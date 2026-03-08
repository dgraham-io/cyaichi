package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestNodeTypesHandler(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/v1/node-types", nil)
	rr := httptest.NewRecorder()

	NodeTypesHandler(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d body=%s", http.StatusOK, rr.Code, rr.Body.String())
	}
	if !strings.Contains(rr.Body.String(), `"type":"file.read"`) || !strings.Contains(rr.Body.String(), `"inputs":[]`) {
		t.Fatalf("expected file.read inputs to serialize as [], got %s", rr.Body.String())
	}
	if got := rr.Header().Get("Content-Type"); got != "application/json" {
		t.Fatalf("expected Content-Type application/json, got %q", got)
	}

	var resp struct {
		Items []struct {
			Type        string `json:"type"`
			DisplayName string `json:"display_name"`
			Category    string `json:"category"`
			Inputs      []struct {
				Port   string `json:"port"`
				Schema string `json:"schema"`
			} `json:"inputs"`
			Outputs []struct {
				Port   string `json:"port"`
				Schema string `json:"schema"`
			} `json:"outputs"`
			ConfigSchema []struct {
				Key      string `json:"key"`
				Kind     string `json:"kind"`
				Required bool   `json:"required"`
				Label    string `json:"label"`
			} `json:"config_schema"`
		} `json:"items"`
	}
	if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}

	if len(resp.Items) != 4 {
		t.Fatalf("expected 4 node types, got %d", len(resp.Items))
	}
	if resp.Items[0].Type != "file.read" || resp.Items[1].Type != "file.write" || resp.Items[2].Type != "file.monitor" || resp.Items[3].Type != "llm.chat" {
		t.Fatalf("unexpected node type order: %#v", resp.Items)
	}

	read := resp.Items[0]
	if len(read.Outputs) != 1 || read.Outputs[0].Port != "out" || read.Outputs[0].Schema != "artifact/text" {
		t.Fatalf("unexpected file.read outputs: %#v", read.Outputs)
	}

	write := resp.Items[1]
	if len(write.Inputs) != 1 || write.Inputs[0].Port != "in" || write.Inputs[0].Schema != "artifact/text" {
		t.Fatalf("unexpected file.write inputs: %#v", write.Inputs)
	}
	if len(write.ConfigSchema) != 2 {
		t.Fatalf("unexpected file.write config_schema: %#v", write.ConfigSchema)
	}
}

func TestProcessorTypesAliasMatchesNodeTypes(t *testing.T) {
	mux := NewMux(nil, nil, "", "", "", "", 0)

	nodeTypesReq := httptest.NewRequest(http.MethodGet, "/v1/node-types", nil)
	nodeTypesRR := httptest.NewRecorder()
	mux.ServeHTTP(nodeTypesRR, nodeTypesReq)

	if nodeTypesRR.Code != http.StatusOK {
		t.Fatalf("expected /v1/node-types status %d, got %d body=%s", http.StatusOK, nodeTypesRR.Code, nodeTypesRR.Body.String())
	}

	processorTypesReq := httptest.NewRequest(http.MethodGet, "/v1/processor-types", nil)
	processorTypesRR := httptest.NewRecorder()
	mux.ServeHTTP(processorTypesRR, processorTypesReq)

	if processorTypesRR.Code != http.StatusOK {
		t.Fatalf("expected /v1/processor-types status %d, got %d body=%s", http.StatusOK, processorTypesRR.Code, processorTypesRR.Body.String())
	}

	if nodeTypesRR.Body.String() != processorTypesRR.Body.String() {
		t.Fatalf("expected alias endpoints to return identical JSON\nnode-types=%s\nprocessor-types=%s", nodeTypesRR.Body.String(), processorTypesRR.Body.String())
	}
}
