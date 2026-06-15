package manifest

import (
	"os"
	"path/filepath"
	"testing"
)

func TestReadSupportsToolsAndToolTables(t *testing.T) {
	path := filepath.Join(t.TempDir(), "tool-updates.toml")
	data := []byte(`
[[tools]]
name = "codex"
provider = "bun-global"
package = "@openai/codex@latest"

[[tool]]
name = "yt-dlp"
provider = "uv-tool-source"
target = "yt-dlp[default]"
source = "https://example.test/yt-dlp.tar.gz"
enabled = false
`)
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}

	tools, err := Read(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(tools) != 2 {
		t.Fatalf("len(tools) = %d, want 2", len(tools))
	}
	if tools[0].Name != "codex" || tools[0].Package != "@openai/codex@latest" {
		t.Fatalf("first tool = %#v", tools[0])
	}
	if tools[1].Name != "yt-dlp" || tools[1].Target != "yt-dlp[default]" || tools[1].Enabled == nil || *tools[1].Enabled {
		t.Fatalf("second tool = %#v", tools[1])
	}
}
