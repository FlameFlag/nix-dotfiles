package zellijtheme

import (
	"path/filepath"
	"strings"
)

func expandPath(path string) string {
	if path == "" {
		return ""
	}
	home, err := HomeDir()
	if err != nil {
		return path
	}
	if path == "~" {
		return home
	}
	if rest, ok := strings.CutPrefix(path, "~/"); ok {
		return filepath.Join(home, rest)
	}
	return path
}
