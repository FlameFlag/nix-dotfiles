package runner

import (
	"context"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/FlameFlag/nix-dotfiles/internal/common/envx"
	"github.com/FlameFlag/nix-dotfiles/internal/ndtools/config"
	"github.com/FlameFlag/nix-dotfiles/internal/ndtools/manifest"
)

var runtimeGOOS = runtime.GOOS

type runResult struct {
	Count  int
	Status int
}

type Options struct {
	Stdout io.Writer
	Stderr io.Writer
}

type environment struct {
	Manifest    string `env:"NIX_DOTFILES_TOOL_UPDATE_MANIFEST"`
	Container   string `env:"NIX_DOTFILES_TOOL_UPDATE_CONTAINER"`
	InContainer bool   `env:"NIX_DOTFILES_TOOL_UPDATE_IN_CONTAINER"`
	Native      bool   `env:"NIX_DOTFILES_TOOL_UPDATE_NATIVE"`
	OstreePath  string `env:"NIX_DOTFILES_OSTREE_BOOTED_PATH" envDefault:"/run/ostree-booted"`
	Path        string `env:"PATH"`
	RuntimeDir  string `env:"XDG_RUNTIME_DIR"`
	TmpDir      string `env:"TMPDIR"`
	Tmp         string `env:"TMP"`
	Temp        string `env:"TEMP"`
}

func Run(ctx context.Context, options Options) int {
	options = normalizeOptions(options)
	toolConfig, err := config.Load()
	if err != nil {
		logf(options.Stdout, "failed to load nd-tools config: %v", err)
		return 2
	}
	prependPath(configuredPathPrefixes(toolConfig.PathPrefixes))
	if status, reexecuted := maybeReexecInImmutableContainer(ctx, options, toolConfig.Immutable.Container); reexecuted {
		return status
	}

	environment := envx.MustParse[environment]()
	manifestPath := firstNonEmpty(environment.Manifest, toolConfig.ManifestPath)

	lockDir := filepath.Join(lockRoot(), toolConfig.LockName)
	if err := os.Mkdir(lockDir, 0o700); err != nil {
		logf(options.Stdout, "another tool updater is already running")
		return 0
	}
	defer os.Remove(lockDir)

	status := 0
	logf(options.Stdout, "tool update started")

	manifestResult := runManifest(ctx, options, toolConfig, manifestPath)
	if manifestResult.Count == 0 {
		logf(options.Stdout, "no tool updates configured; checked %s", manifestPath)
	}
	if manifestResult.Status != 0 {
		status = manifestResult.Status
	}

	logf(options.Stdout, "tool update finished with status %d", status)
	return status
}

func normalizeOptions(options Options) Options {
	if options.Stdout == nil {
		options.Stdout = os.Stdout
	}
	if options.Stderr == nil {
		options.Stderr = os.Stderr
	}
	return options
}

func configuredPathPrefixes(paths []string) []string {
	var prefixes []string
	for _, path := range paths {
		if path != "" {
			prefixes = append(prefixes, path)
		}
	}
	return prefixes
}

func prependPath(paths []string) {
	environment := envx.MustParse[environment]()
	path := environment.Path
	existing := map[string]bool{}
	for _, entry := range filepath.SplitList(path) {
		if entry != "" {
			existing[pathKey(entry)] = true
		}
	}
	for i := len(paths) - 1; i >= 0; i-- {
		dir := paths[i]
		if dir == "" || !pathExists(dir) || existing[pathKey(dir)] {
			continue
		}
		if path == "" {
			path = dir
		} else {
			path = dir + string(os.PathListSeparator) + path
		}
		existing[pathKey(dir)] = true
	}
	_ = os.Setenv("PATH", path)
}

func maybeReexecInImmutableContainer(ctx context.Context, options Options, container string) (int, bool) {
	environment := envx.MustParse[environment]()
	if runtimeGOOS != "linux" || environment.InContainer || environment.Native {
		return 0, false
	}
	if !pathExists(environment.OstreePath) {
		return 0, false
	}
	distrobox, err := exec.LookPath("distrobox")
	if err != nil {
		return 0, false
	}

	container = firstNonEmpty(environment.Container, container)
	probe := exec.CommandContext(ctx, distrobox, "enter", "--name", container, "--", "true")
	if err := probe.Run(); err != nil {
		return 0, false
	}

	exe, err := os.Executable()
	if err != nil {
		return 0, false
	}
	logf(options.Stdout, "re-executing tool updater inside Distrobox container: %s", container)
	cmd := exec.CommandContext(
		ctx, distrobox, "enter", "--name", container, "--", "env",
		"NIX_DOTFILES_TOOL_UPDATE_IN_CONTAINER=1",
		"NIX_DOTFILES_TOOL_UPDATE_MANIFEST="+environment.Manifest,
		"PATH="+environment.Path,
		exe,
		"update",
	)
	cmd.Stdout = options.Stdout
	cmd.Stderr = options.Stderr
	if err := cmd.Run(); err != nil {
		if exitErr, ok := errors.AsType[*exec.ExitError](err); ok {
			return exitErr.ExitCode(), true
		}
		logf(options.Stderr, "%v", err)
		return 1, true
	}
	return 0, true
}

func pathKey(path string) string {
	if runtimeGOOS == "windows" {
		return strings.ToLower(path)
	}
	return path
}

func lockRoot() string {
	environment := envx.MustParse[environment]()
	if runtimeGOOS != "windows" {
		if environment.RuntimeDir != "" {
			return environment.RuntimeDir
		}
	}
	for _, value := range []string{environment.TmpDir, environment.Tmp, environment.Temp} {
		if value != "" {
			return value
		}
	}
	return os.TempDir()
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func pathExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func runManifest(ctx context.Context, options Options, toolConfig config.Config, path string) runResult {
	if _, err := os.Stat(path); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return runResult{}
		}
		logf(options.Stdout, "failed to read update manifest: %v", err)
		return runResult{Status: 2}
	}

	logf(options.Stdout, "reading update manifest: %s", path)
	tools, err := manifest.Read(path)
	if err != nil {
		logf(options.Stdout, "failed to read update manifest: %v", err)
		return runResult{Status: 2}
	}

	result := runResult{}
	for _, tool := range tools {
		result.Count++
		if status := runManifestTool(ctx, options, toolConfig.Providers, tool); status != 0 {
			result.Status = status
		}
	}
	return result
}
