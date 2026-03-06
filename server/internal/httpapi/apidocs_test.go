package httpapi

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestApiDocsUpToDate(t *testing.T) {
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("unable to locate test file path")
	}
	serverDir := filepath.Clean(filepath.Join(filepath.Dir(thisFile), "..", ".."))
	repoRoot := filepath.Clean(filepath.Join(serverDir, ".."))
	docPath := filepath.Join(repoRoot, "docs", "api", "endpoints.md")

	actualBytes, err := os.ReadFile(docPath)
	if err != nil {
		t.Fatalf("failed to read %s: %v", docPath, err)
	}
	actual := strings.ReplaceAll(string(actualBytes), "\r\n", "\n")
	expected := strings.ReplaceAll(RenderEndpointsMarkdown(DocumentedEndpoints()), "\r\n", "\n")

	if actual != expected {
		t.Fatalf("API docs are out of date: %s\nrun: make docs (or go generate ./... from server)", docPath)
	}
}
