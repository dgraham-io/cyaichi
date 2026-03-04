package engine

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/dgraham-io/cyaichi/server/internal/schema"
	"github.com/dgraham-io/cyaichi/server/internal/store"
	"github.com/google/uuid"
)

var (
	ErrWorkspaceNotFound = errors.New("workspace not found")
	ErrFlowHeadNotFound  = errors.New("flow head not found")
	ErrFlowNotFound      = errors.New("flow not found")
)

type ValidationError struct {
	Message string
}

func (e *ValidationError) Error() string {
	return e.Message
}

type UpstreamError struct {
	Message string
}

func (e *UpstreamError) Error() string {
	return e.Message
}

type RunCreateError struct {
	StatusCode int
	Message    string
	RunID      string
	RunVerID   string
}

func (e *RunCreateError) Error() string {
	return e.Message
}

type CreateRunRequest struct {
	WorkspaceID string            `json:"workspace_id"`
	FlowRef     DocRefRequest     `json:"flow_ref"`
	Inputs      map[string]string `json:"inputs"`
}

type DocRefRequest struct {
	DocID    string  `json:"doc_id"`
	VerID    *string `json:"ver_id"`
	Selector string  `json:"selector"`
}

type CreateRunResponse struct {
	RunID    string          `json:"run_id"`
	RunVerID string          `json:"run_ver_id"`
	Flow     PinnedFlowRefID `json:"flow"`
}

type PinnedFlowRefID struct {
	DocID string `json:"doc_id"`
	VerID string `json:"ver_id"`
}

type runFailure struct {
	Message string
	Kind    string
	NodeID  string
}

type RunService struct {
	store         *store.Store
	validator     *schema.Validator
	runner        NodeRunner
	workspaceRoot string
}

func NewRunService(store *store.Store, validator *schema.Validator, runner NodeRunner, workspaceRoot string) *RunService {
	if runner == nil {
		runner = NewDefaultNodeRunner("", "", defaultLLMModel, nil)
	}
	if workspaceRoot == "" {
		workspaceRoot = defaultWorkspaceRoot
	}
	return &RunService{
		store:         store,
		validator:     validator,
		runner:        runner,
		workspaceRoot: workspaceRoot,
	}
}

func (s *RunService) CreateRun(ctx context.Context, req CreateRunRequest) (CreateRunResponse, error) {
	if _, err := uuid.Parse(req.WorkspaceID); err != nil {
		return CreateRunResponse{}, &ValidationError{Message: "workspace_id must be a valid UUID"}
	}
	if _, err := uuid.Parse(req.FlowRef.DocID); err != nil {
		return CreateRunResponse{}, &ValidationError{Message: "flow_ref.doc_id must be a valid UUID"}
	}

	workspaceDoc, err := s.store.GetLatestWorkspaceDoc(ctx, req.WorkspaceID)
	if errors.Is(err, store.ErrDocumentNotFound) {
		return CreateRunResponse{}, ErrWorkspaceNotFound
	}
	if err != nil {
		return CreateRunResponse{}, fmt.Errorf("load workspace: %w", err)
	}
	if workspaceDoc.DocID != req.WorkspaceID || workspaceDoc.WorkspaceID != req.WorkspaceID {
		return CreateRunResponse{}, ErrWorkspaceNotFound
	}

	flowVerID, err := s.resolveFlowVersion(ctx, req.WorkspaceID, req.FlowRef)
	if err != nil {
		return CreateRunResponse{}, err
	}

	flowDoc, err := s.store.GetDocument(ctx, "flow", req.FlowRef.DocID, flowVerID)
	if errors.Is(err, store.ErrDocumentNotFound) {
		return CreateRunResponse{}, ErrFlowNotFound
	}
	if err != nil {
		return CreateRunResponse{}, fmt.Errorf("load flow document: %w", err)
	}
	if flowDoc.WorkspaceID != req.WorkspaceID {
		return CreateRunResponse{}, &ValidationError{Message: "flow does not belong to workspace"}
	}

	runID := uuid.NewString()
	runVerID := uuid.NewString()
	startedAt := time.Now().UTC().Format(time.RFC3339)
	invocations := make([]map[string]any, 0)

	failAndReturn := func(statusCode int, failure runFailure) (CreateRunResponse, error) {
		if persistErr := s.persistFailedRun(ctx, req, flowVerID, runID, runVerID, startedAt, invocations, failure); persistErr != nil {
			return CreateRunResponse{}, fmt.Errorf("persist failed run: %w", persistErr)
		}
		return CreateRunResponse{}, &RunCreateError{
			StatusCode: statusCode,
			Message:    failure.Message,
			RunID:      runID,
			RunVerID:   runVerID,
		}
	}

	if err := s.validator.Validate([]byte(flowDoc.JSON)); err != nil {
		return failAndReturn(http.StatusBadRequest, runFailure{
			Message: fmt.Sprintf("flow schema validation failed: %v", err),
			Kind:    "validation",
		})
	}

	parsedFlow, err := ParseFlowDocument(flowDoc.JSON)
	if err != nil {
		return failAndReturn(http.StatusBadRequest, runFailure{
			Message: err.Error(),
			Kind:    "validation",
		})
	}

	executionOrder, err := ValidateRunnableFlow(parsedFlow)
	if err != nil {
		return failAndReturn(http.StatusBadRequest, runFailure{
			Message: err.Error(),
			Kind:    "validation",
		})
	}

	inputPath := req.Inputs["input_file"]
	if inputPath == "" {
		return failAndReturn(http.StatusBadRequest, runFailure{
			Message: "inputs.input_file is required",
			Kind:    "validation",
		})
	}
	outputPath := req.Inputs["output_file"]

	artifactID := uuid.NewString()
	artifactVerID := uuid.NewString()
	artifactDocMap := map[string]any{
		"doc_type":     "artifact",
		"doc_id":       artifactID,
		"ver_id":       artifactVerID,
		"workspace_id": req.WorkspaceID,
		"created_at":   startedAt,
		"body": map[string]any{
			"schema": "artifact/input_file",
			"payload": map[string]any{
				"path": inputPath,
			},
			"provenance": map[string]any{
				"run_ref": map[string]any{
					"doc_id":   runID,
					"ver_id":   runVerID,
					"selector": "pinned",
				},
				"node_id": "__run_input__",
			},
		},
	}
	artifactBytes, err := json.Marshal(artifactDocMap)
	if err != nil {
		return failAndReturn(http.StatusInternalServerError, runFailure{
			Message: "failed to encode input artifact",
			Kind:    "internal",
		})
	}
	if err := s.validator.Validate(artifactBytes); err != nil {
		return failAndReturn(http.StatusBadRequest, runFailure{
			Message: err.Error(),
			Kind:    "validation",
		})
	}

	pendingArtifacts := []store.Document{{
		DocType:     "artifact",
		DocID:       artifactID,
		VerID:       artifactVerID,
		WorkspaceID: req.WorkspaceID,
		CreatedAt:   startedAt,
		JSON:        string(artifactBytes),
	}}

	latestArtifact := &ResolvedArtifact{
		Ref: ArtifactRef{
			DocID: artifactID,
			VerID: artifactVerID,
		},
		Schema: "artifact/input_file",
	}

	for _, node := range executionOrder {
		result, err := s.runner.RunNode(ctx, NodeRunRequest{
			Node:                 node,
			WorkspaceID:          req.WorkspaceID,
			WorkspaceRoot:        s.workspaceRoot,
			RunID:                runID,
			RunVerID:             runVerID,
			InputFilePath:        inputPath,
			OutputFilePath:       outputPath,
			InputPathArtifactRef: ArtifactRef{DocID: artifactID, VerID: artifactVerID},
			UpstreamArtifact:     latestArtifact,
		})
		if err != nil {
			failure := runFailure{
				Message: err.Error(),
				Kind:    "internal",
				NodeID:  node.ID,
			}
			statusCode := http.StatusInternalServerError

			var upstreamErr *UpstreamError
			if errors.As(err, &upstreamErr) {
				failure.Message = upstreamErr.Message
				failure.Kind = "llm"
				statusCode = http.StatusBadGateway
			}
			var validationErr *ValidationError
			if errors.As(err, &validationErr) {
				failure.Message = validationErr.Message
				failure.Kind = "validation"
				statusCode = http.StatusBadRequest
				if strings.Contains(strings.ToLower(validationErr.Message), "file.read failed") ||
					strings.Contains(strings.ToLower(validationErr.Message), "file.write failed") {
					failure.Kind = "io"
				}
			}

			now := time.Now().UTC().Format(time.RFC3339)
			failedInvocation := map[string]any{
				"invocation_id": uuid.NewString(),
				"node_id":       node.ID,
				"status":        "failed",
				"started_at":    now,
				"ended_at":      now,
				"inputs":        []ArtifactRefWrapper{},
				"outputs":       []ArtifactRefWrapper{},
			}
			if latestArtifact != nil {
				failedInvocation["inputs"] = []ArtifactRefWrapper{
					{
						ArtifactRef: map[string]any{
							"doc_id":   latestArtifact.Ref.DocID,
							"ver_id":   latestArtifact.Ref.VerID,
							"selector": "pinned",
						},
					},
				}
			}
			invocations = append(invocations, failedInvocation)

			return failAndReturn(statusCode, failure)
		}

		for _, artifact := range result.Artifacts {
			if err := s.validator.Validate([]byte(artifact.JSON)); err != nil {
				return failAndReturn(http.StatusBadRequest, runFailure{
					Message: fmt.Sprintf("artifact schema validation failed: %v", err),
					Kind:    "validation",
					NodeID:  node.ID,
				})
			}
			pendingArtifacts = append(pendingArtifacts, store.Document{
				DocType:     "artifact",
				DocID:       artifact.DocID,
				VerID:       artifact.VerID,
				WorkspaceID: req.WorkspaceID,
				CreatedAt:   artifact.CreatedAt,
				JSON:        artifact.JSON,
			})
		}

		invocations = append(invocations, map[string]any{
			"invocation_id": result.Invocation.InvocationID,
			"node_id":       result.Invocation.NodeID,
			"status":        result.Invocation.Status,
			"started_at":    result.Invocation.StartedAt,
			"ended_at":      result.Invocation.EndedAt,
			"inputs":        result.Invocation.Inputs,
			"outputs":       result.Invocation.Outputs,
		})
		if result.NextArtifact != nil {
			latestArtifact = result.NextArtifact
		}
	}

	endedAt := time.Now().UTC().Format(time.RFC3339)
	runOutputs := []map[string]any{}
	if latestArtifact != nil && (latestArtifact.Ref.DocID != artifactID || latestArtifact.Ref.VerID != artifactVerID) {
		runOutputs = append(runOutputs, map[string]any{
			"artifact_ref": map[string]any{
				"doc_id":   latestArtifact.Ref.DocID,
				"ver_id":   latestArtifact.Ref.VerID,
				"selector": "pinned",
			},
		})
	}

	runDocMap := map[string]any{
		"doc_type":     "run",
		"doc_id":       runID,
		"ver_id":       runVerID,
		"workspace_id": req.WorkspaceID,
		"created_at":   startedAt,
		"body": map[string]any{
			"flow_ref": map[string]any{
				"doc_id":   req.FlowRef.DocID,
				"ver_id":   flowVerID,
				"selector": "pinned",
			},
			"mode":       "hybrid",
			"status":     "succeeded",
			"started_at": startedAt,
			"ended_at":   endedAt,
			"inputs": []map[string]any{
				{
					"artifact_ref": map[string]any{
						"doc_id":   artifactID,
						"ver_id":   artifactVerID,
						"selector": "pinned",
					},
				},
			},
			"outputs":     runOutputs,
			"invocations": invocations,
		},
	}
	runBytes, err := json.Marshal(runDocMap)
	if err != nil {
		return CreateRunResponse{}, fmt.Errorf("marshal run document: %w", err)
	}
	if err := s.validator.Validate(runBytes); err != nil {
		return CreateRunResponse{}, &ValidationError{Message: err.Error()}
	}
	for _, artifactDoc := range pendingArtifacts {
		if err := s.store.PutDocument(ctx, artifactDoc); err != nil {
			return CreateRunResponse{}, fmt.Errorf("store artifact document: %w", err)
		}
	}
	if err := s.store.PutDocument(ctx, store.Document{
		DocType:     "run",
		DocID:       runID,
		VerID:       runVerID,
		WorkspaceID: req.WorkspaceID,
		CreatedAt:   startedAt,
		JSON:        string(runBytes),
	}); err != nil {
		return CreateRunResponse{}, fmt.Errorf("store run document: %w", err)
	}

	return CreateRunResponse{
		RunID:    runID,
		RunVerID: runVerID,
		Flow: PinnedFlowRefID{
			DocID: req.FlowRef.DocID,
			VerID: flowVerID,
		},
	}, nil
}

func (s *RunService) persistFailedRun(
	ctx context.Context,
	req CreateRunRequest,
	flowVerID, runID, runVerID, startedAt string,
	invocations []map[string]any,
	failure runFailure,
) error {
	endedAt := time.Now().UTC().Format(time.RFC3339)
	errorObject := map[string]any{
		"message": failure.Message,
		"kind":    failure.Kind,
	}
	if failure.NodeID != "" {
		errorObject["node_id"] = failure.NodeID
	}

	runDocMap := map[string]any{
		"doc_type":     "run",
		"doc_id":       runID,
		"ver_id":       runVerID,
		"workspace_id": req.WorkspaceID,
		"created_at":   startedAt,
		"body": map[string]any{
			"flow_ref": map[string]any{
				"doc_id":   req.FlowRef.DocID,
				"ver_id":   flowVerID,
				"selector": "pinned",
			},
			"mode":       "hybrid",
			"status":     "failed",
			"started_at": startedAt,
			"ended_at":   endedAt,
			"invocations": func() []map[string]any {
				if invocations == nil {
					return []map[string]any{}
				}
				return invocations
			}(),
			"trace_ref": map[string]any{
				"error": errorObject,
			},
		},
	}

	runBytes, err := json.Marshal(runDocMap)
	if err != nil {
		return fmt.Errorf("marshal failed run document: %w", err)
	}
	if err := s.validator.Validate(runBytes); err != nil {
		return fmt.Errorf("validate failed run document: %w", err)
	}
	if err := s.store.PutDocument(ctx, store.Document{
		DocType:     "run",
		DocID:       runID,
		VerID:       runVerID,
		WorkspaceID: req.WorkspaceID,
		CreatedAt:   startedAt,
		JSON:        string(runBytes),
	}); err != nil {
		return fmt.Errorf("store failed run document: %w", err)
	}
	return nil
}

func (s *RunService) resolveFlowVersion(ctx context.Context, workspaceID string, flowRef DocRefRequest) (string, error) {
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
