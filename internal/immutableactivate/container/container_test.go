package container

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/euvlok/nix-dotfiles/internal/immutableactivate/config"
)

func TestResolveManifestFindsSourceTreeContainerManifest(t *testing.T) {
	root := t.TempDir()
	manifest := filepath.Join(root, "internal/immutableactivate/container/distrobox.ini")
	if err := os.MkdirAll(filepath.Dir(manifest), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(manifest, []byte("[fedora-nix]\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	got, err := ResolveManifest(config.Options{WorkDir: root})
	if err != nil {
		t.Fatal(err)
	}
	if got != manifest {
		t.Fatalf("ResolveManifest() = %q; want %q", got, manifest)
	}
}
