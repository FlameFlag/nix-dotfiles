package runner

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/euvlok/nix-dotfiles/internal/ndtools/config"
	"github.com/euvlok/nix-dotfiles/internal/ndtools/manifest"
)

type runResult struct {
	Count  int
	Status int
}

type Options struct {
	Stdout io.Writer
	Stderr io.Writer
}

func Run(ctx context.Context, options Options) int {
	options = normalizeOptions(options)
	toolConfig, err := config.Load()
	if err != nil {
		logf(options.Stdout, "failed to load nd-tools config: %v", err)
		return 2
	}
	prependPath(configuredPathPrefixes(toolConfig.PathPrefixes))
	maybeReexecInImmutableContainer(ctx, options, toolConfig.Immutable.Container)

	manifestPath := getenvDefault(
		"NIX_DOTFILES_TOOL_UPDATE_MANIFEST",
		toolConfig.ManifestPath,
	)

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
	path := os.Getenv("PATH")
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

func maybeReexecInImmutableContainer(ctx context.Context, options Options, container string) {
	if runtime.GOOS != "linux" ||
		os.Getenv("NIX_DOTFILES_TOOL_UPDATE_IN_CONTAINER") == "1" ||
		!pathExists("/run/ostree-booted") {
		return
	}
	distrobox, err := exec.LookPath("distrobox")
	if err != nil {
		return
	}

	container = getenvDefault("NIX_DOTFILES_TOOL_UPDATE_CONTAINER", container)
	probe := exec.CommandContext(ctx, distrobox, "enter", "--name", container, "--", "true")
	if err := probe.Run(); err != nil {
		return
	}

	exe, err := os.Executable()
	if err != nil {
		return
	}
	logf(options.Stdout, "re-executing tool updater inside Distrobox container: %s", container)
	cmd := exec.CommandContext(ctx, distrobox, "enter", "--name", container, "--", "env",
		"NIX_DOTFILES_TOOL_UPDATE_IN_CONTAINER=1",
		"NIX_DOTFILES_TOOL_UPDATE_MANIFEST="+os.Getenv("NIX_DOTFILES_TOOL_UPDATE_MANIFEST"),
		"PATH="+os.Getenv("PATH"),
		exe,
		"update",
	)
	cmd.Stdout = options.Stdout
	cmd.Stderr = options.Stderr
	if err := cmd.Run(); err != nil {
		if exitErr, ok := errors.AsType[*exec.ExitError](err); ok {
			os.Exit(exitErr.ExitCode())
		}
		fmt.Fprintf(options.Stderr, "%v\n", err)
		os.Exit(1)
	}
	os.Exit(0)
}

func pathKey(path string) string {
	if runtime.GOOS == "windows" {
		return strings.ToLower(path)
	}
	return path
}

func lockRoot() string {
	if runtime.GOOS != "windows" {
		if value := os.Getenv("XDG_RUNTIME_DIR"); value != "" {
			return value
		}
	}
	for _, key := range []string{"TMPDIR", "TMP", "TEMP"} {
		if value := os.Getenv(key); value != "" {
			return value
		}
	}
	return os.TempDir()
}

func getenvDefault(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
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
