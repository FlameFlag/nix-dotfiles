package runner

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"

	"github.com/euvlok/nix-dotfiles/internal/ndtools/manifest"
	"github.com/euvlok/nix-dotfiles/internal/ndtools/provider"
)

func runManifestTool(ctx context.Context, options Options, providers []provider.Spec, tool manifest.Tool) int {
	if tool.Enabled != nil && !*tool.Enabled {
		logf(options.Stdout, "skipping disabled manifest updater: %s", tool.Name)
		return 0
	}

	if strings.TrimSpace(tool.Name) == "" ||
		strings.TrimSpace(tool.Provider) == "" {
		logf(options.Stdout, "invalid manifest tool entry: name and provider are required")
		return 2
	}

	spec, ok := findProvider(providers, tool.Provider)
	if !ok {
		logf(options.Stdout, "skipping %s: unknown updater provider '%s'", tool.Name, tool.Provider)
		return 2
	}
	argv, err := provider.Render(spec, tool)
	if err != nil {
		logf(options.Stdout, "skipping %s: %v", tool.Name, err)
		return 2
	}
	logf(options.Stdout, "running manifest updater: %s (%s)", tool.Name, tool.Provider)
	return runRequiredCommand(ctx, options, tool.Name, argv[0], argv[1:]...)
}

func findProvider(providers []provider.Spec, name string) (provider.Spec, bool) {
	for _, spec := range providers {
		if spec.Name == name {
			return spec, true
		}
	}
	return provider.Spec{}, false
}

func runRequiredCommand(ctx context.Context, options Options, toolName, program string, args ...string) int {
	path, err := exec.LookPath(program)
	if err != nil {
		logf(options.Stdout, "skipping %s: %s not found", toolName, program)
		return 127
	}
	return runCommand(ctx, options, path, args...)
}

func runCommand(ctx context.Context, options Options, program string, args ...string) int {
	cmd := exec.CommandContext(ctx, program, args...)
	cmd.Stdout = options.Stdout
	cmd.Stderr = options.Stderr
	if err := cmd.Run(); err != nil {
		if exitErr, ok := errors.AsType[*exec.ExitError](err); ok {
			return exitErr.ExitCode()
		}
		fmt.Fprintf(options.Stderr, "%v\n", err)
		return 1
	}
	return 0
}
