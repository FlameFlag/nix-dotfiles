package main

import (
	"context"
	"os"

	"github.com/euvlok/nix-dotfiles/internal/common/cli"
	"github.com/euvlok/nix-dotfiles/internal/helium"
	"github.com/spf13/cobra"
)

var version = "dev"

func main() {
	cmd := &cobra.Command{
		Use:   "helium-browser",
		Short: "Install and configure Helium browser",
	}
	installOptions := helium.InstallOptions{ApplySettings: true}
	install := &cobra.Command{
		Use:   "install <macos|linux> <cache-dir> <bin-dir> <flags>",
		Short: "Install Helium and configure extensions",
		Args:  cobra.ExactArgs(4),
		RunE: func(cmd *cobra.Command, args []string) error {
			installOptions.Mode = args[0]
			installOptions.Root = args[1]
			installOptions.BinDir = args[2]
			installOptions.Flags = args[3]
			return helium.Install(installOptions)
		},
	}
	install.Flags().
		StringArrayVar(&installOptions.Settings, "settings", nil, "Additional extension settings JSON file")
	install.Flags().
		StringVar(&installOptions.SecretsPath, "secrets", "", "SOPS secrets file containing private extension settings")
	install.Flags().
		BoolVar(&installOptions.ApplySettings, "apply-settings", true, "Apply Helium extension settings after install")

	applyOptions := helium.ApplyOptions{}
	applySettings := &cobra.Command{
		Use:     "apply-extension-settings --profile-dir <Default>",
		Aliases: []string{"extset"},
		Short:   "Apply Helium extension settings",
		Args:    cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			if len(applyOptions.SettingsSource) == 0 {
				sources, err := helium.DefaultSettingsSources()
				if err != nil {
					return err
				}
				applyOptions.SettingsSource = sources
			}
			return helium.ApplyExtensionSettings(applyOptions)
		},
	}
	applySettings.Flags().
		StringVar(&applyOptions.ProfileDir, "profile-dir", "", "Helium profile directory")
	applySettings.Flags().
		StringArrayVar(&applyOptions.Settings, "settings", nil, "Extension settings JSON file")
	applySettings.Flags().
		BoolVar(&applyOptions.GitHubToken, "gh-token", false, "Ask gh for an auth token and store it for Refined GitHub")
	_ = applySettings.MarkFlagRequired("profile-dir")
	cmd.AddCommand(install, applySettings)

	if err := cli.Execute(context.Background(), cmd, os.Args[1:], version); err != nil {
		os.Exit(1)
	}
}
