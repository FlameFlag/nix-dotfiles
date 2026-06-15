package chezmoi

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

type Options struct {
	HomeDir   string
	SourceDir string
	OS        string
}

type Context struct {
	HomeDir   string
	SourceDir string
}

type OSName string

const (
	Darwin  OSName = "darwin"
	Linux   OSName = "linux"
	Windows OSName = "windows"
)

func ContextWithOptions(options Options) (Context, error) {
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return Context{}, fmt.Errorf("environment variable HOME is required")
	}
	homeDir := firstNonEmpty(options.HomeDir, os.Getenv("CHEZMOI_HOME_DIR"), home)
	sourceDir := firstNonEmpty(options.SourceDir, os.Getenv("CHEZMOI_SOURCE_DIR"))
	if sourceDir == "" {
		sourceDir, err = inferSourceDir()
		if err != nil {
			return Context{}, err
		}
	}
	return Context{HomeDir: homeDir, SourceDir: sourceDir}, nil
}

func OSWithOptions(options Options) OSName {
	name := firstNonEmpty(options.OS, os.Getenv("CHEZMOI_OS"), runtime.GOOS)
	switch name {
	case "darwin", "macos":
		return Darwin
	case "linux":
		return Linux
	case "windows":
		return Windows
	default:
		return OSName(name)
	}
}

func inferSourceDir() (string, error) {
	start, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for dir := start; ; dir = filepath.Dir(dir) {
		if isChezmoiSourceDir(dir) {
			return dir, nil
		}
		dotfiles := filepath.Join(dir, "dotfiles")
		if isChezmoiSourceDir(dotfiles) {
			return dotfiles, nil
		}
		next := filepath.Dir(dir)
		if next == dir {
			break
		}
	}
	return "", fmt.Errorf(
		"could not find chezmoi source dir from %s; pass --source-dir DIR or run from this repo",
		start,
	)
}

func isChezmoiSourceDir(path string) bool {
	for _, file := range []string{".chezmoiignore", ".chezmoiexternal.toml", ".chezmoiexternal.toml.tmpl"} {
		if info, err := os.Stat(filepath.Join(path, file)); err == nil && !info.IsDir() {
			return true
		}
	}
	if info, err := os.Stat(filepath.Join(path, ".chezmoiscripts")); err == nil && info.IsDir() {
		return true
	}
	return false
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}
