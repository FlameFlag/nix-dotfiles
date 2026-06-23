package config

import (
	"errors"
	"io"
	"os"
	"runtime"
	"strings"

	"github.com/FlameFlag/nix-dotfiles/internal/common/envx"
	"github.com/FlameFlag/nix-dotfiles/internal/common/process"
	activationruntime "github.com/FlameFlag/nix-dotfiles/internal/immutableactivate/runtime"
)

type Options struct {
	Flake             string
	Backend           string
	ResetContainers   bool
	Update            bool
	HostUpdate        bool
	HostUpdater       string
	SkipAnsible       bool
	RuntimePath       string
	DistroboxManifest string

	HomeDir          string
	WorkDir          string
	DataHome         string
	BinHome          string
	OperatingSystem  string
	OSReleasePath    string
	OstreeBootedPath string

	Stdout   io.Writer
	Stderr   io.Writer
	Executor activationruntime.Executor

	CommandExists func(string) bool
}

type environment struct {
	Home string `env:"HOME"`
}

func Normalize(options Options) (Options, error) {
	environment, err := envx.Parse[environment]()
	if err != nil {
		return Options{}, err
	}
	if options.Backend == "" {
		options.Backend = "auto"
	}
	if options.HostUpdater == "" {
		options.HostUpdater = "auto"
	}
	if options.Stdout == nil {
		options.Stdout = os.Stdout
	}
	if options.Stderr == nil {
		options.Stderr = os.Stderr
	}
	if options.Executor == nil {
		options.Executor = activationruntime.ProcessExecutor{}
	}
	if options.CommandExists == nil {
		options.CommandExists = func(name string) bool {
			_, ok := process.PathOf(name)
			return ok
		}
	}
	if options.HomeDir == "" {
		options.HomeDir = environment.Home
	}
	if options.HomeDir == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return Options{}, errors.New("HOME must be set")
		}
		options.HomeDir = home
	}
	if options.WorkDir == "" {
		wd, err := os.Getwd()
		if err != nil {
			return Options{}, err
		}
		options.WorkDir = wd
	}
	if options.OperatingSystem == "" {
		options.OperatingSystem = runtime.GOOS
	}
	if options.OSReleasePath == "" {
		options.OSReleasePath = "/etc/os-release"
	}
	if options.OstreeBootedPath == "" {
		options.OstreeBootedPath = "/run/ostree-booted"
	}
	return options, nil
}

func FirstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}
