package host

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/euvlok/nix-dotfiles/internal/common/userdirs"
	"github.com/euvlok/nix-dotfiles/internal/immutableactivate/config"
	activationruntime "github.com/euvlok/nix-dotfiles/internal/immutableactivate/runtime"
	"github.com/euvlok/nix-dotfiles/internal/immutableactivate/wrappers"
)

func Activate(options config.Options, flake string) error {
	dataHome := config.FirstNonEmpty(options.DataHome, userdirs.DataHome(options.HomeDir))
	binHome := config.FirstNonEmpty(options.BinHome, userdirs.BinHome(options.HomeDir))
	profileRoot := filepath.Join(dataHome, "nix-dotfiles/immutable")
	profile := filepath.Join(profileRoot, "profile")
	wrapperDir := binHome

	if err := os.MkdirAll(profileRoot, 0o755); err != nil {
		return err
	}
	if err := os.MkdirAll(wrapperDir, 0o755); err != nil {
		return err
	}
	if options.Update {
		if err := options.Executor.Run(
			activationruntime.Command{Argv: []string{"nix", "flake", "update", "--flake", flake}},
		); err != nil {
			return err
		}
	}
	if err := options.Executor.Run(
		activationruntime.Command{
			Argv: []string{"nix", "build", "--profile", profile, flake + "#immutable-profile"},
		},
	); err != nil {
		return err
	}
	profileBin := filepath.Join(profile, "bin")
	if info, err := os.Stat(profileBin); err != nil || !info.IsDir() {
		return fmt.Errorf("immutable profile has no bin directory: %s", profileBin)
	}

	sourceBins, err := wrappers.ExecutableChildren(profileBin)
	if err != nil {
		return err
	}
	owned := map[string]bool{}
	for _, sourceBin := range sourceBins {
		dest, managed, err := wrappers.InstallHost(profile, wrapperDir, sourceBin, options.Stderr)
		if err != nil {
			return err
		}
		if managed {
			owned[dest] = true
		}
	}
	if err := wrappers.RemoveStale(wrapperDir, owned); err != nil {
		return err
	}
	if !options.SkipScaffold {
		if err := options.Executor.Run(
			activationruntime.Command{
				Argv: []string{
					"scaffold",
					"--catalog",
					filepath.Join(flake, "scaffold.scm"),
					"install",
				},
			},
		); err != nil {
			return err
		}
	}
	fmt.Fprintf(options.Stdout, "immutable-activate: activated %s#immutable-profile\n", flake)
	fmt.Fprintf(options.Stdout, "immutable-activate: wrappers managed in %s\n", wrapperDir)
	return nil
}
