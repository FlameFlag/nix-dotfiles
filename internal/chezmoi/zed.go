package chezmoi

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/FlameFlag/nix-dotfiles/internal/common/archiveutil"
	"github.com/FlameFlag/nix-dotfiles/internal/common/fileutil"
	"github.com/FlameFlag/nix-dotfiles/internal/common/httpx"
	"github.com/FlameFlag/nix-dotfiles/internal/common/userdirs"
	"github.com/charmbracelet/log"
)

func InstallZedCatppuccinTheme(options Options) error {
	ctx, err := ContextWithOptions(options)
	if err != nil {
		return err
	}
	client := &httpx.Client{UserAgent: "nix-dotfiles-chezmoi-support"}
	themeTag, err := latestTag("catppuccin/zed")
	if err != nil {
		return err
	}
	iconsTag, err := latestTag("catppuccin/zed-icons")
	if err != nil {
		return err
	}

	zedConfig := filepath.Join(userdirs.ConfigHome(ctx.HomeDir), "zed")
	themesDir := filepath.Join(zedConfig, "themes")
	if err := os.MkdirAll(themesDir, 0o755); err != nil {
		return err
	}
	theme, err := client.Text(
		fmt.Sprintf(
			"https://github.com/catppuccin/zed/releases/download/%s/catppuccin-pink.json",
			themeTag,
		),
	)
	if err != nil {
		return err
	}
	themePath := filepath.Join(themesDir, "catppuccin-pink.json")
	if changed, err := fileutil.WriteTextIfChanged(themePath, theme); err != nil {
		return err
	} else if changed {
		log.Info("theme installed", "path", themePath)
	}

	temp, err := os.MkdirTemp("", "chezmoi-script")
	if err != nil {
		return err
	}
	defer os.RemoveAll(temp)
	reader, err := client.Reader(
		fmt.Sprintf("https://codeload.github.com/catppuccin/zed-icons/tar.gz/%s", iconsTag),
	)
	if err != nil {
		return err
	}
	defer reader.Close()
	if err := archiveutil.ExtractTarGz(context.Background(), reader, temp); err != nil {
		return err
	}
	entries, err := os.ReadDir(temp)
	if err != nil {
		return err
	}
	root := ""
	for _, entry := range entries {
		if entry.IsDir() {
			root = temp + string(os.PathSeparator) + entry.Name()
			break
		}
	}
	if root == "" {
		return fmt.Errorf("archive did not contain a root directory")
	}
	if err := os.MkdirAll(filepath.Join(zedConfig, "icon_themes"), 0o755); err != nil {
		return err
	}
	iconThemeTarget := filepath.Join(zedConfig, "icon_themes/catppuccin-icons.json")
	data, err := os.ReadFile(filepath.Join(root, "icon_themes/catppuccin-icons.json"))
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(iconThemeTarget), 0o755); err != nil {
		return err
	}
	if _, err := fileutil.WriteTextIfChanged(iconThemeTarget, string(data)); err != nil {
		return err
	}
	if err := fileutil.RemoveDirIfExists(filepath.Join(zedConfig, "icons")); err != nil {
		return err
	}
	if err := fileutil.CopyDirRecursive(
		filepath.Join(root, "icons"),
		filepath.Join(zedConfig, "icons"),
	); err != nil {
		return err
	}
	log.Info("icon theme installed", "path", zedConfig)
	return nil
}

type githubReleaseResponse struct {
	TagName string `json:"tag_name"`
}

func latestTag(repo string) (string, error) {
	log.Info("fetching latest GitHub release", "repo", repo)
	owner, name, ok := strings.Cut(repo, "/")
	if !ok {
		return "", fmt.Errorf("invalid GitHub repo: %s", repo)
	}
	client := &httpx.Client{UserAgent: "nix-dotfiles-chezmoi-support"}
	var release githubReleaseResponse
	if err := client.JSON(
		fmt.Sprintf("https://api.github.com/repos/%s/%s/releases/latest", owner, name),
		&release,
	); err != nil {
		return "", err
	}
	return release.TagName, nil
}
