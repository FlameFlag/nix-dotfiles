package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"

	"github.com/euvlok/nix-dotfiles/internal/common/cli"
	"github.com/euvlok/nix-dotfiles/internal/lspfilter"
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
	invokedAs := os.Args[0]
	cmd := &cobra.Command{
		Use:   "lsp-diagnostic-filter [flags] LANGUAGE_SERVER [ARG...]",
		Short: "Proxy an stdio LSP server while filtering template diagnostics",
		Example: `lsp-diagnostic-filter nil
lsp-diagnostic-filter yaml-language-server --stdio
lsp-diagnostic-filter -- bash-language-server start
lsp-diagnostic-filter --lsp
lsp-diagnostic-filter nu --lsp`,
		DisableFlagParsing: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			if len(args) > 0 {
				name := filepath.Base(invokedAs)
				if name != "nushell-lsp-filter" {
					name = "lsp-diagnostic-filter"
				}
				if handler, ok := directFlagHandlers[args[0]]; ok {
					return handler(cmd, name)
				}
			}
			if shouldRunNushell(invokedAs, args) {
				var err error
				code, err = runNushell(args)
				return err
			}
			if len(args) > 0 && (args[0] == "nu" || args[0] == "nushell") {
				var err error
				code, err = runNushell(args[1:])
				return err
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

func shouldRunNushell(invokedAs string, args []string) bool {
	if filepath.Base(invokedAs) == "nushell-lsp-filter" {
		return true
	}
	return len(args) > 0 && args[0] != "--" && strings.HasPrefix(args[0], "-")
}

func runNushell(args []string) (int, error) {
	realNu := os.Getenv("NU_LSP_REAL_NU")
	if realNu == "" {
		realNu = "nu"
	}
	if !slices.Contains(args, "--lsp") {
		cmd := exec.Command(realNu, args...)
		cmd.Stdin = os.Stdin
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		err := cmd.Run()
		if err == nil {
			return 0, nil
		}
		if exitErr, ok := errors.AsType[*exec.ExitError](err); ok {
			return exitErr.ExitCode(), nil
		}
		return 1, err
	}
	return lspfilter.ProxyLSPCommand(realNu, args)
}
