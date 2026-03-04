package engine

import (
	"context"
	"time"

	"github.com/google/uuid"
)

type InvocationRecord struct {
	InvocationID string              `json:"invocation_id"`
	NodeID       string              `json:"node_id"`
	Status       string              `json:"status"`
	StartedAt    string              `json:"started_at"`
	EndedAt      string              `json:"ended_at"`
	Inputs       []map[string]string `json:"inputs"`
	Outputs      []map[string]string `json:"outputs"`
}

type NodeRunner interface {
	RunNode(ctx context.Context, node FlowNode) (InvocationRecord, error)
}

type StubNodeRunner struct{}

func (s StubNodeRunner) RunNode(_ context.Context, node FlowNode) (InvocationRecord, error) {
	now := time.Now().UTC().Format(time.RFC3339)
	return InvocationRecord{
		InvocationID: uuid.NewString(),
		NodeID:       node.ID,
		Status:       "succeeded",
		StartedAt:    now,
		EndedAt:      now,
		Inputs:       []map[string]string{},
		Outputs:      []map[string]string{},
	}, nil
}
