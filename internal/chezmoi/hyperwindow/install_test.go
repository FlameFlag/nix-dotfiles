package hyperwindow

import (
	"os"
	"path/filepath"
	"testing"
)

func TestFlakeRepoDir(t *testing.T) {
	temp := t.TempDir()
	dotfiles := filepath.Join(temp, "dotfiles")
	if err := os.MkdirAll(filepath.Join(temp, "packages"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(dotfiles, 0o755); err != nil {
		t.Fatal(err)
	}
	_ = os.WriteFile(filepath.Join(temp, "flake.nix"), nil, 0o644)
	_ = os.WriteFile(filepath.Join(temp, "packages/hyper-window-tiling.nix"), nil, 0o644)
	got, err := flakeRepoDir(dotfiles)
	if err != nil {
		t.Fatal(err)
	}
	if got != temp {
		t.Fatalf("repo dir = %q; want %q", got, temp)
	}
}
