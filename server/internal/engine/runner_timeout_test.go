package engine

import "testing"

func TestLLMTimeoutSecondsSelection(t *testing.T) {
	tests := []struct {
		name           string
		config         map[string]any
		defaultTimeout int
		want           int
		wantErr        bool
	}{
		{
			name:           "uses env default when config missing",
			config:         nil,
			defaultTimeout: 120,
			want:           120,
		},
		{
			name:           "uses node config override",
			config:         map[string]any{"timeout_seconds": 42.0},
			defaultTimeout: 120,
			want:           42,
		},
		{
			name:           "clamps low override to minimum",
			config:         map[string]any{"timeout_seconds": 1.0},
			defaultTimeout: 120,
			want:           5,
		},
		{
			name:           "clamps high override to maximum",
			config:         map[string]any{"timeout_seconds": 9999.0},
			defaultTimeout: 120,
			want:           900,
		},
		{
			name:           "rejects invalid override type",
			config:         map[string]any{"timeout_seconds": "slow"},
			defaultTimeout: 120,
			wantErr:        true,
		},
		{
			name:           "rejects non-positive override",
			config:         map[string]any{"timeout_seconds": 0.0},
			defaultTimeout: 120,
			wantErr:        true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := llmTimeoutSeconds(tc.config, tc.defaultTimeout)
			if tc.wantErr {
				if err == nil {
					t.Fatalf("expected error, got timeout=%d", got)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tc.want {
				t.Fatalf("expected timeout=%d, got %d", tc.want, got)
			}
		})
	}
}
