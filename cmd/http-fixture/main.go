package main

import (
	"context"
	"os"

	"github.com/FlameFlag/nix-dotfiles/internal/common/cli"
	"github.com/FlameFlag/nix-dotfiles/internal/common/envx"
	"github.com/FlameFlag/nix-dotfiles/internal/httpfixture"
	"github.com/spf13/cobra"
)

var version = "dev"

type environment struct {
	Config string `env:"HTTP_FIXTURE_CONFIG"`
}

func main() {
	environment := envx.MustParse[environment]()
	if environment.Config == "" {
		environment.Config = httpfixture.DefaultConfigPath
	}
	options := httpfixture.Options{
		Config: environment.Config,
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
