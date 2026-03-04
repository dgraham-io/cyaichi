package engine

import (
	"encoding/json"
	"fmt"
)

type FlowDocument struct {
	DocType     string   `json:"doc_type"`
	DocID       string   `json:"doc_id"`
	VerID       string   `json:"ver_id"`
	WorkspaceID string   `json:"workspace_id"`
	CreatedAt   string   `json:"created_at"`
	Parents     []string `json:"parents,omitempty"`
	Body        FlowBody `json:"body"`
}

type FlowBody struct {
	ModeHint string     `json:"mode_hint,omitempty"`
	Nodes    []FlowNode `json:"nodes"`
	Edges    []FlowEdge `json:"edges"`
}

type FlowNode struct {
	ID      string     `json:"id"`
	Type    string     `json:"type"`
	Title   string     `json:"title,omitempty"`
	Inputs  []FlowPort `json:"inputs"`
	Outputs []FlowPort `json:"outputs"`
}

type FlowPort struct {
	Port   string `json:"port"`
	Schema string `json:"schema"`
}

type FlowEdge struct {
	From FlowEndpoint `json:"from"`
	To   FlowEndpoint `json:"to"`
}

type FlowEndpoint struct {
	Node string `json:"node"`
	Port string `json:"port"`
}

func ParseFlowDocument(docJSON string) (FlowDocument, error) {
	var flowDoc FlowDocument
	if err := json.Unmarshal([]byte(docJSON), &flowDoc); err != nil {
		return FlowDocument{}, fmt.Errorf("invalid flow document JSON: %w", err)
	}
	return flowDoc, nil
}
