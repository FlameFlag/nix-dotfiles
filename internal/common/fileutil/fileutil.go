package fileutil

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"

	"github.com/google/renameio/v2/maybe"
	cp "github.com/otiai10/copy"
)

func WriteExecutable(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	if err := maybe.WriteFile(path, data, 0o644); err != nil {
		return err
	}
	return MakeExecutable(path)
}

func WriteTextIfChanged(path, text string) (bool, error) {
	current, err := os.ReadFile(path)
	if err == nil && bytes.Equal(current, []byte(text)) {
		return false, nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return false, err
	}
	if err := maybe.WriteFile(path, []byte(text), 0o644); err != nil {
		return false, err
	}
	return true, nil
}

func MakeExecutable(path string) error {
	info, err := os.Stat(path)
	if err != nil {
		return err
	}
	return os.Chmod(path, info.Mode()|0o111)
}

func RemoveDirIfExists(path string) error {
	err := os.RemoveAll(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	return err
}

func CopyDirRecursive(src, dst string) error {
	return cp.Copy(src, dst, cp.Options{
		OnSymlink: func(string) cp.SymlinkAction {
			return cp.Shallow
		},
	})
}

func MoveDir(src, dst string) error {
	if err := os.Rename(src, dst); err == nil {
		return nil
	}
	if err := CopyDirRecursive(src, dst); err != nil {
		return err
	}
	return os.RemoveAll(src)
}

func Normalize(path string) string {
	if filepath.IsAbs(path) {
		return filepath.Clean(path)
	}
	cwd, err := os.Getwd()
	if err != nil {
		cwd = "."
	}
	return filepath.Clean(filepath.Join(cwd, path))
}

func RelativeUnder(root, path string) bool {
	root = Normalize(root)
	path = Normalize(path)
	rel, err := filepath.Rel(root, path)
	return err == nil && rel != "." && filepath.IsLocal(rel)
}
