package immutableactivate

import (
	"fmt"
	"os"

	"github.com/euvlok/nix-dotfiles/internal/immutableactivate/config"
	"github.com/euvlok/nix-dotfiles/internal/immutableactivate/container"
	"github.com/euvlok/nix-dotfiles/internal/immutableactivate/flake"
	"github.com/euvlok/nix-dotfiles/internal/immutableactivate/host"
	activationruntime "github.com/euvlok/nix-dotfiles/internal/immutableactivate/runtime"
	"github.com/euvlok/nix-dotfiles/internal/immutableactivate/updater"
	"github.com/euvlok/nix-dotfiles/internal/immutableactivate/wrappers"
)

const (
	Marker                 = wrappers.Marker
	nixContainerName       = container.Name
	legacyNixContainerName = container.LegacyName
)

type (
	Options         = config.Options
	Executor        = activationruntime.Executor
	Command         = activationruntime.Command
	ProcessExecutor = activationruntime.ProcessExecutor
)

func Run(options Options) error {
	app, err := newApp(options)
	if err != nil {
		return err
	}
	return app.activate()
}

type app struct {
	options Options
}

type backendSpec struct {
	activate func(config.Options, string) error
}

var activationBackends = map[string]backendSpec{
	"host":      {activate: host.Activate},
	"container": {activate: container.Activate},
}

var autoBackendOrder = []struct {
	name     string
	eligible func(Options) bool
}{
	{name: "host", eligible: func(options Options) bool { return options.CommandExists("nix") }},
	{name: "container", eligible: func(Options) bool { return true }},
}

func newApp(options Options) (app, error) {
	normalized, err := config.Normalize(options)
	if err != nil {
		return app{}, err
	}
	return app{options: normalized}, nil
}

func (a app) activate() error {
	if a.options.RuntimePath != "" {
		oldPath, hadPath := os.LookupEnv("PATH")
		if err := os.Setenv(
			"PATH",
			a.options.RuntimePath+string(os.PathListSeparator)+os.Getenv("PATH"),
		); err != nil {
			return err
		}
		defer func() {
			if hadPath {
				_ = os.Setenv("PATH", oldPath)
			} else {
				_ = os.Unsetenv("PATH")
			}
		}()
	}
	if a.options.OperatingSystem != "linux" {
		return fmt.Errorf("this entry point is only for portable Linux hosts")
	}

	flakePath := a.options.Flake
	if flakePath == "" {
		flakePath = flake.Default(a.options.HomeDir, a.options.WorkDir, a.options.OperatingSystem)
	}
	if flakePath == "" {
		fmt.Fprintln(
			a.options.Stderr,
			"immutable-activate: could not find a nix-dotfiles flake checkout",
		)
		fmt.Fprintln(a.options.Stderr, "set NIX_DOTFILES_FLAKE or pass --flake PATH")
		return fmt.Errorf("missing flake checkout")
	}
	normalizedFlake, err := flake.Normalize(flakePath)
	if err != nil {
		return err
	}
	flakePath = normalizedFlake

	if a.options.HostUpdate {
		if err := updater.RunNative(a.options, a.options.HostUpdater); err != nil {
			return err
		}
	}

	backend := a.options.Backend
	if backend == "auto" {
		backend = selectAutoBackend(a.options)
	}
	spec, ok := activationBackends[backend]
	if !ok {
		return fmt.Errorf("unknown backend: %s", backend)
	}
	return spec.activate(a.options, flakePath)
}

func selectAutoBackend(options Options) string {
	for _, candidate := range autoBackendOrder {
		if candidate.eligible(options) {
			return candidate.name
		}
	}
	return "container"
}
