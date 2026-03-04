package store

import (
	"context"
	"database/sql"
	"errors"
	"path/filepath"
	"testing"
)

func openTestStore(t *testing.T) *Store {
	t.Helper()

	dbPath := filepath.Join(t.TempDir(), "test.db")
	s, err := Open(context.Background(), dbPath)
	if err != nil {
		t.Fatalf("open test store: %v", err)
	}

	t.Cleanup(func() {
		if err := s.Close(); err != nil {
			t.Fatalf("close test store: %v", err)
		}
	})

	return s
}

func TestPutAndGetDocument(t *testing.T) {
	s := openTestStore(t)
	ctx := context.Background()

	in := Document{
		DocType:     "flow",
		DocID:       "doc-123",
		VerID:       "ver-1",
		WorkspaceID: "ws-1",
		CreatedAt:   "2026-03-03T00:00:00Z",
		Ref:         sql.NullString{String: "refs/heads/main", Valid: true},
		KeyNS:       sql.NullString{String: "flow", Valid: true},
		KeyName:     sql.NullString{String: "intro", Valid: true},
		JSON:        `{"id":"doc-123","name":"Intro"}`,
	}

	if err := s.PutDocument(ctx, in); err != nil {
		t.Fatalf("put document: %v", err)
	}

	got, err := s.GetDocument(ctx, in.DocType, in.DocID, in.VerID)
	if err != nil {
		t.Fatalf("get document: %v", err)
	}

	if got.DocType != in.DocType ||
		got.DocID != in.DocID ||
		got.VerID != in.VerID ||
		got.WorkspaceID != in.WorkspaceID ||
		got.CreatedAt != in.CreatedAt ||
		got.Ref != in.Ref ||
		got.KeyNS != in.KeyNS ||
		got.KeyName != in.KeyName ||
		got.JSON != in.JSON {
		t.Fatalf("document mismatch: got=%+v want=%+v", got, in)
	}
}

func TestPutDocumentDuplicateVersionFails(t *testing.T) {
	s := openTestStore(t)
	ctx := context.Background()

	doc := Document{
		DocType:     "flow",
		DocID:       "doc-123",
		VerID:       "ver-1",
		WorkspaceID: "ws-1",
		CreatedAt:   "2026-03-03T00:00:00Z",
		JSON:        `{"id":"doc-123"}`,
	}

	if err := s.PutDocument(ctx, doc); err != nil {
		t.Fatalf("first insert failed: %v", err)
	}

	if err := s.PutDocument(ctx, doc); err == nil {
		t.Fatalf("expected duplicate insert to fail")
	}
}

func TestSetAndGetHead(t *testing.T) {
	s := openTestStore(t)
	ctx := context.Background()

	if err := s.SetHead(ctx, "ws-1", "doc-123", "ver-9"); err != nil {
		t.Fatalf("set head: %v", err)
	}

	got, err := s.GetHead(ctx, "ws-1", "doc-123")
	if err != nil {
		t.Fatalf("get head: %v", err)
	}

	if got != "ver-9" {
		t.Fatalf("unexpected head version: got=%q want=%q", got, "ver-9")
	}
}

func TestGetHeadNotFound(t *testing.T) {
	s := openTestStore(t)
	ctx := context.Background()

	_, err := s.GetHead(ctx, "ws-1", "missing-doc")
	if !errors.Is(err, ErrHeadNotFound) {
		t.Fatalf("expected ErrHeadNotFound, got %v", err)
	}
}
