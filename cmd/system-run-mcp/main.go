package main

import (
	"context"
	"os"

	"github.com/FlameFlag/nix-dotfiles/internal/common/cli"
	"github.com/FlameFlag/nix-dotfiles/internal/systemrun"
	"github.com/spf13/cobra"
)

var version = "dev"

func main() {
	cmd := &cobra.Command{
		Use:   "system-run-mcp",
		Short: "Run the system-run MCP server over stdio",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return systemrun.ServeMCP(context.Background(), os.Stdin, os.Stdout)
		},
	}
	if err := cli.Execute(context.Background(), cmd, os.Args[1:], version); err != nil {
		os.Exit(1)
	}
}
