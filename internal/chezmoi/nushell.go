package chezmoi

import (
	"os"
	"path/filepath"

	"github.com/FlameFlag/nix-dotfiles/internal/common/userdirs"
)

func NushellInit() error {
	home, err := shellHomeDir()
	if err != nil {
		return err
	}
	for _, dir := range []string{
		filepath.Join(home, ".config/nushell/completions"),
		filepath.Join(userdirs.CacheHome(home), "starship"),
		filepath.Join(userdirs.CacheHome(home), "zoxide"),
		filepath.Join(home, ".local/share/atuin"),
	} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	return nil
}
