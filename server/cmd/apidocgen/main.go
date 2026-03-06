package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"

	"github.com/dgraham-io/cyaichi/server/internal/httpapi"
)

func main() {
	outPath, err := endpointsDocPath()
	if err != nil {
		panic(err)
	}
	if err := os.MkdirAll(filepath.Dir(outPath), 0o755); err != nil {
		panic(err)
	}

	content := httpapi.RenderEndpointsMarkdown(httpapi.DocumentedEndpoints())
	if err := os.WriteFile(outPath, []byte(content), 0o644); err != nil {
		panic(err)
	}
	fmt.Printf("wrote %s\n", outPath)
}

func endpointsDocPath() (string, error) {
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		return "", fmt.Errorf("unable to locate apidocgen source path")
	}
	serverDir := filepath.Clean(filepath.Join(filepath.Dir(thisFile), "..", ".."))
	repoRoot := filepath.Clean(filepath.Join(serverDir, ".."))
	return filepath.Join(repoRoot, "docs", "api", "endpoints.md"), nil
}
