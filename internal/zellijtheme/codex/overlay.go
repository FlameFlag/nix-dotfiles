package codex

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/FlameFlag/nix-dotfiles/internal/common/envx"
	"github.com/FlameFlag/nix-dotfiles/internal/common/fileutil"
	"github.com/FlameFlag/nix-dotfiles/internal/common/userdirs"
	"github.com/otiai10/copy"
)

type environment struct {
	Home                      string `env:"CODEX_HOME"`
	PruneUnreachableMCP       string `env:"ZELLIJ_THEME_RUN_PRUNE_UNREACHABLE_MCP"`
	LegacyPruneUnreachableMCP string `env:"CODEX_ZELLIJ_THEME_PRUNE_UNREACHABLE_MCP"`
}

var stableCodexDirs = []string{
	".tmp",
	"cache",
	"computer-use",
	"plugins",
	"sessions",
	"shell_snapshots",
	"skills",
	"themes",
	"tmp",
}

var stableCodexFiles = []string{
	".personality_migration",
	"auth.json",
	"goals_1.sqlite",
	"goals_1.sqlite-shm",
	"goals_1.sqlite-wal",
	"history.jsonl",
	"installation_id",
	"logs_2.sqlite",
	"logs_2.sqlite-shm",
	"logs_2.sqlite-wal",
	"memories_1.sqlite",
	"memories_1.sqlite-shm",
	"memories_1.sqlite-wal",
	"models_cache.json",
	"state_5.sqlite",
	"state_5.sqlite-shm",
	"state_5.sqlite-wal",
	"version.json",
}

func CreateTrustOverlay(tuiTheme string) (string, func(), error) {
	overlay, _, cleanup, err := CreateTrustOverlayForArgs(tuiTheme, nil)
	return overlay, cleanup, err
}

func CreateTrustOverlayForArgs(tuiTheme string, extraArgs []string) (string, []string, func(), error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", nil, nil, err
	}

	codexHome := filepath.Join(home, ".codex")
	if value := envx.MustParse[environment]().Home; value != "" {
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
			return "", nil, nil, err
		}
	}

	overlayRoot := filepath.Join(userdirs.CacheHome(home), "zellij-theme-run/codex")
	if err := os.MkdirAll(codexHome, 0o755); err != nil {
		return "", nil, nil, err
	}
	if err := os.MkdirAll(overlayRoot, 0o755); err != nil {
		return "", nil, nil, err
	}
	overlay, err := os.MkdirTemp(overlayRoot, "codex-trust")
	if err != nil {
		return "", nil, nil, err
	}
	cleanup := func() {
		_ = persistOverlayAuth(codexHome, overlay)
		_ = os.RemoveAll(overlay)
	}

	entries, err := os.ReadDir(codexHome)
	if err != nil {
		cleanup()
		return "", nil, nil, err
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
				return "", nil, nil, err
			}
			continue
		}
		if err := copy.Copy(source, target); err != nil {
			cleanup()
			return "", nil, nil, err
		}
	}
	if err := ensureStableCodexState(codexHome, overlay); err != nil {
		cleanup()
		return "", nil, nil, err
	}

	existing := ""
	if data, err := os.ReadFile(filepath.Join(codexHome, "config.toml")); err == nil {
		existing = string(data)
	}
	filteredArgs := filterUnreachableMCPEnableArgs(existing, extraArgs)
	updated, err := trustedConfig(existing, trustTarget, tuiTheme)
	if err != nil {
		cleanup()
		return "", nil, nil, err
	}
	if _, err := fileutil.WriteTextIfChanged(
		filepath.Join(overlay, "config.toml"),
		updated,
	); err != nil {
		cleanup()
		return "", nil, nil, err
	}
	return overlay, filteredArgs, cleanup, nil
}

func ensureStableCodexState(codexHome, overlay string) error {
	for _, name := range stableCodexDirs {
		source := filepath.Join(codexHome, name)
		if err := os.MkdirAll(source, 0o755); err != nil {
			return err
		}
		if err := symlinkOverlayEntry(source, filepath.Join(overlay, name)); err != nil {
			return err
		}
	}
	for _, name := range stableCodexFiles {
		source := filepath.Join(codexHome, name)
		if err := symlinkOverlayEntry(source, filepath.Join(overlay, name)); err != nil {
			return err
		}
	}
	return nil
}

func symlinkOverlayEntry(source, target string) error {
	if _, err := os.Lstat(target); err == nil {
		return nil
	} else if !os.IsNotExist(err) {
		return err
	}
	return os.Symlink(source, target)
}

func persistOverlayAuth(codexHome, overlay string) error {
	source := filepath.Join(overlay, "auth.json")
	info, err := os.Lstat(source)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	if info.Mode()&os.ModeSymlink != 0 {
		return nil
	}
	if !info.Mode().IsRegular() {
		return nil
	}
	data, err := os.ReadFile(source)
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(codexHome, "auth.json"), data, 0o600)
}
