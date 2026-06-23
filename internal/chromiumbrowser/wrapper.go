package chromiumbrowser

import (
	"errors"
	"os"
	"path/filepath"
	"slices"

	"github.com/buildkite/shellwords"
	"github.com/google/renameio/v2/maybe"
)

func writeWrapper(target, launcher string, options *InstallOptions) error {
	var flags []string
	if options.Flags != "" {
		var err error
		flags, err = shellwords.SplitPosix(options.Flags)
		if err != nil {
			return err
		}
	}
	args := slices.Concat([]string{launcher}, flags, options.extraWrapperFlags)
	content := renderWrapperScript(args)
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		return err
	}
	return maybe.WriteFile(target, []byte(content), 0o755)
}

func replaceSymlink(oldname, newname string) error {
	if err := os.Remove(newname); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return os.Symlink(oldname, newname)
}
