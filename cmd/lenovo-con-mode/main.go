package main

import (
	"context"
	"os"

	"github.com/euvlok/nix-dotfiles/internal/common/cli"
	"github.com/euvlok/nix-dotfiles/internal/lenovo"
	"github.com/spf13/cobra"
)

var version = "dev"

func main() {
	cmd := &cobra.Command{
		Use:   "lenovo-con-mode",
		Short: "Read or toggle Lenovo conservation mode",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return lenovo.Run(lenovo.Toggle)
		},
	}
	for _, spec := range []struct {
		name   string
		action lenovo.Action
		short  string
	}{
		{"status", lenovo.Status, "Show conservation mode status"},
		{"on", lenovo.On, "Enable conservation mode"},
		{"enable", lenovo.Enable, "Enable conservation mode"},
		{"off", lenovo.Off, "Disable conservation mode"},
		{"disable", lenovo.Disable, "Disable conservation mode"},
		{"toggle", lenovo.Toggle, "Toggle conservation mode"},
	} {
		action := spec.action
		cmd.AddCommand(&cobra.Command{
			Use:   spec.name,
			Short: spec.short,
			Args:  cobra.NoArgs,
			RunE: func(cmd *cobra.Command, args []string) error {
				return lenovo.Run(action)
			},
		})
	}
	if err := cli.Execute(context.Background(), cmd, os.Args[1:], version); err != nil {
		os.Exit(1)
	}
}
