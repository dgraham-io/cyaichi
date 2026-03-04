package httpapi

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/google/uuid"
)

type workspaceCreateResponse struct {
	WorkspaceID string `json:"workspace_id"`
	DocID       string `json:"doc_id"`
	VerID       string `json:"ver_id"`
}

func createWorkspaceViaAPI(t *testing.T, h *apiTestHarness, name string) workspaceCreateResponse {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/v1/workspaces", strings.NewReader(`{"name":"`+name+`"}`))
	req.Header.Set("Content-Type", "application/json")
	rr := httptest.NewRecorder()
	h.mux.ServeHTTP(rr, req)
	if rr.Code != http.StatusCreated {
		t.Fatalf("create workspace failed: status=%d body=%s", rr.Code, rr.Body.String())
	}
	var resp workspaceCreateResponse
	if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode create workspace response: %v", err)
	}
	return resp
}

func putFlowDocViaAPI(t *testing.T, h *apiTestHarness, workspaceID, flowDocID, flowVerID string, flowBody string) {
	t.Helper()
	flowDoc := `{
	  "doc_type": "flow",
	  "doc_id": "` + flowDocID + `",
	  "ver_id": "` + flowVerID + `",
	  "workspace_id": "` + workspaceID + `",
	  "created_at": "2026-03-03T00:00:00Z",
	  "body": ` + flowBody + `
	}`
	req := httptest.NewRequest(http.MethodPut, "/v1/docs/flow/"+flowDocID+"/"+flowVerID, strings.NewReader(flowDoc))
	req.Header.Set("Content-Type", "application/json")
	rr := httptest.NewRecorder()
	h.mux.ServeHTTP(rr, req)
	if rr.Code != http.StatusCreated {
		t.Fatalf("put flow failed: status=%d body=%s", rr.Code, rr.Body.String())
	}
}

func setWorkspaceHeadViaAPI(t *testing.T, h *apiTestHarness, workspaceID, docID, verID string) {
	t.Helper()
	req := httptest.NewRequest(http.MethodPut, "/v1/workspaces/"+workspaceID+"/heads/"+docID, strings.NewReader(`{"ver_id":"`+verID+`"}`))
	req.Header.Set("Content-Type", "application/json")
	rr := httptest.NewRecorder()
	h.mux.ServeHTTP(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("set head failed: status=%d body=%s", rr.Code, rr.Body.String())
	}
}

func postRunViaAPI(t *testing.T, h *apiTestHarness, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/v1/runs", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rr := httptest.NewRecorder()
	h.mux.ServeHTTP(rr, req)
	return rr
}

func writeWorkspaceInputFile(t *testing.T, h *apiTestHarness, workspaceID, relPath, contents string) {
	t.Helper()
	fullPath := filepath.Join(h.workspaceRoot, workspaceID, relPath)
	if err := os.MkdirAll(filepath.Dir(fullPath), 0o755); err != nil {
		t.Fatalf("mkdir workspace input dir: %v", err)
	}
	if err := os.WriteFile(fullPath, []byte(contents), 0o644); err != nil {
		t.Fatalf("write workspace input file: %v", err)
	}
}

type mockChatRequest struct {
	Authorization string
	Model         string
	Role          string
	Content       string
	Temperature   float64
}

func newMockVLLMServer(t *testing.T, responseStatus int, responseBody string) (*httptest.Server, *mockChatRequest) {
	t.Helper()

	var mu sync.Mutex
	captured := &mockChatRequest{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/v1/chat/completions" {
			http.Error(w, "not found", http.StatusNotFound)
			return
		}

		bodyBytes, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, "read error", http.StatusBadRequest)
			return
		}

		var payload struct {
			Model    string `json:"model"`
			Messages []struct {
				Role    string `json:"role"`
				Content string `json:"content"`
			} `json:"messages"`
			Temperature float64 `json:"temperature"`
		}
		if err := json.Unmarshal(bodyBytes, &payload); err != nil {
			http.Error(w, "bad json", http.StatusBadRequest)
			return
		}

		mu.Lock()
		captured.Authorization = r.Header.Get("Authorization")
		captured.Model = payload.Model
		captured.Temperature = payload.Temperature
		if len(payload.Messages) > 0 {
			captured.Role = payload.Messages[0].Role
			captured.Content = payload.Messages[0].Content
		}
		mu.Unlock()

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(responseStatus)
		_, _ = w.Write([]byte(responseBody))
	}))

	t.Cleanup(server.Close)
	return server, captured
}

func TestRunsSelectorHeadResolvesThroughHeadsTable(t *testing.T) {
	h := newAPITestHarness(t)
	workspace := createWorkspaceViaAPI(t, h, "Runs Head Workspace")

	flowDocID := uuid.NewString()
	flowVerID := uuid.NewString()
	flowBody := `{
	  "nodes": [
	    {"id":"n1","type":"node.in","inputs":[],"outputs":[{"port":"out","schema":"artifact/text"}],"config":{}},
	    {"id":"n2","type":"node.out","inputs":[{"port":"in","schema":"artifact/text"}],"outputs":[],"config":{}}
	  ],
	  "edges": [
	    {"from":{"node":"n1","port":"out"},"to":{"node":"n2","port":"in"}}
	  ]
	}`
	putFlowDocViaAPI(t, h, workspace.WorkspaceID, flowDocID, flowVerID, flowBody)
	setWorkspaceHeadViaAPI(t, h, workspace.WorkspaceID, flowDocID, flowVerID)
	writeWorkspaceInputFile(t, h, workspace.WorkspaceID, "input.txt", "hello run")

	runReq := `{
	  "workspace_id":"` + workspace.WorkspaceID + `",
	  "flow_ref":{"doc_id":"` + flowDocID + `","ver_id":null,"selector":"head"},
	  "inputs":{"input_file":"input.txt","output_file":"output.txt"}
	}`
	rr := postRunViaAPI(t, h, runReq)
	if rr.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d body=%s", http.StatusCreated, rr.Code, rr.Body.String())
	}

	var resp struct {
		Flow struct {
			DocID string `json:"doc_id"`
			VerID string `json:"ver_id"`
		} `json:"flow"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode run response: %v", err)
	}
	if resp.Flow.DocID != flowDocID || resp.Flow.VerID != flowVerID {
		t.Fatalf("expected resolved flow %s@%s, got %s@%s", flowDocID, flowVerID, resp.Flow.DocID, resp.Flow.VerID)
	}
}

func TestRunsMissingHeadReturnsNotFound(t *testing.T) {
	h := newAPITestHarness(t)
	workspace := createWorkspaceViaAPI(t, h, "Runs Missing Head")

	flowDocID := uuid.NewString()
	flowVerID := uuid.NewString()
	flowBody := `{
	  "nodes": [
	    {"id":"n1","type":"node.in","inputs":[],"outputs":[{"port":"out","schema":"artifact/text"}],"config":{}},
	    {"id":"n2","type":"node.out","inputs":[{"port":"in","schema":"artifact/text"}],"outputs":[],"config":{}}
	  ],
	  "edges": [
	    {"from":{"node":"n1","port":"out"},"to":{"node":"n2","port":"in"}}
	  ]
	}`
	putFlowDocViaAPI(t, h, workspace.WorkspaceID, flowDocID, flowVerID, flowBody)

	runReq := `{
	  "workspace_id":"` + workspace.WorkspaceID + `",
	  "flow_ref":{"doc_id":"` + flowDocID + `","ver_id":null,"selector":"head"},
	  "inputs":{"input_file":"input.txt","output_file":"output.txt"}
	}`
	rr := postRunViaAPI(t, h, runReq)
	if rr.Code != http.StatusNotFound {
		t.Fatalf("expected status %d, got %d body=%s", http.StatusNotFound, rr.Code, rr.Body.String())
	}
}

func TestRunsInvalidFlowReturnsBadRequest(t *testing.T) {
	tests := []struct {
		name      string
		flowBody  string
		errSubstr string
	}{
		{
			name: "cycle",
			flowBody: `{
			  "nodes": [
			    {"id":"a","type":"node.a","inputs":[{"port":"in","schema":"artifact/text"}],"outputs":[{"port":"out","schema":"artifact/text"}],"config":{}},
			    {"id":"b","type":"node.b","inputs":[{"port":"in","schema":"artifact/text"}],"outputs":[{"port":"out","schema":"artifact/text"}],"config":{}}
			  ],
			  "edges": [
			    {"from":{"node":"a","port":"out"},"to":{"node":"b","port":"in"}},
			    {"from":{"node":"b","port":"out"},"to":{"node":"a","port":"in"}}
			  ]
			}`,
			errSubstr: "cycle",
		},
		{
			name: "missing node",
			flowBody: `{
			  "nodes": [
			    {"id":"a","type":"node.a","inputs":[],"outputs":[{"port":"out","schema":"artifact/text"}],"config":{}}
			  ],
			  "edges": [
			    {"from":{"node":"a","port":"out"},"to":{"node":"missing","port":"in"}}
			  ]
			}`,
			errSubstr: "missing target node",
		},
		{
			name: "bad port",
			flowBody: `{
			  "nodes": [
			    {"id":"a","type":"node.a","inputs":[],"outputs":[{"port":"out","schema":"artifact/text"}],"config":{}},
			    {"id":"b","type":"node.b","inputs":[{"port":"in","schema":"artifact/text"}],"outputs":[],"config":{}}
			  ],
			  "edges": [
			    {"from":{"node":"a","port":"bad"},"to":{"node":"b","port":"in"}}
			  ]
			}`,
			errSubstr: "missing source output port",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			h := newAPITestHarness(t)
			workspace := createWorkspaceViaAPI(t, h, "Runs Invalid "+tc.name)

			flowDocID := uuid.NewString()
			flowVerID := uuid.NewString()
			putFlowDocViaAPI(t, h, workspace.WorkspaceID, flowDocID, flowVerID, tc.flowBody)
			setWorkspaceHeadViaAPI(t, h, workspace.WorkspaceID, flowDocID, flowVerID)

			runReq := `{
			  "workspace_id":"` + workspace.WorkspaceID + `",
			  "flow_ref":{"doc_id":"` + flowDocID + `","ver_id":null,"selector":"head"},
			  "inputs":{"input_file":"input.txt","output_file":"output.txt"}
			}`
			rr := postRunViaAPI(t, h, runReq)
			if rr.Code != http.StatusBadRequest {
				t.Fatalf("expected status %d, got %d body=%s", http.StatusBadRequest, rr.Code, rr.Body.String())
			}
			if !strings.Contains(strings.ToLower(rr.Body.String()), strings.ToLower(tc.errSubstr)) {
				t.Fatalf("expected error message to contain %q, got %q", tc.errSubstr, rr.Body.String())
			}
		})
	}
}

func TestRunsValidFlowFileReadToLLMChatToFileWriteCreatesFinalOutput(t *testing.T) {
	mockResp := `{"choices":[{"message":{"content":"mocked assistant response"}}]}`
	mockServer, captured := newMockVLLMServer(t, http.StatusOK, mockResp)
	h := newAPITestHarnessWithLLM(t, mockServer.URL, "test-vllm-key", "env-model")
	workspace := createWorkspaceViaAPI(t, h, "Runs Valid")

	flowDocID := uuid.NewString()
	flowVerID := uuid.NewString()
	flowBody := `{
	  "nodes": [
	    {"id":"n1","type":"file.read","inputs":[],"outputs":[{"port":"out","schema":"artifact/text"}],"config":{}},
	    {"id":"n2","type":"llm.chat","inputs":[{"port":"in","schema":"artifact/text"}],"outputs":[{"port":"out","schema":"artifact/text"}],"config":{"model":"node-model"}},
	    {"id":"n3","type":"file.write","inputs":[{"port":"in","schema":"artifact/text"}],"outputs":[{"port":"out","schema":"artifact/output_file"}],"config":{}}
	  ],
	  "edges": [
	    {"from":{"node":"n1","port":"out"},"to":{"node":"n2","port":"in"}},
	    {"from":{"node":"n2","port":"out"},"to":{"node":"n3","port":"in"}}
	  ]
	}`
	putFlowDocViaAPI(t, h, workspace.WorkspaceID, flowDocID, flowVerID, flowBody)
	setWorkspaceHeadViaAPI(t, h, workspace.WorkspaceID, flowDocID, flowVerID)
	writeWorkspaceInputFile(t, h, workspace.WorkspaceID, "input.txt", "file content from test")

	runReq := `{
	  "workspace_id":"` + workspace.WorkspaceID + `",
	  "flow_ref":{"doc_id":"` + flowDocID + `","ver_id":null,"selector":"head"},
	  "inputs":{"input_file":"input.txt","output_file":"output.txt"}
	}`
	rr := postRunViaAPI(t, h, runReq)
	if rr.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d body=%s", http.StatusCreated, rr.Code, rr.Body.String())
	}

	if captured.Authorization != "Bearer test-vllm-key" {
		t.Fatalf("expected Authorization header %q, got %q", "Bearer test-vllm-key", captured.Authorization)
	}
	if captured.Model != "node-model" {
		t.Fatalf("expected model node-model from node config, got %q", captured.Model)
	}
	if captured.Role != "user" {
		t.Fatalf("expected role user, got %q", captured.Role)
	}
	if captured.Content != "file content from test" {
		t.Fatalf("expected llm input text %q, got %q", "file content from test", captured.Content)
	}

	var runResp struct {
		RunID    string `json:"run_id"`
		RunVerID string `json:"run_ver_id"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &runResp); err != nil {
		t.Fatalf("decode run response: %v", err)
	}

	runDocReq := httptest.NewRequest(http.MethodGet, "/v1/docs/run/"+runResp.RunID+"/"+runResp.RunVerID, nil)
	runDocRR := httptest.NewRecorder()
	h.mux.ServeHTTP(runDocRR, runDocReq)
	if runDocRR.Code != http.StatusOK {
		t.Fatalf("expected run doc status %d, got %d body=%s", http.StatusOK, runDocRR.Code, runDocRR.Body.String())
	}

	var runDoc struct {
		Body struct {
			Outputs []struct {
				ArtifactRef struct {
					DocID string `json:"doc_id"`
					VerID string `json:"ver_id"`
				} `json:"artifact_ref"`
			} `json:"outputs"`
			Invocations []struct {
				NodeID string `json:"node_id"`
				Inputs []struct {
					ArtifactRef struct {
						DocID string `json:"doc_id"`
						VerID string `json:"ver_id"`
					} `json:"artifact_ref"`
				} `json:"inputs"`
				Outputs []struct {
					ArtifactRef struct {
						DocID string `json:"doc_id"`
						VerID string `json:"ver_id"`
					} `json:"artifact_ref"`
				} `json:"outputs"`
			} `json:"invocations"`
		} `json:"body"`
	}
	if err := json.Unmarshal(runDocRR.Body.Bytes(), &runDoc); err != nil {
		t.Fatalf("decode run doc: %v", err)
	}

	var fileReadOutDocID, fileReadOutVerID string
	var llmOutDocID, llmOutVerID string
	var llmInputDocID, llmInputVerID string
	var writeOutDocID, writeOutVerID string
	var writeInputDocID, writeInputVerID string
	for _, inv := range runDoc.Body.Invocations {
		if inv.NodeID == "n1" && len(inv.Outputs) == 1 {
			fileReadOutDocID = inv.Outputs[0].ArtifactRef.DocID
			fileReadOutVerID = inv.Outputs[0].ArtifactRef.VerID
		}
		if inv.NodeID == "n2" {
			if len(inv.Inputs) == 1 {
				llmInputDocID = inv.Inputs[0].ArtifactRef.DocID
				llmInputVerID = inv.Inputs[0].ArtifactRef.VerID
			}
			if len(inv.Outputs) == 1 {
				llmOutDocID = inv.Outputs[0].ArtifactRef.DocID
				llmOutVerID = inv.Outputs[0].ArtifactRef.VerID
			}
		}
		if inv.NodeID == "n3" {
			if len(inv.Inputs) == 1 {
				writeInputDocID = inv.Inputs[0].ArtifactRef.DocID
				writeInputVerID = inv.Inputs[0].ArtifactRef.VerID
			}
			if len(inv.Outputs) == 1 {
				writeOutDocID = inv.Outputs[0].ArtifactRef.DocID
				writeOutVerID = inv.Outputs[0].ArtifactRef.VerID
			}
		}
	}
	if fileReadOutDocID == "" || llmOutDocID == "" || writeOutDocID == "" {
		t.Fatalf("expected file.read, llm.chat and file.write output artifacts")
	}
	if llmInputDocID != fileReadOutDocID || llmInputVerID != fileReadOutVerID {
		t.Fatalf("expected llm.chat input to reference file.read output artifact")
	}
	if writeInputDocID != llmOutDocID || writeInputVerID != llmOutVerID {
		t.Fatalf("expected file.write input to reference llm.chat output artifact")
	}
	if len(runDoc.Body.Outputs) != 1 {
		t.Fatalf("expected run.body.outputs to have one artifact")
	}
	if runDoc.Body.Outputs[0].ArtifactRef.DocID != writeOutDocID || runDoc.Body.Outputs[0].ArtifactRef.VerID != writeOutVerID {
		t.Fatalf("expected run.body.outputs to reference file.write artifact")
	}

	llmArtifactReq := httptest.NewRequest(http.MethodGet, "/v1/docs/artifact/"+llmOutDocID+"/"+llmOutVerID, nil)
	llmArtifactRR := httptest.NewRecorder()
	h.mux.ServeHTTP(llmArtifactRR, llmArtifactReq)
	if llmArtifactRR.Code != http.StatusOK {
		t.Fatalf("expected llm output artifact status %d, got %d body=%s", http.StatusOK, llmArtifactRR.Code, llmArtifactRR.Body.String())
	}

	var llmArtifact struct {
		Body struct {
			Schema  string `json:"schema"`
			Payload struct {
				Text  string `json:"text"`
				Model string `json:"model"`
			} `json:"payload"`
		} `json:"body"`
	}
	if err := json.Unmarshal(llmArtifactRR.Body.Bytes(), &llmArtifact); err != nil {
		t.Fatalf("decode llm output artifact: %v", err)
	}
	if llmArtifact.Body.Schema != "artifact/text" {
		t.Fatalf("expected llm output schema artifact/text, got %q", llmArtifact.Body.Schema)
	}
	if llmArtifact.Body.Payload.Text != "mocked assistant response" {
		t.Fatalf("expected llm output text %q, got %q", "mocked assistant response", llmArtifact.Body.Payload.Text)
	}
	if llmArtifact.Body.Payload.Model != "node-model" {
		t.Fatalf("expected llm output model %q, got %q", "node-model", llmArtifact.Body.Payload.Model)
	}

	writeArtifactReq := httptest.NewRequest(http.MethodGet, "/v1/docs/artifact/"+writeOutDocID+"/"+writeOutVerID, nil)
	writeArtifactRR := httptest.NewRecorder()
	h.mux.ServeHTTP(writeArtifactRR, writeArtifactReq)
	if writeArtifactRR.Code != http.StatusOK {
		t.Fatalf("expected file.write artifact status %d, got %d body=%s", http.StatusOK, writeArtifactRR.Code, writeArtifactRR.Body.String())
	}

	var writeArtifact struct {
		Body struct {
			Schema  string `json:"schema"`
			Payload struct {
				Path  string `json:"path"`
				Bytes int    `json:"bytes"`
			} `json:"payload"`
		} `json:"body"`
	}
	if err := json.Unmarshal(writeArtifactRR.Body.Bytes(), &writeArtifact); err != nil {
		t.Fatalf("decode file.write artifact: %v", err)
	}
	if writeArtifact.Body.Schema != "artifact/output_file" {
		t.Fatalf("expected file.write schema artifact/output_file, got %q", writeArtifact.Body.Schema)
	}
	if writeArtifact.Body.Payload.Path != "output.txt" {
		t.Fatalf("expected output path output.txt, got %q", writeArtifact.Body.Payload.Path)
	}
	if writeArtifact.Body.Payload.Bytes != len("mocked assistant response") {
		t.Fatalf("expected bytes=%d got %d", len("mocked assistant response"), writeArtifact.Body.Payload.Bytes)
	}

	outputPath := filepath.Join(h.workspaceRoot, workspace.WorkspaceID, "output.txt")
	outputBytes, err := os.ReadFile(outputPath)
	if err != nil {
		t.Fatalf("read output file: %v", err)
	}
	if string(outputBytes) != "mocked assistant response" {
		t.Fatalf("expected output file content %q, got %q", "mocked assistant response", string(outputBytes))
	}
}

func TestRunsRejectsPathTraversal(t *testing.T) {
	h := newAPITestHarness(t)
	workspace := createWorkspaceViaAPI(t, h, "Runs Traversal")

	flowDocID := uuid.NewString()
	flowVerID := uuid.NewString()
	flowBody := `{
	  "nodes": [
	    {"id":"n1","type":"file.read","inputs":[],"outputs":[{"port":"out","schema":"artifact/text"}],"config":{}},
	    {"id":"n2","type":"node.out","inputs":[{"port":"in","schema":"artifact/text"}],"outputs":[],"config":{}}
	  ],
	  "edges": [
	    {"from":{"node":"n1","port":"out"},"to":{"node":"n2","port":"in"}}
	  ]
	}`
	putFlowDocViaAPI(t, h, workspace.WorkspaceID, flowDocID, flowVerID, flowBody)
	setWorkspaceHeadViaAPI(t, h, workspace.WorkspaceID, flowDocID, flowVerID)

	runReq := `{
	  "workspace_id":"` + workspace.WorkspaceID + `",
	  "flow_ref":{"doc_id":"` + flowDocID + `","ver_id":null,"selector":"head"},
	  "inputs":{"input_file":"../secrets.txt","output_file":"output.txt"}
	}`
	rr := postRunViaAPI(t, h, runReq)
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d body=%s", http.StatusBadRequest, rr.Code, rr.Body.String())
	}
	if !strings.Contains(strings.ToLower(rr.Body.String()), "path traversal") {
		t.Fatalf("expected traversal message, got %q", rr.Body.String())
	}
}

func TestRunsRejectsOutputPathTraversal(t *testing.T) {
	mockResp := `{"choices":[{"message":{"content":"mocked assistant response"}}]}`
	mockServer, _ := newMockVLLMServer(t, http.StatusOK, mockResp)
	h := newAPITestHarnessWithLLM(t, mockServer.URL, "test-vllm-key", "env-model")
	workspace := createWorkspaceViaAPI(t, h, "Runs Output Traversal")

	flowDocID := uuid.NewString()
	flowVerID := uuid.NewString()
	flowBody := `{
	  "nodes": [
	    {"id":"n1","type":"file.read","inputs":[],"outputs":[{"port":"out","schema":"artifact/text"}],"config":{}},
	    {"id":"n2","type":"llm.chat","inputs":[{"port":"in","schema":"artifact/text"}],"outputs":[{"port":"out","schema":"artifact/text"}],"config":{}},
	    {"id":"n3","type":"file.write","inputs":[{"port":"in","schema":"artifact/text"}],"outputs":[{"port":"out","schema":"artifact/output_file"}],"config":{}}
	  ],
	  "edges": [
	    {"from":{"node":"n1","port":"out"},"to":{"node":"n2","port":"in"}},
	    {"from":{"node":"n2","port":"out"},"to":{"node":"n3","port":"in"}}
	  ]
	}`
	putFlowDocViaAPI(t, h, workspace.WorkspaceID, flowDocID, flowVerID, flowBody)
	setWorkspaceHeadViaAPI(t, h, workspace.WorkspaceID, flowDocID, flowVerID)
	writeWorkspaceInputFile(t, h, workspace.WorkspaceID, "input.txt", "hello")

	runReq := `{
	  "workspace_id":"` + workspace.WorkspaceID + `",
	  "flow_ref":{"doc_id":"` + flowDocID + `","ver_id":null,"selector":"head"},
	  "inputs":{"input_file":"input.txt","output_file":"../evil.txt"}
	}`
	rr := postRunViaAPI(t, h, runReq)
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d body=%s", http.StatusBadRequest, rr.Code, rr.Body.String())
	}
	if !strings.Contains(strings.ToLower(rr.Body.String()), "path traversal") {
		t.Fatalf("expected traversal message, got %q", rr.Body.String())
	}
}

func TestRunsLLMFailureReturnsBadGateway(t *testing.T) {
	mockServer, _ := newMockVLLMServer(t, http.StatusBadGateway, `{"error":"upstream unavailable"}`)
	h := newAPITestHarnessWithLLM(t, mockServer.URL, "test-vllm-key", "env-model")
	workspace := createWorkspaceViaAPI(t, h, "Runs LLM Failure")

	flowDocID := uuid.NewString()
	flowVerID := uuid.NewString()
	flowBody := `{
	  "nodes": [
	    {"id":"n1","type":"file.read","inputs":[],"outputs":[{"port":"out","schema":"artifact/text"}],"config":{}},
	    {"id":"n2","type":"llm.chat","inputs":[{"port":"in","schema":"artifact/text"}],"outputs":[{"port":"out","schema":"artifact/text"}],"config":{}}
	  ],
	  "edges": [
	    {"from":{"node":"n1","port":"out"},"to":{"node":"n2","port":"in"}}
	  ]
	}`
	putFlowDocViaAPI(t, h, workspace.WorkspaceID, flowDocID, flowVerID, flowBody)
	setWorkspaceHeadViaAPI(t, h, workspace.WorkspaceID, flowDocID, flowVerID)
	writeWorkspaceInputFile(t, h, workspace.WorkspaceID, "input.txt", "file content from test")

	runReq := `{
	  "workspace_id":"` + workspace.WorkspaceID + `",
	  "flow_ref":{"doc_id":"` + flowDocID + `","ver_id":null,"selector":"head"},
	  "inputs":{"input_file":"input.txt","output_file":"output.txt"}
	}`
	rr := postRunViaAPI(t, h, runReq)
	if rr.Code != http.StatusBadGateway {
		t.Fatalf("expected status %d, got %d body=%s", http.StatusBadGateway, rr.Code, rr.Body.String())
	}
	if !strings.Contains(strings.ToLower(rr.Body.String()), "llm.chat failed") {
		t.Fatalf("expected llm failure message, got %q", rr.Body.String())
	}
}

func TestRunsMissingInputFilePersistsFailedRun(t *testing.T) {
	h := newAPITestHarness(t)
	workspace := createWorkspaceViaAPI(t, h, "Runs Persist Failure")

	flowDocID := uuid.NewString()
	flowVerID := uuid.NewString()
	flowBody := `{
	  "nodes": [
	    {"id":"n1","type":"file.read","inputs":[],"outputs":[{"port":"out","schema":"artifact/text"}],"config":{}},
	    {"id":"n2","type":"node.out","inputs":[{"port":"in","schema":"artifact/text"}],"outputs":[],"config":{}}
	  ],
	  "edges": [
	    {"from":{"node":"n1","port":"out"},"to":{"node":"n2","port":"in"}}
	  ]
	}`
	putFlowDocViaAPI(t, h, workspace.WorkspaceID, flowDocID, flowVerID, flowBody)
	setWorkspaceHeadViaAPI(t, h, workspace.WorkspaceID, flowDocID, flowVerID)

	runReq := `{
	  "workspace_id":"` + workspace.WorkspaceID + `",
	  "flow_ref":{"doc_id":"` + flowDocID + `","ver_id":null,"selector":"head"},
	  "inputs":{"input_file":"missing.txt","output_file":"output.txt"}
	}`
	rr := postRunViaAPI(t, h, runReq)
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d body=%s", http.StatusBadRequest, rr.Code, rr.Body.String())
	}

	var errResp struct {
		Error struct {
			Message string `json:"message"`
		} `json:"error"`
		RunID    string `json:"run_id"`
		RunVerID string `json:"run_ver_id"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &errResp); err != nil {
		t.Fatalf("decode error response: %v", err)
	}
	if errResp.RunID == "" || errResp.RunVerID == "" {
		t.Fatalf("expected run_id and run_ver_id in error response, got %+v", errResp)
	}
	if !strings.Contains(strings.ToLower(errResp.Error.Message), "file.read failed") {
		t.Fatalf("expected file.read failure message, got %q", errResp.Error.Message)
	}

	runDocReq := httptest.NewRequest(http.MethodGet, "/v1/docs/run/"+errResp.RunID+"/"+errResp.RunVerID, nil)
	runDocRR := httptest.NewRecorder()
	h.mux.ServeHTTP(runDocRR, runDocReq)
	if runDocRR.Code != http.StatusOK {
		t.Fatalf("expected persisted failed run doc status %d, got %d body=%s", http.StatusOK, runDocRR.Code, runDocRR.Body.String())
	}

	var runDoc struct {
		Body struct {
			Status   string `json:"status"`
			TraceRef struct {
				Error struct {
					Message string `json:"message"`
					Kind    string `json:"kind"`
					NodeID  string `json:"node_id"`
				} `json:"error"`
			} `json:"trace_ref"`
		} `json:"body"`
	}
	if err := json.Unmarshal(runDocRR.Body.Bytes(), &runDoc); err != nil {
		t.Fatalf("decode failed run doc: %v", err)
	}
	if runDoc.Body.Status != "failed" {
		t.Fatalf("expected run status failed, got %q", runDoc.Body.Status)
	}
	if runDoc.Body.TraceRef.Error.Message == "" || runDoc.Body.TraceRef.Error.Kind == "" {
		t.Fatalf("expected trace_ref.error fields in failed run: %+v", runDoc.Body.TraceRef.Error)
	}
}
