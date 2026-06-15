package main

import (
	"context"
	"os"

	"github.com/euvlok/nix-dotfiles/internal/common/cli"
	"github.com/euvlok/nix-dotfiles/internal/immutableactivate"
	"github.com/spf13/cobra"
)

var version = "dev"

var (
	runtimePath       string
	distroboxManifest string
)

func main() {
	options := immutableactivate.Options{
		Flake:             os.Getenv("NIX_DOTFILES_FLAKE"),
		Backend:           "auto",
		HostUpdater:       "auto",
		RuntimePath:       runtimePath,
		DistroboxManifest: distroboxManifest,
	}
	if value := os.Getenv("NIX_DOTFILES_IMMUTABLE_BACKEND"); value != "" {
		options.Backend = value
	}
	if value := os.Getenv("NIX_DOTFILES_HOST_UPDATER"); value != "" {
		options.HostUpdater = value
	}
	cmd := &cobra.Command{
		Use:   "immutable-activate [options]",
		Short: "Build and activate the nix-dotfiles immutable Linux user profile",
		Args:  cobra.NoArgs,
		RunE: func(_ *cobra.Command, args []string) error {
			return immutableactivate.Run(options)
		},
	}
	cmd.Flags().
		StringVar(&options.Flake, "flake", options.Flake, "Use PATH as the nix-dotfiles flake checkout")
	cmd.Flags().
		StringVar(&options.Backend, "backend", options.Backend, "Select activation backend: auto, host, or container")
	cmd.Flags().
		BoolVar(&options.ResetContainers, "reset-containers", false, "With --backend container, delete managed Distrobox containers first")
	cmd.Flags().BoolVar(&options.Update, "update", false, "Run nix flake update before activation")
	cmd.Flags().
		BoolVar(&options.HostUpdate, "host-update", false, "Also run native host/user package updates when available")
	cmd.Flags().
		StringVar(&options.HostUpdater, "host-updater", options.HostUpdater, "Select the native updater: auto, none, rpm-ostree, pacman, dnf, or apt")
	cmd.Flags().
		BoolVar(&options.SkipScaffold, "skip-scaffold", false, "Do not run scaffold install")
	if err := cli.Execute(context.Background(), cmd, os.Args[1:], version); err != nil {
		os.Exit(1)
	}
}
