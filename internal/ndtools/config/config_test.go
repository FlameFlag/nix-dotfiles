package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadFileMergesProviderOverride(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nd-tools.toml")
	data := []byte(`
path_prefixes = ["/custom/bin"]

[schedule]
interval_hours = 12

[[providers]]
name = "example"
argv = ["example", "{{ .Package }}"]
required = ["package"]
`)
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}

	config, err := LoadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if config.Schedule.IntervalHours != 12 {
		t.Fatalf("interval_hours = %d, want 12", config.Schedule.IntervalHours)
	}
	if len(config.PathPrefixes) != 1 || config.PathPrefixes[0] != "/custom/bin" {
		t.Fatalf("path_prefixes = %#v", config.PathPrefixes)
	}

	foundDefault := false
	foundCustom := false
	for _, spec := range config.Providers {
		if spec.Name == "bun-global" {
			foundDefault = true
		}
		if spec.Name == "example" {
			foundCustom = true
		}
	}
	if !foundDefault || !foundCustom {
		t.Fatalf("providers = %#v", config.Providers)
	}
}

func TestPathUsesEnvironmentOverride(t *testing.T) {
	t.Setenv("ND_TOOLS_CONFIG", "/tmp/nd-tools.toml")
	if path := Path(); path != "/tmp/nd-tools.toml" {
		t.Fatalf("Path() = %q", path)
	}
}
