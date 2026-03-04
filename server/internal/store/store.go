package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

var (
	ErrDocumentNotFound = errors.New("document not found")
	ErrDocumentExists   = errors.New("document already exists")
	ErrHeadNotFound     = errors.New("head not found")
)

type Document struct {
	DocType     string
	DocID       string
	VerID       string
	WorkspaceID string
	CreatedAt   string
	Ref         sql.NullString
	KeyNS       sql.NullString
	KeyName     sql.NullString
	JSON        string
}

type Store struct {
	db *sql.DB
}

type MemoryRow struct {
	DocID     string
	VerID     string
	CreatedAt string
	JSON      string
}

type DocumentListRow struct {
	DocID     string
	VerID     string
	CreatedAt string
	Ref       sql.NullString
	JSON      string
}

func Open(ctx context.Context, dbPath string) (*Store, error) {
	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return nil, fmt.Errorf("open sqlite: %w", err)
	}

	if err := db.PingContext(ctx); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("ping sqlite: %w", err)
	}

	if err := applyMigrations(ctx, db); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("apply migrations: %w", err)
	}

	return &Store{db: db}, nil
}

func (s *Store) Close() error {
	return s.db.Close()
}

func (s *Store) PutDocument(ctx context.Context, doc Document) error {
	createdAt := doc.CreatedAt
	if createdAt == "" {
		createdAt = time.Now().UTC().Format(time.RFC3339Nano)
	}

	_, err := s.db.ExecContext(ctx, `
		INSERT INTO documents (
			doc_type, doc_id, ver_id, workspace_id, created_at,
			ref, key_namespace, key_name, json
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
	`,
		doc.DocType,
		doc.DocID,
		doc.VerID,
		doc.WorkspaceID,
		createdAt,
		doc.Ref,
		doc.KeyNS,
		doc.KeyName,
		doc.JSON,
	)
	if err != nil {
		if strings.Contains(err.Error(), "UNIQUE constraint failed") {
			return ErrDocumentExists
		}
		return fmt.Errorf("insert document: %w", err)
	}
	return nil
}

func (s *Store) GetDocument(ctx context.Context, docType, docID, verID string) (Document, error) {
	var doc Document
	err := s.db.QueryRowContext(ctx, `
		SELECT doc_type, doc_id, ver_id, workspace_id, created_at,
		       ref, key_namespace, key_name, json
		FROM documents
		WHERE doc_type = ? AND doc_id = ? AND ver_id = ?
	`,
		docType,
		docID,
		verID,
	).Scan(
		&doc.DocType,
		&doc.DocID,
		&doc.VerID,
		&doc.WorkspaceID,
		&doc.CreatedAt,
		&doc.Ref,
		&doc.KeyNS,
		&doc.KeyName,
		&doc.JSON,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return Document{}, ErrDocumentNotFound
	}
	if err != nil {
		return Document{}, fmt.Errorf("get document: %w", err)
	}
	return doc, nil
}

func (s *Store) GetLatestWorkspaceDoc(ctx context.Context, workspaceID string) (Document, error) {
	var doc Document
	err := s.db.QueryRowContext(ctx, `
		SELECT doc_type, doc_id, ver_id, workspace_id, created_at,
		       ref, key_namespace, key_name, json
		FROM documents
		WHERE doc_type = 'workspace' AND workspace_id = ?
		ORDER BY created_at DESC
		LIMIT 1
	`, workspaceID).Scan(
		&doc.DocType,
		&doc.DocID,
		&doc.VerID,
		&doc.WorkspaceID,
		&doc.CreatedAt,
		&doc.Ref,
		&doc.KeyNS,
		&doc.KeyName,
		&doc.JSON,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return Document{}, ErrDocumentNotFound
	}
	if err != nil {
		return Document{}, fmt.Errorf("get latest workspace doc: %w", err)
	}
	return doc, nil
}

func (s *Store) SetHead(ctx context.Context, workspaceID, docID, verID string) error {
	_, err := s.db.ExecContext(ctx, `
		INSERT INTO heads (workspace_id, doc_id, ver_id)
		VALUES (?, ?, ?)
		ON CONFLICT(workspace_id, doc_id) DO UPDATE SET ver_id = excluded.ver_id
	`, workspaceID, docID, verID)
	if err != nil {
		return fmt.Errorf("set head: %w", err)
	}
	return nil
}

func (s *Store) GetHead(ctx context.Context, workspaceID, docID string) (string, error) {
	var verID string
	err := s.db.QueryRowContext(ctx, `
		SELECT ver_id
		FROM heads
		WHERE workspace_id = ? AND doc_id = ?
	`, workspaceID, docID).Scan(&verID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrHeadNotFound
	}
	if err != nil {
		return "", fmt.Errorf("get head: %w", err)
	}
	return verID, nil
}

func (s *Store) ListMemoryByWorkspace(ctx context.Context, workspaceID string, limit, offset int) ([]MemoryRow, error) {
	docRows, err := s.ListDocumentsByType(ctx, workspaceID, "memory", limit, offset)
	if err != nil {
		return nil, err
	}

	result := make([]MemoryRow, 0, len(docRows))
	for _, row := range docRows {
		result = append(result, MemoryRow{
			DocID:     row.DocID,
			VerID:     row.VerID,
			CreatedAt: row.CreatedAt,
			JSON:      row.JSON,
		})
	}
	return result, nil
}

func (s *Store) ListDocumentsByType(ctx context.Context, workspaceID, docType string, limit, offset int) ([]DocumentListRow, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT doc_id, ver_id, created_at, ref, json
		FROM documents
		WHERE doc_type = ? AND workspace_id = ?
		ORDER BY created_at DESC
		LIMIT ? OFFSET ?
	`, docType, workspaceID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("list documents by type: %w", err)
	}
	defer rows.Close()

	result := []DocumentListRow{}
	for rows.Next() {
		var row DocumentListRow
		if err := rows.Scan(&row.DocID, &row.VerID, &row.CreatedAt, &row.Ref, &row.JSON); err != nil {
			return nil, fmt.Errorf("scan document row: %w", err)
		}
		result = append(result, row)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate document rows: %w", err)
	}
	return result, nil
}
