package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"
)

func TestExportPackageIncludesWorkspaceAndSubflows(t *testing.T) {
	h := newAPITestHarness(t)
	workspace := createWorkspaceViaAPI(t, h, "Package Export Workspace")

	subflowDocID := uuid.NewString()
	subflowVerID := uuid.NewString()
	rootFlowDocID := uuid.NewString()
	rootFlowVerID := uuid.NewString()

	subflowBody := `{
	  "nodes": [],
	  "edges": []
	}`
	rootFlowBody := `{
	  "nodes": [],
	  "edges": [],
	  "subflows": [
	    {
	      "id": "subflow-1",
	      "flow_ref": {
	        "doc_id": "` + subflowDocID + `",
	        "ver_id": null,
	        "selector": "head"
	      }
	    }
	  ]
	}`

	putFlowDocViaAPI(t, h, workspace.WorkspaceID, subflowDocID, subflowVerID, subflowBody)
	putFlowDocViaAPI(t, h, workspace.WorkspaceID, rootFlowDocID, rootFlowVerID, rootFlowBody)
	setWorkspaceHeadViaAPI(t, h, workspace.WorkspaceID, subflowDocID, subflowVerID)
	setWorkspaceHeadViaAPI(t, h, workspace.WorkspaceID, rootFlowDocID, rootFlowVerID)
	latestWorkspaceDoc, err := h.store.GetLatestWorkspaceDoc(context.Background(), workspace.WorkspaceID)
	if err != nil {
		t.Fatalf("get latest workspace doc: %v", err)
	}

	exportReq := `{
	  "workspace_id":"` + workspace.WorkspaceID + `",
	  "flow_ref":{"doc_id":"` + rootFlowDocID + `","ver_id":null,"selector":"head"},
	  "recommended_head": true
	}`
	req := httptest.NewRequest(http.MethodPost, "/v1/packages/export", strings.NewReader(exportReq))
	req.Header.Set("Content-Type", "application/json")
	rr := httptest.NewRecorder()
	h.mux.ServeHTTP(rr, req)
	if rr.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d body=%s", http.StatusCreated, rr.Code, rr.Body.String())
	}

	var exportResp struct {
		PackageID     string `json:"package_id"`
		PackageVerID  string `json:"package_ver_id"`
		IncludesCount int    `json:"includes_count"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &exportResp); err != nil {
		t.Fatalf("decode export response: %v", err)
	}
	if exportResp.PackageID == "" || exportResp.PackageVerID == "" {
		t.Fatalf("expected package ids in response")
	}
	if exportResp.IncludesCount != 3 {
		t.Fatalf("expected includes_count=3, got %d", exportResp.IncludesCount)
	}

	getReq := httptest.NewRequest(http.MethodGet, "/v1/packages/"+exportResp.PackageID+"/"+exportResp.PackageVerID, nil)
	getRR := httptest.NewRecorder()
	h.mux.ServeHTTP(getRR, getReq)
	if getRR.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d body=%s", http.StatusOK, getRR.Code, getRR.Body.String())
	}

	var packageDoc struct {
		DocType string `json:"doc_type"`
		Body    struct {
			Format   string `json:"format"`
			Includes []struct {
				DocType string `json:"doc_type"`
				DocID   string `json:"doc_id"`
				VerID   string `json:"ver_id"`
			} `json:"includes"`
			RecommendedHeads []struct {
				DocID string `json:"doc_id"`
				VerID string `json:"ver_id"`
			} `json:"recommended_heads"`
		} `json:"body"`
	}
	if err := json.Unmarshal(getRR.Body.Bytes(), &packageDoc); err != nil {
		t.Fatalf("decode package doc: %v", err)
	}
	if packageDoc.DocType != "package" {
		t.Fatalf("expected doc_type package, got %q", packageDoc.DocType)
	}
	if packageDoc.Body.Format != "cyaichi-package/v1" {
		t.Fatalf("expected format cyaichi-package/v1, got %q", packageDoc.Body.Format)
	}
	if len(packageDoc.Body.Includes) != 3 {
		t.Fatalf("expected 3 includes, got %d", len(packageDoc.Body.Includes))
	}

	includes := map[string]bool{}
	for _, item := range packageDoc.Body.Includes {
		includes[item.DocType+"|"+item.DocID+"|"+item.VerID] = true
	}
	if !includes["flow|"+rootFlowDocID+"|"+rootFlowVerID] {
		t.Fatalf("expected root flow include")
	}
	if !includes["flow|"+subflowDocID+"|"+subflowVerID] {
		t.Fatalf("expected subflow include")
	}
	if !includes["workspace|"+workspace.WorkspaceID+"|"+latestWorkspaceDoc.VerID] {
		t.Fatalf("expected workspace include")
	}

	if len(packageDoc.Body.RecommendedHeads) != 1 {
		t.Fatalf("expected one recommended head, got %d", len(packageDoc.Body.RecommendedHeads))
	}
	if packageDoc.Body.RecommendedHeads[0].DocID != rootFlowDocID || packageDoc.Body.RecommendedHeads[0].VerID != rootFlowVerID {
		t.Fatalf("unexpected recommended head: %+v", packageDoc.Body.RecommendedHeads[0])
	}
}

func TestExportPackageMissingSubflowHeadReturnsBadRequestAndNoPackage(t *testing.T) {
	h := newAPITestHarness(t)
	workspace := createWorkspaceViaAPI(t, h, "Package Export Missing Subflow Head")

	rootFlowDocID := uuid.NewString()
	rootFlowVerID := uuid.NewString()
	missingSubflowDocID := uuid.NewString()

	rootFlowBody := `{
	  "nodes": [],
	  "edges": [],
	  "subflows": [
	    {
	      "id": "subflow-1",
	      "flow_ref": {
	        "doc_id": "` + missingSubflowDocID + `",
	        "ver_id": null,
	        "selector": "head"
	      }
	    }
	  ]
	}`
	putFlowDocViaAPI(t, h, workspace.WorkspaceID, rootFlowDocID, rootFlowVerID, rootFlowBody)
	setWorkspaceHeadViaAPI(t, h, workspace.WorkspaceID, rootFlowDocID, rootFlowVerID)

	exportReq := `{
	  "workspace_id":"` + workspace.WorkspaceID + `",
	  "flow_ref":{"doc_id":"` + rootFlowDocID + `","ver_id":null,"selector":"head"},
	  "recommended_head": true
	}`
	req := httptest.NewRequest(http.MethodPost, "/v1/packages/export", strings.NewReader(exportReq))
	req.Header.Set("Content-Type", "application/json")
	rr := httptest.NewRecorder()
	h.mux.ServeHTTP(rr, req)
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d body=%s", http.StatusBadRequest, rr.Code, rr.Body.String())
	}
	if !strings.Contains(strings.ToLower(rr.Body.String()), "subflow head not found") {
		t.Fatalf("expected clear subflow head error, got %q", rr.Body.String())
	}

	packages, err := h.store.ListDocumentsByType(context.Background(), workspace.WorkspaceID, "package", 50, 0)
	if err != nil {
		t.Fatalf("list package documents: %v", err)
	}
	if len(packages) != 0 {
		t.Fatalf("expected no stored package docs on failure, got %d", len(packages))
	}
}
