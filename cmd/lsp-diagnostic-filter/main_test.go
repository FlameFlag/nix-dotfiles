package main

import "testing"

func TestShouldRunNushell(t *testing.T) {
	tests := []struct {
		name      string
		invokedAs string
		args      []string
		want      bool
	}{
		{
			name:      "legacy command name",
			invokedAs: "/nix/store/bin/nushell-lsp-filter",
			want:      true,
		},
		{
			name:      "direct lsp flag",
			invokedAs: "lsp-diagnostic-filter",
			args:      []string{"--lsp"},
			want:      true,
		},
		{
			name:      "direct nushell flag",
			invokedAs: "lsp-diagnostic-filter",
			args:      []string{"-c", "version"},
			want:      true,
		},
		{
			name:      "regular language server",
			invokedAs: "lsp-diagnostic-filter",
			args:      []string{"nil"},
			want:      false,
		},
		{
			name:      "command delimiter",
			invokedAs: "lsp-diagnostic-filter",
			args:      []string{"--", "bash-language-server", "start"},
			want:      false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := shouldRunNushell(tt.invokedAs, tt.args); got != tt.want {
				t.Fatalf("shouldRunNushell() = %v; want %v", got, tt.want)
			}
		})
	}
}
