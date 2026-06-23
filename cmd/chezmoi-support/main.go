package main

import (
	"context"
	"os"

	"github.com/FlameFlag/nix-dotfiles/internal/chezmoi"
	"github.com/FlameFlag/nix-dotfiles/internal/common/cli"
	"github.com/spf13/cobra"
)

var version = "dev"

func main() {
	var options chezmoi.Options
	cmd := &cobra.Command{
		Use:   "chezmoi-support",
		Short: "Runtime helpers for dotfiles chezmoi hooks",
	}
	cmd.PersistentFlags().
		StringVar(&options.SourceDir, "source-dir", "", "Dotfiles source directory")
	cmd.PersistentFlags().StringVar(&options.HomeDir, "home-dir", "", "Home directory")
	cmd.PersistentFlags().StringVar(&options.OS, "os", "", "Target operating system")
	for _, spec := range []struct {
		name  string
		short string
	}{
		{"nushell-init", "Generate Nushell initialization files"},
		{"shell-init", "Generate shell initialization files"},
		{"install-vs-extensions", "Install VS Code extensions"},
		{"install-hyper-window-tiling", "Install hyper window tiling integration"},
		{"zed-install-catppuccin-theme", "Install Catppuccin assets for Zed"},
		{"yazi-init", "Install Yazi plugins"},
		{"raycast-beta-patch", "Patch Raycast Beta user metadata"},
	} {
		commandName := spec.name
		cmd.AddCommand(&cobra.Command{
			Use:   commandName,
			Short: spec.short,
			Args:  cobra.NoArgs,
			RunE: func(cmd *cobra.Command, args []string) error {
				return chezmoi.Run(commandName, options)
			},
		})
	}
	if err := cli.Execute(context.Background(), cmd, os.Args[1:], version); err != nil {
		os.Exit(1)
	}
}
