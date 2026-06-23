package main

import (
	"context"
	"os"

	"github.com/FlameFlag/nix-dotfiles/internal/common/cli"
	"github.com/FlameFlag/nix-dotfiles/internal/common/envx"
	"github.com/FlameFlag/nix-dotfiles/internal/immutableactivate"
	"github.com/spf13/cobra"
)

var version = "dev"

var (
	runtimePath       string
	distroboxManifest string
)

type environment struct {
	Flake       string `env:"NIX_DOTFILES_FLAKE"`
	Backend     string `env:"NIX_DOTFILES_IMMUTABLE_BACKEND" envDefault:"auto"`
	HostUpdater string `env:"NIX_DOTFILES_HOST_UPDATER" envDefault:"auto"`
}

func main() {
	environment := envx.MustParse[environment]()
	options := immutableactivate.Options{
		Flake:             environment.Flake,
		Backend:           environment.Backend,
		HostUpdater:       environment.HostUpdater,
		RuntimePath:       runtimePath,
		DistroboxManifest: distroboxManifest,
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
		BoolVar(&options.SkipAnsible, "skip-ansible", false, "Do not run Ansible userland install")
	if err := cli.Execute(context.Background(), cmd, os.Args[1:], version); err != nil {
		os.Exit(1)
	}
}
