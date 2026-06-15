package chezmoi

import (
	"os"
	"path/filepath"
	"testing"
)

func TestInferSourceDirFromRepoRoot(t *testing.T) {
	temp := t.TempDir()
	dotfiles := filepath.Join(temp, "dotfiles")
	if err := os.MkdirAll(dotfiles, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dotfiles, ".chezmoiignore"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	old, _ := os.Getwd()
	defer os.Chdir(old)
	if err := os.Chdir(temp); err != nil {
		t.Fatal(err)
	}
	got, err := inferSourceDir()
	if err != nil {
		t.Fatal(err)
	}
	got, _ = filepath.EvalSymlinks(got)
	dotfiles, _ = filepath.EvalSymlinks(dotfiles)
	if got != dotfiles {
		t.Fatalf("source dir = %q; want %q", got, dotfiles)
	}
}

func TestExtensionIDsTrimAndSkipEmpty(t *testing.T) {
	path := filepath.Join(t.TempDir(), "extensions.toml")
	if err := os.WriteFile(
		path,
		[]byte(
			"[[extensions]]\nid = \"one.alpha\"\n\n[[extensions]]\nid = \"\"\n\n[[extensions]]\nid = \" Two.Beta \"\n",
		),
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	got := extensionIDsFromFile(path)
	want := []string{"one.alpha", "Two.Beta"}
	if len(got) != len(want) || got[0] != want[0] || got[1] != want[1] {
		t.Fatalf("ids = %#v; want %#v", got, want)
	}
}
