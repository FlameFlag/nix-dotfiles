package codex

import (
	"strings"
	"testing"
)

func TestTrustedConfig(t *testing.T) {
	got, err := trustedConfig("model = \"gpt-5.5\"\n", "/repo", "catppuccin-latte-pink")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(got, "trust_level = 'trusted'") ||
		!strings.Contains(got, "approval_policy = 'never'") ||
		!strings.Contains(got, "sandbox_mode = 'danger-full-access'") ||
		!strings.Contains(got, "web_search = 'live'") ||
		!strings.Contains(got, "theme = 'catppuccin-latte-pink'") {
		t.Fatalf("trusted config missing updates:\n%s", got)
	}
}

func TestTrustedConfigOverridesRestrictiveRuntimeSettings(t *testing.T) {
	got, err := trustedConfig(
		"approval_policy = 'on-request'\nsandbox_mode = 'workspace-write'\nweb_search = 'cached'\ntrust_level = 'untrusted'\n",
		"/repo",
		"catppuccin-frappe-pink",
	)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"approval_policy = 'never'",
		"sandbox_mode = 'danger-full-access'",
		"web_search = 'live'",
		"trust_level = 'trusted'",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("trusted config missing %q:\n%s", want, got)
		}
	}
}

func TestTrustedConfigPrunesUnreachableLocalMCP(t *testing.T) {
	got, err := trustedConfig(
		"[mcp_servers.local]\nurl = 'http://127.0.0.1:1/mcp'\n[mcp_servers.remote]\nurl = 'https://example.com/mcp'\n",
		"/repo",
		"catppuccin-frappe-pink",
	)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(got, "local") || !strings.Contains(got, "remote") {
		t.Fatalf("unexpected MCP pruning result:\n%s", got)
	}
}
