package cli

import (
	"context"

	"github.com/spf13/cobra"
)

func Execute(ctx context.Context, cmd *cobra.Command, args []string, version string) error {
	cmd.Version = version
	cmd.SetArgs(args)
	return cmd.ExecuteContext(ctx)
}
