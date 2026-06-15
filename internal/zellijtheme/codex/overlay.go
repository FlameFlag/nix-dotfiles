package codex

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/euvlok/nix-dotfiles/internal/common/fileutil"
	"github.com/euvlok/nix-dotfiles/internal/common/userdirs"
	"github.com/otiai10/copy"
)

func CreateTrustOverlay(tuiTheme string) (string, func(), error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", nil, err
	}

	codexHome := filepath.Join(home, ".codex")
	if value := os.Getenv("CODEX_HOME"); value != "" {
		if value == "~" {
			value = home
		} else if rest, ok := strings.CutPrefix(value, "~/"); ok {
			value = filepath.Join(home, rest)
		}
		if !strings.HasPrefix(filepath.Base(value), "codex-trust") {
			codexHome = value
		}
	}

	output, err := exec.Command("git", "rev-parse", "--show-toplevel").Output()
	var trustTarget string
	if err == nil && strings.TrimSpace(string(output)) != "" {
		trustTarget = strings.TrimSpace(string(output))
	} else {
		trustTarget, err = os.Getwd()
		if err != nil {
			return "", nil, err
		}
	}

	overlayRoot := filepath.Join(userdirs.CacheHome(home), "zellij-theme-run/codex")
	if err := os.MkdirAll(codexHome, 0o755); err != nil {
		return "", nil, err
	}
	if err := os.MkdirAll(overlayRoot, 0o755); err != nil {
		return "", nil, err
	}
	overlay, err := os.MkdirTemp(overlayRoot, "codex-trust")
	if err != nil {
		return "", nil, err
	}
	cleanup := func() { _ = os.RemoveAll(overlay) }

	entries, err := os.ReadDir(codexHome)
	if err != nil {
		cleanup()
		return "", nil, err
	}
	for _, entry := range entries {
		if entry.Name() == "config.toml" {
			continue
		}
		source := filepath.Join(codexHome, entry.Name())
		target := filepath.Join(overlay, entry.Name())
		if err := os.Symlink(source, target); err == nil {
			continue
		}
		if info, err := os.Stat(target); err == nil && !info.IsDir() {
			continue
		}
		if entry.IsDir() {
			if err := fileutil.CopyDirRecursive(source, target); err != nil {
				cleanup()
				return "", nil, err
			}
			continue
		}
		if err := copy.Copy(source, target); err != nil {
			cleanup()
			return "", nil, err
		}
	}

	existing := ""
	if data, err := os.ReadFile(filepath.Join(codexHome, "config.toml")); err == nil {
		existing = string(data)
	}
	updated, err := trustedConfig(existing, trustTarget, tuiTheme)
	if err != nil {
		cleanup()
		return "", nil, err
	}
	if _, err := fileutil.WriteTextIfChanged(
		filepath.Join(overlay, "config.toml"),
		updated,
	); err != nil {
		cleanup()
		return "", nil, err
	}
	return overlay, cleanup, nil
}
