package raycast

import (
	"fmt"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/FlameFlag/nix-dotfiles/internal/common/envx"
	"github.com/FlameFlag/nix-dotfiles/internal/common/httpx"
	"github.com/charmbracelet/log"
)

type avatarEnvironment struct {
	Source string `env:"RAYCAST_AVATAR_SRC"`
}

func (p betaPatcher) ensureAvatar() error {
	avatarPath := p.avatarPath()
	if info, err := os.Stat(avatarPath); err == nil && !info.IsDir() {
		log.Info("avatar exists", "bytes", info.Size())
		return nil
	}
	if err := os.MkdirAll(p.appSupport, 0o755); err != nil {
		return fmt.Errorf("create Raycast app support directory: %w", err)
	}
	if source := envx.MustParse[avatarEnvironment]().Source; source != "" && regularFileExists(source) {
		if ok := resizeAvatar(source, avatarPath); ok {
			log.Info("avatar resized", "source", source)
			return nil
		}
	}
	temp, err := os.CreateTemp("", "raycast-beta-avatar-source-*.png")
	if err != nil {
		return fmt.Errorf("create temporary Raycast avatar path: %w", err)
	}
	tempPath := temp.Name()
	defer os.Remove(tempPath)
	if err := temp.Close(); err != nil {
		return fmt.Errorf("close temporary Raycast avatar: %w", err)
	}
	if err := (&httpx.Client{UserAgent: "nix-dotfiles-chezmoi-support"}).DownloadFile(defaultProfile.AvatarURL, tempPath); err != nil {
		log.Warn("failed to download Raycast avatar; continuing without avatar refresh", "error", err)
		return nil
	}
	if ok := resizeAvatar(tempPath, avatarPath); ok {
		log.Info("avatar downloaded and resized", "source", defaultProfile.AvatarURL)
	}
	return nil
}

func (p betaPatcher) avatarPath() string {
	return filepath.Join(p.appSupport, "avatar.png")
}

func (p betaPatcher) avatarURL() string {
	return (&url.URL{Scheme: "file", Path: p.avatarPath()}).String()
}

func resizeAvatar(source, destination string) bool {
	cmd := exec.Command("sips", "-Z", "256", source, "--out", destination)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run() == nil
}
