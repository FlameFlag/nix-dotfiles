package main

import (
	"context"
	"fmt"
	"os"

	"github.com/FlameFlag/nix-dotfiles/internal/common/cli"
	"github.com/FlameFlag/nix-dotfiles/internal/lspfilter"
	"github.com/spf13/cobra"
)

var version = "dev"

var directFlagHandlers = map[string]func(*cobra.Command, string) error{
	"--version": printVersion,
	"-V":        printVersion,
	"--help":    printHelp,
	"-h":        printHelp,
}

func main() {
	code := 0
	cmd := &cobra.Command{
		Use:   "lsp-diagnostic-filter [flags] LANGUAGE_SERVER [ARG...]",
		Short: "Proxy an stdio LSP server while filtering template diagnostics",
		Example: `lsp-diagnostic-filter nil
lsp-diagnostic-filter yaml-language-server --stdio
lsp-diagnostic-filter -- bash-language-server start`,
		DisableFlagParsing: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			if len(args) > 0 {
				if handler, ok := directFlagHandlers[args[0]]; ok {
					return handler(cmd, "lsp-diagnostic-filter")
				}
			}
			commandStart := 0
			if len(args) > 0 && args[0] == "--" {
				commandStart = 1
			}
			if len(args) <= commandStart {
				return cmd.Help()
			}
			var err error
			code, err = lspfilter.ProxyLSPCommand(args[commandStart], args[commandStart+1:])
			return err
		},
	}
	if err := cli.Execute(context.Background(), cmd, os.Args[1:], version); err != nil {
		os.Exit(1)
	}
	os.Exit(code)
}

func printVersion(_ *cobra.Command, name string) error {
	fmt.Printf("%s %s\n", name, version)
	return nil
}

func printHelp(cmd *cobra.Command, _ string) error {
	_ = cmd.Help()
	return nil
}
