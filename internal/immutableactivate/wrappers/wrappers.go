package wrappers

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/FlameFlag/nix-dotfiles/internal/common/process"
	"github.com/buildkite/shellwords"
	"github.com/google/renameio/v2/maybe"
)

const (
	Marker             = "# nix-dotfiles: immutable-wrapper"
	legacyArchNixGroup = "# group: arch-nix"
	legacyArchDevGroup = "# group: arch-dev"
)

func ExecutableChildren(dir string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	paths := make([]string, 0, len(entries))
	for _, entry := range entries {
		path := filepath.Join(dir, entry.Name())
		info, err := os.Stat(path)
		if err != nil || !process.IsExecutableFile(info) {
			continue
		}
		paths = append(paths, path)
	}
	slices.Sort(paths)
	return paths, nil
}

func InstallHost(profile, wrapperDir, sourceBin string, stderr io.Writer) (string, bool, error) {
	name := filepath.Base(sourceBin)
	dest := filepath.Join(wrapperDir, name)
	if _, err := os.Lstat(dest); err == nil {
		if !Is(dest) {
			fmt.Fprintf(
				stderr,
				"immutable-activate: leaving existing non-managed command alone: %s\n",
				dest,
			)
			return dest, false, nil
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", false, err
	}

	target := filepath.Join(profile, "bin", name)
	text := "#!/bin/sh\n" + Marker + "\nexec " + shellwords.QuotePosix(target) + " \"$@\"\n"
	if err := maybe.WriteFile(dest, []byte(text), 0o755); err != nil {
		return "", false, err
	}
	return dest, true, nil
}

func RemoveStale(wrapperDir string, owned map[string]bool) error {
	entries, err := os.ReadDir(wrapperDir)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		path := filepath.Join(wrapperDir, entry.Name())
		info, err := entry.Info()
		if err != nil || !info.Mode().IsRegular() {
			continue
		}
		if Is(path) && !owned[path] {
			if err := os.Remove(path); err != nil {
				return err
			}
		}
	}
	return nil
}

func RemoveLegacyContainer(wrapperDir string) error {
	entries, err := os.ReadDir(wrapperDir)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	for _, entry := range entries {
		path := filepath.Join(wrapperDir, entry.Name())
		info, err := entry.Info()
		if err != nil || !info.Mode().IsRegular() {
			continue
		}
		if Is(path) && HasLegacyContainerGroup(path) {
			if err := os.Remove(path); err != nil {
				return err
			}
		}
	}
	return nil
}

func HasLegacyContainerGroup(path string) bool {
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	for line := range strings.SplitSeq(string(data), "\n") {
		if line == legacyArchNixGroup || line == legacyArchDevGroup {
			return true
		}
	}
	return false
}

func Is(path string) bool {
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	for line := range strings.SplitSeq(string(data), "\n") {
		if line == Marker {
			return true
		}
	}
	return false
}
