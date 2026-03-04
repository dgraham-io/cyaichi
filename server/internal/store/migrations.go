package store

import (
	"context"
	"database/sql"
	"fmt"
	"time"
)

type migration struct {
	id  int
	sql string
}

var migrations = []migration{
	{
		id: 1,
		sql: `
			CREATE TABLE IF NOT EXISTS documents (
				doc_type TEXT NOT NULL,
				doc_id TEXT NOT NULL,
				ver_id TEXT NOT NULL,
				workspace_id TEXT NOT NULL,
				created_at TEXT NOT NULL,
				ref TEXT NULL,
				key_namespace TEXT NULL,
				key_name TEXT NULL,
				json TEXT NOT NULL,
				PRIMARY KEY (doc_type, doc_id, ver_id)
			);

			CREATE TABLE IF NOT EXISTS heads (
				workspace_id TEXT NOT NULL,
				doc_id TEXT NOT NULL,
				ver_id TEXT NOT NULL,
				PRIMARY KEY (workspace_id, doc_id)
			);

			CREATE INDEX IF NOT EXISTS idx_documents_workspace_doc_type
				ON documents(workspace_id, doc_type);
			CREATE INDEX IF NOT EXISTS idx_documents_workspace_ref
				ON documents(workspace_id, ref);
			CREATE INDEX IF NOT EXISTS idx_documents_key_namespace_key_name
				ON documents(key_namespace, key_name);
		`,
	},
}

func applyMigrations(ctx context.Context, db *sql.DB) error {
	if _, err := db.ExecContext(ctx, `
		CREATE TABLE IF NOT EXISTS schema_migrations (
			id INTEGER PRIMARY KEY,
			applied_at TEXT NOT NULL
		)
	`); err != nil {
		return fmt.Errorf("create schema_migrations: %w", err)
	}

	for _, m := range migrations {
		applied, err := isMigrationApplied(ctx, db, m.id)
		if err != nil {
			return err
		}
		if applied {
			continue
		}

		tx, err := db.BeginTx(ctx, nil)
		if err != nil {
			return fmt.Errorf("begin migration %d: %w", m.id, err)
		}

		if _, err := tx.ExecContext(ctx, m.sql); err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("execute migration %d: %w", m.id, err)
		}

		if _, err := tx.ExecContext(ctx, `
			INSERT INTO schema_migrations (id, applied_at) VALUES (?, ?)
		`, m.id, time.Now().UTC().Format(time.RFC3339Nano)); err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("record migration %d: %w", m.id, err)
		}

		if err := tx.Commit(); err != nil {
			return fmt.Errorf("commit migration %d: %w", m.id, err)
		}
	}

	return nil
}

func isMigrationApplied(ctx context.Context, db *sql.DB, id int) (bool, error) {
	var count int
	if err := db.QueryRowContext(ctx, `
		SELECT COUNT(1) FROM schema_migrations WHERE id = ?
	`, id).Scan(&count); err != nil {
		return false, fmt.Errorf("check migration %d: %w", id, err)
	}
	return count > 0, nil
}
