package userdirs

import (
	"os"
	"path/filepath"

	"github.com/adrg/xdg"
)

func ConfigHome(home string) string {
	if value := os.Getenv("XDG_CONFIG_HOME"); value != "" {
		return value
	}
	return homeRelative(home, xdg.ConfigHome, ".config")
}

func DataHome(home string) string {
	if value := os.Getenv("XDG_DATA_HOME"); value != "" {
		return value
	}
	return homeRelative(home, xdg.DataHome, ".local/share")
}

func StateHome(home string) string {
	if value := os.Getenv("XDG_STATE_HOME"); value != "" {
		return value
	}
	return homeRelative(home, xdg.StateHome, ".local/state")
}

func CacheHome(home string) string {
	if value := os.Getenv("XDG_CACHE_HOME"); value != "" {
		return value
	}
	return homeRelative(home, xdg.CacheHome, ".cache")
}

func BinHome(home string) string {
	if value := os.Getenv("XDG_BIN_HOME"); value != "" {
		return value
	}
	return homeRelative(home, xdg.BinHome, ".local/bin")
}

func homeRelative(home, detected, rel string) string {
	if home != "" {
		return filepath.Join(home, rel)
	}
	if detected != "" {
		return detected
	}
	return filepath.Join(".", rel)
}
