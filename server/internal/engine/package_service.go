package engine

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/dgraham-io/cyaichi/server/internal/schema"
	"github.com/dgraham-io/cyaichi/server/internal/store"
	"github.com/google/uuid"
)

type ExportPackageRequest struct {
	WorkspaceID     string        `json:"workspace_id"`
	FlowRef         DocRefRequest `json:"flow_ref"`
	RecommendedHead bool          `json:"recommended_head"`
}

type ExportPackageResponse struct {
	PackageID     string `json:"package_id"`
	PackageVerID  string `json:"package_ver_id"`
	IncludesCount int    `json:"includes_count"`
}

type PackageExportError struct {
	StatusCode int
	Message    string
}

func (e *PackageExportError) Error() string {
	return e.Message
}

type PackageService struct {
	store     *store.Store
	validator *schema.Validator
}

func NewPackageService(store *store.Store, validator *schema.Validator) *PackageService {
	return &PackageService{
		store:     store,
		validator: validator,
	}
}

func (s *PackageService) ExportPackage(ctx context.Context, req ExportPackageRequest) (ExportPackageResponse, error) {
	if _, err := uuid.Parse(req.WorkspaceID); err != nil {
		return ExportPackageResponse{}, &PackageExportError{
			StatusCode: 400,
			Message:    "workspace_id must be a valid UUID",
		}
	}
	if _, err := uuid.Parse(req.FlowRef.DocID); err != nil {
		return ExportPackageResponse{}, &PackageExportError{
			StatusCode: 400,
			Message:    "flow_ref.doc_id must be a valid UUID",
		}
	}

	workspaceDoc, err := s.store.GetLatestWorkspaceDoc(ctx, req.WorkspaceID)
	if errors.Is(err, store.ErrDocumentNotFound) {
		return ExportPackageResponse{}, ErrWorkspaceNotFound
	}
	if err != nil {
		return ExportPackageResponse{}, fmt.Errorf("load workspace: %w", err)
	}
	if workspaceDoc.DocID != req.WorkspaceID || workspaceDoc.WorkspaceID != req.WorkspaceID {
		return ExportPackageResponse{}, ErrWorkspaceNotFound
	}

	rootFlowVerID, err := s.resolveFlowVersion(ctx, req.WorkspaceID, req.FlowRef)
	if err != nil {
		if errors.Is(err, ErrFlowHeadNotFound) {
			return ExportPackageResponse{}, ErrFlowHeadNotFound
		}
		return ExportPackageResponse{}, err
	}

	type include struct {
		DocType string `json:"doc_type"`
		DocID   string `json:"doc_id"`
		VerID   string `json:"ver_id"`
	}
	includes := make([]include, 0)
	seen := map[string]struct{}{}
	addInclude := func(docType, docID, verID string) {
		key := docType + "|" + docID + "|" + verID
		if _, ok := seen[key]; ok {
			return
		}
		seen[key] = struct{}{}
		includes = append(includes, include{
			DocType: docType,
			DocID:   docID,
			VerID:   verID,
		})
	}

	var includeFlowRecursively func(docID, verID string) error
	includeFlowRecursively = func(docID, verID string) error {
		key := "flow|" + docID + "|" + verID
		if _, ok := seen[key]; ok {
			return nil
		}

		flowDoc, err := s.store.GetDocument(ctx, "flow", docID, verID)
		if errors.Is(err, store.ErrDocumentNotFound) {
			return &PackageExportError{
				StatusCode: 400,
				Message:    fmt.Sprintf("flow %s@%s not found", docID, verID),
			}
		}
		if err != nil {
			return fmt.Errorf("load flow %s@%s: %w", docID, verID, err)
		}
		if flowDoc.WorkspaceID != req.WorkspaceID {
			return &PackageExportError{
				StatusCode: 400,
				Message:    fmt.Sprintf("flow %s@%s does not belong to workspace", docID, verID),
			}
		}
		addInclude("flow", docID, verID)

		var parsed struct {
			Body struct {
				Subflows []struct {
					FlowRef DocRefRequest `json:"flow_ref"`
				} `json:"subflows"`
			} `json:"body"`
		}
		if err := json.Unmarshal([]byte(flowDoc.JSON), &parsed); err != nil {
			return &PackageExportError{
				StatusCode: 400,
				Message:    fmt.Sprintf("flow %s@%s contains invalid JSON", docID, verID),
			}
		}

		for _, sub := range parsed.Body.Subflows {
			if _, err := uuid.Parse(sub.FlowRef.DocID); err != nil {
				return &PackageExportError{
					StatusCode: 400,
					Message:    fmt.Sprintf("subflow doc_id %q is not a valid UUID", sub.FlowRef.DocID),
				}
			}
			subflowVerID, err := s.resolveFlowVersion(ctx, req.WorkspaceID, sub.FlowRef)
			if err != nil {
				if errors.Is(err, ErrFlowHeadNotFound) {
					return &PackageExportError{
						StatusCode: 400,
						Message:    fmt.Sprintf("subflow head not found for doc_id %s", sub.FlowRef.DocID),
					}
				}
				return err
			}
			if err := includeFlowRecursively(sub.FlowRef.DocID, subflowVerID); err != nil {
				return err
			}
		}
		return nil
	}

	if err := includeFlowRecursively(req.FlowRef.DocID, rootFlowVerID); err != nil {
		return ExportPackageResponse{}, err
	}

	addInclude("workspace", workspaceDoc.DocID, workspaceDoc.VerID)

	packageID := uuid.NewString()
	packageVerID := uuid.NewString()
	createdAt := time.Now().UTC().Format(time.RFC3339)

	body := map[string]any{
		"format":   "cyaichi-package/v1",
		"includes": includes,
	}
	if req.RecommendedHead {
		body["recommended_heads"] = []map[string]any{
			{
				"doc_id": req.FlowRef.DocID,
				"ver_id": rootFlowVerID,
			},
		}
	}

	packageDoc := map[string]any{
		"doc_type":     "package",
		"doc_id":       packageID,
		"ver_id":       packageVerID,
		"workspace_id": req.WorkspaceID,
		"created_at":   createdAt,
		"body":         body,
	}

	packageBytes, err := json.Marshal(packageDoc)
	if err != nil {
		return ExportPackageResponse{}, fmt.Errorf("marshal package document: %w", err)
	}
	if err := s.validator.Validate(packageBytes); err != nil {
		return ExportPackageResponse{}, &PackageExportError{
			StatusCode: 400,
			Message:    fmt.Sprintf("package schema validation failed: %v", err),
		}
	}

	if err := s.store.PutDocument(ctx, store.Document{
		DocType:     "package",
		DocID:       packageID,
		VerID:       packageVerID,
		WorkspaceID: req.WorkspaceID,
		CreatedAt:   createdAt,
		JSON:        string(packageBytes),
	}); err != nil {
		if errors.Is(err, store.ErrDocumentExists) {
			return ExportPackageResponse{}, &PackageExportError{
				StatusCode: 409,
				Message:    "package document already exists",
			}
		}
		return ExportPackageResponse{}, fmt.Errorf("store package document: %w", err)
	}

	return ExportPackageResponse{
		PackageID:     packageID,
		PackageVerID:  packageVerID,
		IncludesCount: len(includes),
	}, nil
}

func (s *PackageService) resolveFlowVersion(ctx context.Context, workspaceID string, flowRef DocRefRequest) (string, error) {
	switch flowRef.Selector {
	case "pinned":
		if flowRef.VerID == nil || *flowRef.VerID == "" {
			return "", &ValidationError{Message: "flow_ref.ver_id is required when selector is pinned"}
		}
		if _, err := uuid.Parse(*flowRef.VerID); err != nil {
			return "", &ValidationError{Message: "flow_ref.ver_id must be a valid UUID when selector is pinned"}
		}
		return *flowRef.VerID, nil
	case "head":
		if flowRef.VerID != nil {
			return "", &ValidationError{Message: "flow_ref.ver_id must be null when selector is head"}
		}
		verID, err := s.store.GetHead(ctx, workspaceID, flowRef.DocID)
		if errors.Is(err, store.ErrHeadNotFound) {
			return "", ErrFlowHeadNotFound
		}
		if err != nil {
			return "", fmt.Errorf("resolve flow head: %w", err)
		}
		return verID, nil
	default:
		return "", &ValidationError{Message: "flow_ref.selector must be 'pinned' or 'head'"}
	}
}
