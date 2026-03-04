package schema

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/santhosh-tekuri/jsonschema/v5"
)

type Validator struct {
	envelope *jsonschema.Schema
	typed    map[string]*jsonschema.Schema
}

func NewValidator() (*Validator, error) {
	schemaDir, err := findSchemaDir()
	if err != nil {
		return nil, err
	}
	return NewValidatorFromDir(schemaDir)
}

func NewValidatorFromDir(schemaDir string) (*Validator, error) {
	compiler := jsonschema.NewCompiler()
	if err := addSchemaResources(compiler, schemaDir); err != nil {
		return nil, err
	}

	envelope, err := compiler.Compile("envelope.schema.json")
	if err != nil {
		return nil, fmt.Errorf("compile envelope schema: %w", err)
	}

	typed := map[string]*jsonschema.Schema{}
	docSchemas := map[string]string{
		"workspace": "workspace.schema.json",
		"flow":      "flow.schema.json",
		"run":       "run.schema.json",
		"artifact":  "artifact.schema.json",
		"memory":    "memory.schema.json",
		"package":   "package.schema.json",
	}

	for docType, filename := range docSchemas {
		s, err := compiler.Compile(filename)
		if err != nil {
			return nil, fmt.Errorf("compile %s schema: %w", docType, err)
		}
		typed[docType] = s
	}

	return &Validator{
		envelope: envelope,
		typed:    typed,
	}, nil
}

func (v *Validator) Validate(docBytes []byte) error {
	var body map[string]any
	if err := json.Unmarshal(docBytes, &body); err != nil {
		return fmt.Errorf("invalid JSON body: %w", err)
	}

	if err := v.envelope.Validate(body); err != nil {
		return fmt.Errorf("envelope validation failed: %w", err)
	}

	docTypeRaw, ok := body["doc_type"]
	if !ok {
		return fmt.Errorf("missing doc_type")
	}
	docType, ok := docTypeRaw.(string)
	if !ok || docType == "" {
		return fmt.Errorf("doc_type must be a non-empty string")
	}

	s, ok := v.typed[docType]
	if !ok {
		return fmt.Errorf("unsupported doc_type: %s", docType)
	}

	if err := s.Validate(body); err != nil {
		return fmt.Errorf("%s schema validation failed: %w", docType, err)
	}

	return nil
}

func addSchemaResources(compiler *jsonschema.Compiler, schemaDir string) error {
	entries, err := os.ReadDir(schemaDir)
	if err != nil {
		return fmt.Errorf("read schema dir: %w", err)
	}

	for _, entry := range entries {
		if entry.IsDir() || filepath.Ext(entry.Name()) != ".json" {
			continue
		}

		path := filepath.Join(schemaDir, entry.Name())
		data, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("read schema file %s: %w", entry.Name(), err)
		}

		if err := compiler.AddResource(entry.Name(), bytes.NewReader(data)); err != nil {
			return fmt.Errorf("add schema resource %s: %w", entry.Name(), err)
		}

		canonicalURL := "https://cyaichi.dev/schemas/v1/" + entry.Name()
		if err := compiler.AddResource(canonicalURL, bytes.NewReader(data)); err != nil {
			return fmt.Errorf("add schema canonical resource %s: %w", canonicalURL, err)
		}
	}

	return nil
}

func findSchemaDir() (string, error) {
	wd, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("get cwd: %w", err)
	}

	dir := wd
	for {
		candidate := filepath.Join(dir, "docs", "schema", "v1")
		info, err := os.Stat(candidate)
		if err == nil && info.IsDir() {
			return candidate, nil
		}

		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}

	return "", fmt.Errorf("could not locate docs/schema/v1 from cwd %s", wd)
}
