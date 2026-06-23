package app

import (
	"os"

	"github.com/FlameFlag/nix-dotfiles/internal/ndtools/runner"
	"github.com/FlameFlag/nix-dotfiles/internal/ndtools/schedule"
	"github.com/spf13/cobra"
)

func Command() *cobra.Command {
	root := &cobra.Command{
		Use:          "nd-tools",
		Short:        "Run and install nix-dotfiles tool updates",
		Args:         cobra.NoArgs,
		SilenceUsage: true,
		Run: func(cmd *cobra.Command, args []string) {
			os.Exit(runner.Run(cmd.Context(), runner.Options{}))
		},
	}
	root.AddCommand(updateCommand(), installCommand())
	return root
}

func updateCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "update",
		Short: "Run configured tool updates",
		Args:  cobra.NoArgs,
		Run: func(cmd *cobra.Command, args []string) {
			os.Exit(runner.Run(cmd.Context(), runner.Options{}))
		},
	}
}

func installCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "install",
		Short: "Install the Windows scheduled task",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return schedule.Install(cmd.Context(), schedule.Options{})
		},
	}
}
