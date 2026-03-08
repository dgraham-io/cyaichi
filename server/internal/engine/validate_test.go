package engine

import (
	"strings"
	"testing"
)

func TestValidateRunnableFlow(t *testing.T) {
	baseFlow := func() FlowDocument {
		return FlowDocument{
			Body: FlowBody{
				Nodes: []FlowNode{
					{
						ID:      "a",
						Type:    "file.read",
						Outputs: []FlowPort{{Port: "out", Schema: "artifact/text"}},
					},
					{
						ID:      "b",
						Type:    "file.read",
						Outputs: []FlowPort{{Port: "out", Schema: "artifact/text"}},
					},
					{
						ID:   "c",
						Type: "llm.chat",
						Inputs: []FlowPort{
							{Port: "left", Schema: "artifact/text"},
							{Port: "right", Schema: "artifact/text"},
						},
						Outputs: []FlowPort{{Port: "out", Schema: "artifact/text"}},
					},
				},
				Edges: []FlowEdge{
					{
						From: FlowEndpoint{Node: "a", Port: "out"},
						To:   FlowEndpoint{Node: "c", Port: "left"},
					},
					{
						From: FlowEndpoint{Node: "b", Port: "out"},
						To:   FlowEndpoint{Node: "c", Port: "right"},
					},
				},
			},
		}
	}

	tests := []struct {
		name        string
		mutate      func(flow *FlowDocument)
		wantOrder   []string
		wantErrText string
	}{
		{
			name:      "returns deterministic topological order",
			wantOrder: []string{"a", "b", "c"},
		},
		{
			name: "rejects empty node list",
			mutate: func(flow *FlowDocument) {
				flow.Body.Nodes = nil
			},
			wantErrText: "flow must contain at least one node",
		},
		{
			name: "rejects empty edge list",
			mutate: func(flow *FlowDocument) {
				flow.Body.Edges = nil
			},
			wantErrText: "flow must contain at least one edge",
		},
		{
			name: "rejects duplicate node ids",
			mutate: func(flow *FlowDocument) {
				flow.Body.Nodes = append(flow.Body.Nodes, flow.Body.Nodes[0])
			},
			wantErrText: "duplicate node id: a",
		},
		{
			name: "rejects duplicate input ports",
			mutate: func(flow *FlowDocument) {
				flow.Body.Nodes[2].Inputs = append(
					flow.Body.Nodes[2].Inputs,
					FlowPort{Port: "left", Schema: "artifact/text"},
				)
			},
			wantErrText: `duplicate input port "left" on node "c"`,
		},
		{
			name: "rejects duplicate output ports",
			mutate: func(flow *FlowDocument) {
				flow.Body.Nodes[0].Outputs = append(
					flow.Body.Nodes[0].Outputs,
					FlowPort{Port: "out", Schema: "artifact/text"},
				)
			},
			wantErrText: `duplicate output port "out" on node "a"`,
		},
		{
			name: "rejects missing source node",
			mutate: func(flow *FlowDocument) {
				flow.Body.Edges[0].From.Node = "missing"
			},
			wantErrText: "edge references missing source node: missing",
		},
		{
			name: "rejects missing target node",
			mutate: func(flow *FlowDocument) {
				flow.Body.Edges[0].To.Node = "missing"
			},
			wantErrText: "edge references missing target node: missing",
		},
		{
			name: "rejects missing source output port",
			mutate: func(flow *FlowDocument) {
				flow.Body.Edges[0].From.Port = "missing"
			},
			wantErrText: `edge references missing source output port "missing" on node "a"`,
		},
		{
			name: "rejects missing target input port",
			mutate: func(flow *FlowDocument) {
				flow.Body.Edges[0].To.Port = "missing"
			},
			wantErrText: `edge references missing target input port "missing" on node "c"`,
		},
		{
			name: "rejects multiple outgoing edges from one output port",
			mutate: func(flow *FlowDocument) {
				flow.Body.Nodes = append(
					flow.Body.Nodes,
					FlowNode{
						ID:     "d",
						Type:   "file.write",
						Inputs: []FlowPort{{Port: "in", Schema: "artifact/text"}},
					},
				)
				flow.Body.Edges = append(
					flow.Body.Edges,
					FlowEdge{
						From: FlowEndpoint{Node: "a", Port: "out"},
						To:   FlowEndpoint{Node: "d", Port: "in"},
					},
				)
			},
			wantErrText: `single-chain violation: output port "out" on node "a" has multiple outgoing edges`,
		},
		{
			name: "rejects multiple incoming edges to one input port",
			mutate: func(flow *FlowDocument) {
				flow.Body.Edges[1].To.Port = "left"
			},
			wantErrText: `single-chain violation: input port "left" on node "c" has multiple incoming edges`,
		},
		{
			name: "rejects cycles",
			mutate: func(flow *FlowDocument) {
				flow.Body.Nodes[0].Inputs = []FlowPort{{Port: "in", Schema: "artifact/text"}}
				flow.Body.Edges = append(
					flow.Body.Edges,
					FlowEdge{
						From: FlowEndpoint{Node: "c", Port: "out"},
						To:   FlowEndpoint{Node: "a", Port: "in"},
					},
				)
			},
			wantErrText: "flow contains a cycle",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			flow := baseFlow()
			if tc.mutate != nil {
				tc.mutate(&flow)
			}

			got, err := ValidateRunnableFlow(flow)
			if tc.wantErrText != "" {
				if err == nil {
					t.Fatal("expected error, got nil")
				}
				if !strings.Contains(err.Error(), tc.wantErrText) {
					t.Fatalf("expected error containing %q, got %q", tc.wantErrText, err.Error())
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}

			gotOrder := make([]string, 0, len(got))
			for _, node := range got {
				gotOrder = append(gotOrder, node.ID)
			}
			if len(gotOrder) != len(tc.wantOrder) {
				t.Fatalf("expected %d ordered nodes, got %d", len(tc.wantOrder), len(gotOrder))
			}
			for i := range tc.wantOrder {
				if gotOrder[i] != tc.wantOrder[i] {
					t.Fatalf("expected order %v, got %v", tc.wantOrder, gotOrder)
				}
			}
		})
	}
}
