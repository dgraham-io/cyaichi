package engine

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"
)

const defaultWorkspaceRoot = "./workspace-data"

type ArtifactRef struct {
	DocID string `json:"doc_id"`
	VerID string `json:"ver_id"`
}

type ArtifactRefWrapper struct {
	ArtifactRef map[string]any `json:"artifact_ref"`
}

type InvocationRecord struct {
	InvocationID string               `json:"invocation_id"`
	NodeID       string               `json:"node_id"`
	Status       string               `json:"status"`
	StartedAt    string               `json:"started_at"`
	EndedAt      string               `json:"ended_at"`
	Inputs       []ArtifactRefWrapper `json:"inputs"`
	Outputs      []ArtifactRefWrapper `json:"outputs"`
}

type NodeRunner interface {
	RunNode(ctx context.Context, req NodeRunRequest) (NodeRunResult, error)
}

type NodeRunRequest struct {
	Node                 FlowNode
	WorkspaceID          string
	WorkspaceRoot        string
	RunID                string
	RunVerID             string
	InputFilePath        string
	InputPathArtifactRef ArtifactRef
}

type NodeRunResult struct {
	Invocation InvocationRecord
	Artifacts  []ArtifactDocument
}

type ArtifactDocument struct {
	DocID     string
	VerID     string
	CreatedAt string
	JSON      string
}

type StubNodeRunner struct{}

func (s StubNodeRunner) RunNode(_ context.Context, req NodeRunRequest) (NodeRunResult, error) {
	now := time.Now().UTC().Format(time.RFC3339)
	inv := InvocationRecord{
		InvocationID: uuid.NewString(),
		NodeID:       req.Node.ID,
		Status:       "succeeded",
		StartedAt:    now,
		EndedAt:      now,
		Inputs:       []ArtifactRefWrapper{},
		Outputs:      []ArtifactRefWrapper{},
	}

	if req.Node.Type != "file.read" {
		return NodeRunResult{Invocation: inv, Artifacts: []ArtifactDocument{}}, nil
	}

	text, err := readWorkspaceFile(req.WorkspaceRoot, req.WorkspaceID, req.InputFilePath)
	if err != nil {
		return NodeRunResult{}, fmt.Errorf("file.read failed: %w", err)
	}

	artifactID := uuid.NewString()
	artifactVerID := uuid.NewString()
	createdAt := time.Now().UTC().Format(time.RFC3339)
	artifactDoc := map[string]any{
		"doc_type":     "artifact",
		"doc_id":       artifactID,
		"ver_id":       artifactVerID,
		"workspace_id": req.WorkspaceID,
		"created_at":   createdAt,
		"body": map[string]any{
			"schema": "artifact/text",
			"payload": map[string]any{
				"text": text,
				"path": req.InputFilePath,
			},
			"provenance": map[string]any{
				"run_ref": map[string]any{
					"doc_id":   req.RunID,
					"ver_id":   req.RunVerID,
					"selector": "pinned",
				},
				"node_id": req.Node.ID,
				"derived_from": []map[string]any{
					{
						"doc_id":   req.InputPathArtifactRef.DocID,
						"ver_id":   req.InputPathArtifactRef.VerID,
						"selector": "pinned",
					},
				},
			},
		},
	}
	artifactBytes, err := json.Marshal(artifactDoc)
	if err != nil {
		return NodeRunResult{}, fmt.Errorf("marshal file.read artifact: %w", err)
	}

	inv.Inputs = []ArtifactRefWrapper{
		{
			ArtifactRef: map[string]any{
				"doc_id":   req.InputPathArtifactRef.DocID,
				"ver_id":   req.InputPathArtifactRef.VerID,
				"selector": "pinned",
			},
		},
	}
	inv.Outputs = []ArtifactRefWrapper{
		{
			ArtifactRef: map[string]any{
				"doc_id":   artifactID,
				"ver_id":   artifactVerID,
				"selector": "pinned",
			},
		},
	}

	return NodeRunResult{
		Invocation: inv,
		Artifacts: []ArtifactDocument{
			{
				DocID:     artifactID,
				VerID:     artifactVerID,
				CreatedAt: createdAt,
				JSON:      string(artifactBytes),
			},
		},
	}, nil
}

func readWorkspaceFile(workspaceRoot, workspaceID, relPath string) (string, error) {
	if strings.TrimSpace(workspaceRoot) == "" {
		workspaceRoot = defaultWorkspaceRoot
	}
	if strings.TrimSpace(relPath) == "" {
		return "", fmt.Errorf("input file path is required")
	}
	if filepath.IsAbs(relPath) {
		return "", fmt.Errorf("input file path must be relative")
	}

	clean := filepath.Clean(relPath)
	if clean == "." || clean == "" || clean == ".." || strings.HasPrefix(clean, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("path traversal is not allowed")
	}

	workspaceDir := filepath.Join(workspaceRoot, workspaceID)
	workspaceDirReal, err := filepath.EvalSymlinks(workspaceDir)
	if err != nil {
		return "", fmt.Errorf("workspace directory is not accessible: %w", err)
	}
	workspaceDirReal = filepath.Clean(workspaceDirReal)

	targetPath := filepath.Join(workspaceDirReal, clean)
	targetReal, err := filepath.EvalSymlinks(targetPath)
	if err != nil {
		return "", fmt.Errorf("input file is not accessible: %w", err)
	}
	targetReal = filepath.Clean(targetReal)

	if !isWithinRoot(workspaceDirReal, targetReal) {
		return "", fmt.Errorf("path escapes workspace root")
	}

	data, err := os.ReadFile(targetReal)
	if err != nil {
		return "", fmt.Errorf("read input file: %w", err)
	}
	return string(data), nil
}

func isWithinRoot(root, path string) bool {
	if root == path {
		return true
	}
	rootWithSep := root
	if !strings.HasSuffix(rootWithSep, string(filepath.Separator)) {
		rootWithSep += string(filepath.Separator)
	}
	return strings.HasPrefix(path, rootWithSep)
}
