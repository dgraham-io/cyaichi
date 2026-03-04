package engine

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"
)

const (
	defaultWorkspaceRoot = "./workspace-data"
	defaultLLMModel      = "gpt-oss120:b"
)

type ArtifactRef struct {
	DocID string `json:"doc_id"`
	VerID string `json:"ver_id"`
}

type ArtifactRefWrapper struct {
	ArtifactRef map[string]any `json:"artifact_ref"`
}

type ResolvedArtifact struct {
	Ref    ArtifactRef
	Schema string
	Text   string
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
	OutputFilePath       string
	InputPathArtifactRef ArtifactRef
	UpstreamArtifact     *ResolvedArtifact
}

type NodeRunResult struct {
	Invocation   InvocationRecord
	Artifacts    []ArtifactDocument
	NextArtifact *ResolvedArtifact
}

type ArtifactDocument struct {
	DocID     string
	VerID     string
	CreatedAt string
	JSON      string
}

type LLMChatClient interface {
	Chat(ctx context.Context, model string, userText string) (string, error)
}

type DefaultNodeRunner struct {
	llmClient    LLMChatClient
	defaultModel string
}

func NewDefaultNodeRunner(baseURL, apiKey, model string, httpClient *http.Client) *DefaultNodeRunner {
	if model == "" {
		model = defaultLLMModel
	}
	if httpClient == nil {
		httpClient = &http.Client{Timeout: 30 * time.Second}
	}
	return &DefaultNodeRunner{
		llmClient:    &VLLMChatClient{baseURL: baseURL, apiKey: apiKey, httpClient: httpClient},
		defaultModel: model,
	}
}

func (r *DefaultNodeRunner) RunNode(ctx context.Context, req NodeRunRequest) (NodeRunResult, error) {
	switch req.Node.Type {
	case "file.read":
		return r.runFileRead(ctx, req)
	case "llm.chat":
		return r.runLLMChat(ctx, req)
	case "file.write":
		return r.runFileWrite(ctx, req)
	default:
		now := time.Now().UTC().Format(time.RFC3339)
		return NodeRunResult{
			Invocation: InvocationRecord{
				InvocationID: uuid.NewString(),
				NodeID:       req.Node.ID,
				Status:       "succeeded",
				StartedAt:    now,
				EndedAt:      now,
				Inputs:       []ArtifactRefWrapper{},
				Outputs:      []ArtifactRefWrapper{},
			},
			Artifacts:    []ArtifactDocument{},
			NextArtifact: nil,
		}, nil
	}
}

func (r *DefaultNodeRunner) runFileRead(_ context.Context, req NodeRunRequest) (NodeRunResult, error) {
	now := time.Now().UTC().Format(time.RFC3339)

	text, err := readWorkspaceFile(req.WorkspaceRoot, req.WorkspaceID, req.InputFilePath)
	if err != nil {
		return NodeRunResult{}, &ValidationError{Message: fmt.Sprintf("file.read failed: %v", err)}
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

	return NodeRunResult{
		Invocation: InvocationRecord{
			InvocationID: uuid.NewString(),
			NodeID:       req.Node.ID,
			Status:       "succeeded",
			StartedAt:    now,
			EndedAt:      time.Now().UTC().Format(time.RFC3339),
			Inputs: []ArtifactRefWrapper{
				{
					ArtifactRef: map[string]any{
						"doc_id":   req.InputPathArtifactRef.DocID,
						"ver_id":   req.InputPathArtifactRef.VerID,
						"selector": "pinned",
					},
				},
			},
			Outputs: []ArtifactRefWrapper{
				{
					ArtifactRef: map[string]any{
						"doc_id":   artifactID,
						"ver_id":   artifactVerID,
						"selector": "pinned",
					},
				},
			},
		},
		Artifacts: []ArtifactDocument{
			{
				DocID:     artifactID,
				VerID:     artifactVerID,
				CreatedAt: createdAt,
				JSON:      string(artifactBytes),
			},
		},
		NextArtifact: &ResolvedArtifact{
			Ref: ArtifactRef{
				DocID: artifactID,
				VerID: artifactVerID,
			},
			Schema: "artifact/text",
			Text:   text,
		},
	}, nil
}

func (r *DefaultNodeRunner) runLLMChat(ctx context.Context, req NodeRunRequest) (NodeRunResult, error) {
	now := time.Now().UTC().Format(time.RFC3339)

	if req.UpstreamArtifact == nil {
		return NodeRunResult{}, &ValidationError{Message: "llm.chat requires an upstream artifact"}
	}
	if req.UpstreamArtifact.Schema != "artifact/text" {
		return NodeRunResult{}, &ValidationError{Message: "llm.chat requires upstream artifact schema artifact/text"}
	}
	if strings.TrimSpace(req.UpstreamArtifact.Text) == "" {
		return NodeRunResult{}, &ValidationError{Message: "llm.chat requires non-empty input text"}
	}

	model := r.defaultModel
	if req.Node.Config != nil {
		if raw, ok := req.Node.Config["model"]; ok {
			if configModel, ok := raw.(string); ok && strings.TrimSpace(configModel) != "" {
				model = configModel
			}
		}
	}

	outputText, err := r.llmClient.Chat(ctx, model, req.UpstreamArtifact.Text)
	if err != nil {
		return NodeRunResult{}, &UpstreamError{Message: fmt.Sprintf("llm.chat failed: %v", err)}
	}
	if strings.TrimSpace(outputText) == "" {
		return NodeRunResult{}, &UpstreamError{Message: "llm.chat returned empty content"}
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
				"text":  outputText,
				"model": model,
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
						"doc_id":   req.UpstreamArtifact.Ref.DocID,
						"ver_id":   req.UpstreamArtifact.Ref.VerID,
						"selector": "pinned",
					},
				},
			},
		},
	}
	artifactBytes, err := json.Marshal(artifactDoc)
	if err != nil {
		return NodeRunResult{}, fmt.Errorf("marshal llm.chat artifact: %w", err)
	}

	return NodeRunResult{
		Invocation: InvocationRecord{
			InvocationID: uuid.NewString(),
			NodeID:       req.Node.ID,
			Status:       "succeeded",
			StartedAt:    now,
			EndedAt:      time.Now().UTC().Format(time.RFC3339),
			Inputs: []ArtifactRefWrapper{
				{
					ArtifactRef: map[string]any{
						"doc_id":   req.UpstreamArtifact.Ref.DocID,
						"ver_id":   req.UpstreamArtifact.Ref.VerID,
						"selector": "pinned",
					},
				},
			},
			Outputs: []ArtifactRefWrapper{
				{
					ArtifactRef: map[string]any{
						"doc_id":   artifactID,
						"ver_id":   artifactVerID,
						"selector": "pinned",
					},
				},
			},
		},
		Artifacts: []ArtifactDocument{
			{
				DocID:     artifactID,
				VerID:     artifactVerID,
				CreatedAt: createdAt,
				JSON:      string(artifactBytes),
			},
		},
		NextArtifact: &ResolvedArtifact{
			Ref: ArtifactRef{
				DocID: artifactID,
				VerID: artifactVerID,
			},
			Schema: "artifact/text",
			Text:   outputText,
		},
	}, nil
}

func (r *DefaultNodeRunner) runFileWrite(_ context.Context, req NodeRunRequest) (NodeRunResult, error) {
	now := time.Now().UTC().Format(time.RFC3339)

	if req.UpstreamArtifact == nil {
		return NodeRunResult{}, &ValidationError{Message: "file.write requires an upstream artifact"}
	}
	if req.UpstreamArtifact.Schema != "artifact/text" {
		return NodeRunResult{}, &ValidationError{Message: "file.write requires upstream artifact schema artifact/text"}
	}
	if req.OutputFilePath == "" {
		return NodeRunResult{}, &ValidationError{Message: "inputs.output_file is required for file.write"}
	}

	writtenBytes, err := writeWorkspaceFile(req.WorkspaceRoot, req.WorkspaceID, req.OutputFilePath, req.UpstreamArtifact.Text)
	if err != nil {
		return NodeRunResult{}, &ValidationError{Message: fmt.Sprintf("file.write failed: %v", err)}
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
			"schema": "artifact/output_file",
			"payload": map[string]any{
				"path":  req.OutputFilePath,
				"bytes": writtenBytes,
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
						"doc_id":   req.UpstreamArtifact.Ref.DocID,
						"ver_id":   req.UpstreamArtifact.Ref.VerID,
						"selector": "pinned",
					},
				},
			},
		},
	}
	artifactBytes, err := json.Marshal(artifactDoc)
	if err != nil {
		return NodeRunResult{}, fmt.Errorf("marshal file.write artifact: %w", err)
	}

	return NodeRunResult{
		Invocation: InvocationRecord{
			InvocationID: uuid.NewString(),
			NodeID:       req.Node.ID,
			Status:       "succeeded",
			StartedAt:    now,
			EndedAt:      time.Now().UTC().Format(time.RFC3339),
			Inputs: []ArtifactRefWrapper{
				{
					ArtifactRef: map[string]any{
						"doc_id":   req.UpstreamArtifact.Ref.DocID,
						"ver_id":   req.UpstreamArtifact.Ref.VerID,
						"selector": "pinned",
					},
				},
			},
			Outputs: []ArtifactRefWrapper{
				{
					ArtifactRef: map[string]any{
						"doc_id":   artifactID,
						"ver_id":   artifactVerID,
						"selector": "pinned",
					},
				},
			},
		},
		Artifacts: []ArtifactDocument{
			{
				DocID:     artifactID,
				VerID:     artifactVerID,
				CreatedAt: createdAt,
				JSON:      string(artifactBytes),
			},
		},
		NextArtifact: &ResolvedArtifact{
			Ref: ArtifactRef{
				DocID: artifactID,
				VerID: artifactVerID,
			},
			Schema: "artifact/output_file",
		},
	}, nil
}

type VLLMChatClient struct {
	baseURL    string
	apiKey     string
	httpClient *http.Client
}

func (c *VLLMChatClient) Chat(ctx context.Context, model string, userText string) (string, error) {
	if strings.TrimSpace(c.baseURL) == "" {
		return "", fmt.Errorf("CYAI_VLLM_BASE_URL is required for llm.chat")
	}
	if strings.TrimSpace(c.apiKey) == "" {
		return "", fmt.Errorf("VLLM_KEY is required for llm.chat")
	}
	if strings.TrimSpace(model) == "" {
		model = defaultLLMModel
	}

	body := map[string]any{
		"model": model,
		"messages": []map[string]string{
			{
				"role":    "user",
				"content": userText,
			},
		},
		"temperature": 0.2,
	}
	bodyBytes, err := json.Marshal(body)
	if err != nil {
		return "", fmt.Errorf("marshal chat request: %w", err)
	}

	url := strings.TrimRight(c.baseURL, "/") + "/v1/chat/completions"
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(bodyBytes))
	if err != nil {
		return "", fmt.Errorf("build chat request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+c.apiKey)

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return "", fmt.Errorf("chat request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("read chat response: %w", err)
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		msg := string(respBody)
		if len(msg) > 300 {
			msg = msg[:300]
		}
		return "", fmt.Errorf("chat API status %d: %s", resp.StatusCode, msg)
	}

	var parsed struct {
		Choices []struct {
			Message struct {
				Content any `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return "", fmt.Errorf("parse chat response: %w", err)
	}
	if len(parsed.Choices) == 0 {
		return "", fmt.Errorf("chat response missing choices")
	}

	switch content := parsed.Choices[0].Message.Content.(type) {
	case string:
		if strings.TrimSpace(content) == "" {
			return "", fmt.Errorf("chat response content is empty")
		}
		return content, nil
	default:
		return "", fmt.Errorf("chat response content is not a string")
	}
}

func readWorkspaceFile(workspaceRoot, workspaceID, relPath string) (string, error) {
	rootReal, workspaceDirReal, clean, err := resolveWorkspacePath(workspaceRoot, workspaceID, relPath, false)
	if err != nil {
		return "", err
	}
	_ = rootReal
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

func writeWorkspaceFile(workspaceRoot, workspaceID, relPath, text string) (int, error) {
	_, workspaceDirReal, clean, err := resolveWorkspacePath(workspaceRoot, workspaceID, relPath, true)
	if err != nil {
		return 0, err
	}

	targetPath := filepath.Join(workspaceDirReal, clean)
	parentDir := filepath.Dir(targetPath)
	if err := os.MkdirAll(parentDir, 0o755); err != nil {
		return 0, fmt.Errorf("create output directory: %w", err)
	}

	parentReal, err := filepath.EvalSymlinks(parentDir)
	if err != nil {
		return 0, fmt.Errorf("output directory is not accessible: %w", err)
	}
	parentReal = filepath.Clean(parentReal)
	if !isWithinRoot(workspaceDirReal, parentReal) {
		return 0, fmt.Errorf("output path escapes workspace root")
	}

	bytes := []byte(text)
	if err := os.WriteFile(targetPath, bytes, 0o644); err != nil {
		return 0, fmt.Errorf("write output file: %w", err)
	}
	return len(bytes), nil
}

func resolveWorkspacePath(workspaceRoot, workspaceID, relPath string, allowCreateWorkspaceDir bool) (rootReal, workspaceDirReal, clean string, err error) {
	if strings.TrimSpace(workspaceRoot) == "" {
		workspaceRoot = defaultWorkspaceRoot
	}
	if strings.TrimSpace(relPath) == "" {
		return "", "", "", fmt.Errorf("path is required")
	}
	if filepath.IsAbs(relPath) {
		return "", "", "", fmt.Errorf("path must be relative")
	}

	clean = filepath.Clean(relPath)
	if clean == "." || clean == "" || clean == ".." || strings.HasPrefix(clean, ".."+string(filepath.Separator)) {
		return "", "", "", fmt.Errorf("path traversal is not allowed")
	}

	if allowCreateWorkspaceDir {
		if err := os.MkdirAll(workspaceRoot, 0o755); err != nil {
			return "", "", "", fmt.Errorf("workspace root is not writable: %w", err)
		}
	}
	rootReal, err = filepath.EvalSymlinks(workspaceRoot)
	if err != nil {
		return "", "", "", fmt.Errorf("workspace root is not accessible: %w", err)
	}
	rootReal = filepath.Clean(rootReal)

	workspaceDir := filepath.Join(rootReal, workspaceID)
	if allowCreateWorkspaceDir {
		if err := os.MkdirAll(workspaceDir, 0o755); err != nil {
			return "", "", "", fmt.Errorf("workspace directory is not writable: %w", err)
		}
	}
	workspaceDirReal, err = filepath.EvalSymlinks(workspaceDir)
	if err != nil {
		return "", "", "", fmt.Errorf("workspace directory is not accessible: %w", err)
	}
	workspaceDirReal = filepath.Clean(workspaceDirReal)
	if !isWithinRoot(rootReal, workspaceDirReal) {
		return "", "", "", fmt.Errorf("workspace directory escapes workspace root")
	}
	return rootReal, workspaceDirReal, clean, nil
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
