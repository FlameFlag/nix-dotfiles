package flake

import (
	"os"
	"path/filepath"
)

func Default(homeDir, workDir, operatingSystem string) string {
	for _, candidate := range defaultCandidates(homeDir, workDir, operatingSystem) {
		info, err := os.Stat(filepath.Join(candidate, "flake.nix"))
		if err == nil && !info.IsDir() {
			return candidate
		}
	}
	return ""
}

func defaultCandidates(homeDir, workDir, operatingSystem string) []string {
	candidates := []string{workDir}
	if homeDir == "" {
		return append(candidates, "/etc/nixos")
	}
	switch operatingSystem {
	case "darwin":
		candidates = append(candidates, filepath.Join(homeDir, "Developer", "nix-dotfiles"))
	case "linux":
		candidates = append(candidates, filepath.Join(homeDir, "nix-dotfiles"))
	default:
		candidates = append(candidates, filepath.Join(homeDir, "nix-dotfiles"))
	}
	return append(candidates, "/etc/nixos")
}

func Normalize(path string) (string, error) {
	info, ok := existingPathInfo(path)
	if !ok {
		return path, nil
	}
	if !info.IsDir() {
		return path, nil
	}
	resolved, err := filepath.EvalSymlinks(path)
	if err != nil {
		return "", err
	}
	return filepath.Abs(resolved)
}

func existingPathInfo(path string) (os.FileInfo, bool) {
	info, err := os.Stat(path)
	return info, err == nil
}
