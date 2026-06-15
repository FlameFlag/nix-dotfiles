package chezmoi

import (
	"errors"
	"os"
	"path/filepath"

	"github.com/charmbracelet/log"
	"github.com/euvlok/nix-dotfiles/internal/common/fileutil"
	"github.com/euvlok/nix-dotfiles/internal/common/process"
	"github.com/euvlok/nix-dotfiles/internal/common/userdirs"
)

const (
	yaziPluginsRev     = "5d5c4803dd12bab4e4f19d606f8db0c871e6bec5"
	systemClipboardRev = "75a53300bed1946c6d488d42efc34864ea26ca85"
	starshipRev        = "a83710153ab5625a64ef98d55e6ddad480a3756f"
)

func InstallYaziPlugins(options Options) error {
	if _, ok := process.PathOf("git"); !ok {
		return errors.New("git not found")
	}
	ctx, err := ContextWithOptions(options)
	if err != nil {
		return err
	}
	yaziConfig := filepath.Join(userdirs.ConfigHome(ctx.HomeDir), "yazi")
	pluginsDir := filepath.Join(yaziConfig, "plugins")
	flavorsDir := filepath.Join(yaziConfig, "flavors")
	if err := os.MkdirAll(pluginsDir, 0o755); err != nil {
		return err
	}
	if err := os.MkdirAll(flavorsDir, 0o755); err != nil {
		return err
	}
	temp, err := os.MkdirTemp("", "chezmoi-script")
	if err != nil {
		return err
	}
	defer os.RemoveAll(temp)

	log.Info("downloading plugins repository")
	if err := cloneRev("https://github.com/yazi-rs/plugins.git", yaziPluginsRev, temp); err != nil {
		return err
	}
	if err := fileutil.RemoveDirIfExists(filepath.Join(temp, ".git")); err != nil {
		return err
	}
	for _, plugin := range []string{"diff", "full-border", "smart-enter", "smart-paste", "git"} {
		log.Info("installing plugin", "name", plugin)
		dst := filepath.Join(pluginsDir, plugin+".yazi")
		if err := fileutil.RemoveDirIfExists(dst); err != nil {
			return err
		}
		if err := fileutil.CopyDirRecursive(filepath.Join(temp, plugin+".yazi"), dst); err != nil {
			return err
		}
	}
	for _, plugin := range []struct {
		name string
		repo string
		rev  string
	}{
		{"system-clipboard", "https://github.com/orhnk/system-clipboard.yazi.git", systemClipboardRev},
		{"starship", "https://github.com/Rolv-Apneseth/starship.yazi.git", starshipRev},
	} {
		log.Info("installing plugin", "name", plugin.name)
		dst := filepath.Join(pluginsDir, plugin.name+".yazi")
		if err := fileutil.RemoveDirIfExists(dst); err != nil {
			return err
		}
		if err := cloneRev(plugin.repo, plugin.rev, dst); err != nil {
			return err
		}
		if err := fileutil.RemoveDirIfExists(filepath.Join(dst, ".git")); err != nil {
			return err
		}
	}
	log.Info("Yazi plugins installed")
	return nil
}

func cloneRev(repo, rev, dst string) error {
	if err := process.RunInWithEnvAndStdin(
		"",
		[]string{"git", "init", "--quiet", dst},
		nil,
		os.Stdin,
	); err != nil {
		return err
	}
	if err := process.RunInWithEnvAndStdin(
		"",
		[]string{"git", "-C", dst, "remote", "add", "origin", repo},
		nil,
		os.Stdin,
	); err != nil {
		return err
	}
	if err := process.RunInWithEnvAndStdin(
		"",
		[]string{"git", "-C", dst, "fetch", "--depth", "1", "--no-tags", "--quiet", "origin", rev},
		nil,
		os.Stdin,
	); err != nil {
		return err
	}
	return process.RunInWithEnvAndStdin(
		"",
		[]string{"git", "-C", dst, "checkout", "--detach", "--quiet", "FETCH_HEAD"},
		nil,
		os.Stdin,
	)
}
