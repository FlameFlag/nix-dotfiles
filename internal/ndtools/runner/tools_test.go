package runner

import (
	"bytes"
	"context"
	"strings"
	"testing"

	"github.com/euvlok/nix-dotfiles/internal/ndtools/manifest"
	"github.com/euvlok/nix-dotfiles/internal/ndtools/provider"
)

var testProviders = []provider.Spec{
	{
		Name:     "bun-global",
		Argv:     []string{"bun", "install", "--global", "{{ .Package }}"},
		Required: []string{"name", "provider", "package"},
	},
}

func TestRunManifestToolSkipsDisabled(t *testing.T) {
	var stdout bytes.Buffer
	enabled := false
	status := runManifestTool(context.Background(), Options{Stdout: &stdout}, testProviders, manifest.Tool{
		Name:     "codex",
		Provider: "bun-global",
		Package:  "@openai/codex@latest",
		Enabled:  &enabled,
	})

	if status != 0 {
		t.Fatalf("status = %d, want 0", status)
	}
	if !strings.Contains(stdout.String(), "skipping disabled manifest updater: codex") {
		t.Fatalf("stdout = %q", stdout.String())
	}
}

func TestRunManifestToolMissingProgramReturns127(t *testing.T) {
	t.Setenv("PATH", "")
	var stdout bytes.Buffer
	status := runManifestTool(context.Background(), Options{Stdout: &stdout}, testProviders, manifest.Tool{
		Name:     "codex",
		Provider: "bun-global",
		Package:  "@openai/codex@latest",
	})

	if status != 127 {
		t.Fatalf("status = %d, want 127", status)
	}
	if !strings.Contains(stdout.String(), "skipping codex: bun not found") {
		t.Fatalf("stdout = %q", stdout.String())
	}
}
