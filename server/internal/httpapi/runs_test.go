package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
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

func TestRunsValidFlowCreatesRunAndInputArtifactDocs(t *testing.T) {
	h := newAPITestHarness(t)
	workspace := createWorkspaceViaAPI(t, h, "Runs Valid")

	flowDocID := uuid.NewString()
	flowVerID := uuid.NewString()
	flowBody := `{
	  "nodes": [
	    {"id":"n1","type":"node.in","inputs":[],"outputs":[{"port":"out","schema":"artifact/text"}],"config":{}},
	    {"id":"n2","type":"node.mid","inputs":[{"port":"in","schema":"artifact/text"}],"outputs":[{"port":"out","schema":"artifact/text"}],"config":{}},
	    {"id":"n3","type":"node.out","inputs":[{"port":"in","schema":"artifact/text"}],"outputs":[],"config":{}}
	  ],
	  "edges": [
	    {"from":{"node":"n1","port":"out"},"to":{"node":"n2","port":"in"}},
	    {"from":{"node":"n2","port":"out"},"to":{"node":"n3","port":"in"}}
	  ]
	}`
	putFlowDocViaAPI(t, h, workspace.WorkspaceID, flowDocID, flowVerID, flowBody)
	setWorkspaceHeadViaAPI(t, h, workspace.WorkspaceID, flowDocID, flowVerID)

	runReq := `{
	  "workspace_id":"` + workspace.WorkspaceID + `",
	  "flow_ref":{"doc_id":"` + flowDocID + `","ver_id":null,"selector":"head"},
	  "inputs":{"input_file":"input.txt","output_file":"output.txt"}
	}`
	rr := postRunViaAPI(t, h, runReq)
	if rr.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d body=%s", http.StatusCreated, rr.Code, rr.Body.String())
	}

	var runResp struct {
		RunID    string `json:"run_id"`
		RunVerID string `json:"run_ver_id"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &runResp); err != nil {
		t.Fatalf("decode run response: %v", err)
	}
	if runResp.RunID == "" || runResp.RunVerID == "" {
		t.Fatalf("expected non-empty run IDs")
	}

	runDocReq := httptest.NewRequest(http.MethodGet, "/v1/docs/run/"+runResp.RunID+"/"+runResp.RunVerID, nil)
	runDocRR := httptest.NewRecorder()
	h.mux.ServeHTTP(runDocRR, runDocReq)
	if runDocRR.Code != http.StatusOK {
		t.Fatalf("expected run doc status %d, got %d body=%s", http.StatusOK, runDocRR.Code, runDocRR.Body.String())
	}

	var runDoc struct {
		DocType string `json:"doc_type"`
		Body    struct {
			FlowRef struct {
				DocID    string `json:"doc_id"`
				VerID    string `json:"ver_id"`
				Selector string `json:"selector"`
			} `json:"flow_ref"`
			Inputs []struct {
				ArtifactRef struct {
					DocID    string `json:"doc_id"`
					VerID    string `json:"ver_id"`
					Selector string `json:"selector"`
				} `json:"artifact_ref"`
			} `json:"inputs"`
		} `json:"body"`
	}
	if err := json.Unmarshal(runDocRR.Body.Bytes(), &runDoc); err != nil {
		t.Fatalf("decode run doc: %v", err)
	}
	if runDoc.DocType != "run" {
		t.Fatalf("expected doc_type run, got %q", runDoc.DocType)
	}
	if runDoc.Body.FlowRef.DocID != flowDocID || runDoc.Body.FlowRef.VerID != flowVerID || runDoc.Body.FlowRef.Selector != "pinned" {
		t.Fatalf("unexpected flow_ref in run doc: %+v", runDoc.Body.FlowRef)
	}
	if len(runDoc.Body.Inputs) != 1 {
		t.Fatalf("expected one run input artifact ref, got %d", len(runDoc.Body.Inputs))
	}

	artifactDocID := runDoc.Body.Inputs[0].ArtifactRef.DocID
	artifactVerID := runDoc.Body.Inputs[0].ArtifactRef.VerID
	artifactReq := httptest.NewRequest(http.MethodGet, "/v1/docs/artifact/"+artifactDocID+"/"+artifactVerID, nil)
	artifactRR := httptest.NewRecorder()
	h.mux.ServeHTTP(artifactRR, artifactReq)
	if artifactRR.Code != http.StatusOK {
		t.Fatalf("expected artifact doc status %d, got %d body=%s", http.StatusOK, artifactRR.Code, artifactRR.Body.String())
	}

	var artifactDoc struct {
		DocType string `json:"doc_type"`
		Body    struct {
			Payload struct {
				Path string `json:"path"`
			} `json:"payload"`
			Provenance struct {
				RunRef struct {
					DocID    string `json:"doc_id"`
					VerID    string `json:"ver_id"`
					Selector string `json:"selector"`
				} `json:"run_ref"`
				NodeID string `json:"node_id"`
			} `json:"provenance"`
		} `json:"body"`
	}
	if err := json.Unmarshal(artifactRR.Body.Bytes(), &artifactDoc); err != nil {
		t.Fatalf("decode artifact doc: %v", err)
	}
	if artifactDoc.DocType != "artifact" {
		t.Fatalf("expected doc_type artifact, got %q", artifactDoc.DocType)
	}
	if artifactDoc.Body.Payload.Path != "input.txt" {
		t.Fatalf("expected artifact payload path input.txt, got %q", artifactDoc.Body.Payload.Path)
	}
	if artifactDoc.Body.Provenance.RunRef.DocID != runResp.RunID ||
		artifactDoc.Body.Provenance.RunRef.VerID != runResp.RunVerID ||
		artifactDoc.Body.Provenance.RunRef.Selector != "pinned" {
		t.Fatalf("unexpected artifact provenance run_ref: %+v", artifactDoc.Body.Provenance.RunRef)
	}
	if artifactDoc.Body.Provenance.NodeID != "__run_input__" {
		t.Fatalf("expected provenance node_id __run_input__, got %q", artifactDoc.Body.Provenance.NodeID)
	}
}
