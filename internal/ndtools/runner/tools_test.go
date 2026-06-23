package runner

import (
	"context"
	"os"
	"testing"

	"github.com/FlameFlag/nix-dotfiles/internal/ndtools/manifest"
	"github.com/FlameFlag/nix-dotfiles/internal/ndtools/provider"
	"github.com/rogpeppe/go-internal/testscript"
)

var testProviders = []provider.Spec{
	{
		Name:     "bun-global",
		Argv:     []string{"bun", "install", "--global", "{{ .Package }}"},
		Required: []string{"name", "provider", "package"},
	},
}

func TestRunManifestToolScripts(t *testing.T) {
	testscript.Run(t, testscript.Params{
		Dir: "testdata/script",
		Cmds: map[string]func(ts *testscript.TestScript, neg bool, args []string){
			"runmanifest": runManifestToolScript,
		},
	})
}

func runManifestToolScript(ts *testscript.TestScript, neg bool, args []string) {
	if neg {
		ts.Fatalf("runmanifest does not support negation")
	}
	if len(args) != 2 {
		ts.Fatalf("usage: runmanifest SCENARIO WANT_STATUS")
	}
	var enabled *bool
	switch args[0] {
	case "disabled":
		value := false
		enabled = &value
	case "missing":
	default:
		ts.Fatalf("unknown runmanifest scenario %q", args[0])
	}
	want := 0
	if args[1] == "127" {
		want = 127
	} else if args[1] != "0" {
		ts.Fatalf("unsupported wanted status %q", args[1])
	}
	oldPath, hadPath := os.LookupEnv("PATH")
	if err := os.Setenv("PATH", ts.Getenv("PATH")); err != nil {
		ts.Fatalf("%v", err)
	}
	defer func() {
		if hadPath {
			_ = os.Setenv("PATH", oldPath)
		} else {
			_ = os.Unsetenv("PATH")
		}
	}()
	status := runManifestTool(context.Background(), Options{Stdout: ts.Stdout()}, testProviders, manifest.Tool{
		Name:     "codex",
		Provider: "bun-global",
		Package:  "@openai/codex@latest",
		Enabled:  enabled,
	})
	if status != want {
		ts.Fatalf("status = %d, want %d", status, want)
	}
}
