package flake

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
)

func TestDefaultPrefersWorkDir(t *testing.T) {
	root := t.TempDir()
	home := filepath.Join(root, "home")
	work := filepath.Join(root, "checkout")
	mustMkdir(t, home)
	mustMkdir(t, work)
	mustWrite(t, filepath.Join(work, "flake.nix"), "")

	if got := Default(home, work, "linux"); got != work {
		t.Fatalf("Default() = %q, want %q", got, work)
	}
}

func TestDefaultLinuxCandidatesUseHomeNixDotfiles(t *testing.T) {
	root := t.TempDir()
	home := filepath.Join(root, "home")
	work := filepath.Join(root, "elsewhere")

	candidates := defaultCandidates(home, work, "linux")
	if slices.Contains(candidates, filepath.Join(home, "Developer", "nix-dotfiles")) {
		t.Fatalf("defaultCandidates() = %q, Linux must not include ~/Developer/nix-dotfiles", candidates)
	}
	if !slices.Contains(candidates, filepath.Join(home, "nix-dotfiles")) {
		t.Fatalf("defaultCandidates() = %q, want ~/nix-dotfiles on Linux", candidates)
	}
}

func TestDefaultDarwinCandidatesUseDeveloperNixDotfiles(t *testing.T) {
	root := t.TempDir()
	home := filepath.Join(root, "home")
	work := filepath.Join(root, "elsewhere")

	candidates := defaultCandidates(home, work, "darwin")
	if !slices.Contains(candidates, filepath.Join(home, "Developer", "nix-dotfiles")) {
		t.Fatalf("defaultCandidates() = %q, want ~/Developer/nix-dotfiles on Darwin", candidates)
	}
}

func TestDefaultUsesHomeNixDotfilesBeforeEtcNixosOnLinux(t *testing.T) {
	root := t.TempDir()
	home := filepath.Join(root, "home")
	checkout := filepath.Join(home, "nix-dotfiles")
	mustMkdir(t, checkout)
	mustWrite(t, filepath.Join(checkout, "flake.nix"), "")

	if got := Default(home, filepath.Join(root, "elsewhere"), "linux"); got != checkout {
		t.Fatalf("Default() = %q, want %q", got, checkout)
	}
}

func mustMkdir(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(path, 0o755); err != nil {
		t.Fatal(err)
	}
}

func mustWrite(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}
