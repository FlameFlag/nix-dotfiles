package main

import (
	"context"
	"os"

	"github.com/euvlok/nix-dotfiles/internal/common/cli"
	"github.com/euvlok/nix-dotfiles/internal/httpfixture"
	"github.com/spf13/cobra"
)

var version = "dev"

func main() {
	options := httpfixture.Options{
		Config: httpfixture.DefaultConfigPath,
	}
	if value := os.Getenv("HTTP_FIXTURE_CONFIG"); value != "" {
		options.Config = value
	}
	cmd := &cobra.Command{
		Use:   "http-fixture",
		Short: "Serve TOML-configured HTTP fixture responses",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			app, err := httpfixture.Load(options)
			if err != nil {
				return err
			}
			return httpfixture.Serve(app)
		},
	}
	cmd.Flags().StringVar(&options.Config, "config", options.Config, "TOML configuration path")
	cmd.Flags().StringVar(&options.Listen, "listen", "", "Address to listen on")
	if err := cli.Execute(context.Background(), cmd, os.Args[1:], version); err != nil {
		os.Exit(1)
	}
}
