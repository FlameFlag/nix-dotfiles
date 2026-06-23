package chezmoi

import "github.com/FlameFlag/nix-dotfiles/internal/chezmoi/hyperwindow"

func InstallHyperWindowTiling(options Options) error {
	if OSWithOptions(options) != Linux {
		return nil
	}
	ctx, err := ContextWithOptions(options)
	if err != nil {
		return err
	}
	return hyperwindow.Install(hyperwindow.Config{
		HomeDir:   ctx.HomeDir,
		SourceDir: ctx.SourceDir,
	})
}
