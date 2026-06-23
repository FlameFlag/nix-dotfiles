package container

import (
	_ "embed"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/FlameFlag/nix-dotfiles/internal/common/userdirs"
	"github.com/FlameFlag/nix-dotfiles/internal/immutableactivate/config"
	activationruntime "github.com/FlameFlag/nix-dotfiles/internal/immutableactivate/runtime"
	"github.com/FlameFlag/nix-dotfiles/internal/immutableactivate/wrappers"
)

const (
	Name       = "fedora-nix"
	LegacyName = "arch-nix"
	systemPath = "/usr/local/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
)

//go:embed export-bins.sh
var exportScript string

func Activate(options config.Options, flake string) error {
	if !options.CommandExists("distrobox") {
		return fmt.Errorf("missing required command: distrobox")
	}
	binHome := config.FirstNonEmpty(options.BinHome, userdirs.BinHome(options.HomeDir))
	exportRoot := filepath.Join(
		config.FirstNonEmpty(options.DataHome, userdirs.DataHome(options.HomeDir)),
		"nix-dotfiles/immutable",
	)
	exportDir := filepath.Join(exportRoot, "bin")
	launcherRoot := filepath.Join(exportRoot, "container-launchers")

	for _, dir := range []string{binHome, exportDir, launcherRoot} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	manifest, err := ResolveManifest(options)
	if err != nil {
		return err
	}
	if options.ResetContainers {
		_ = options.Executor.Run(
			activationruntime.Command{
				Argv: []string{"distrobox", "assemble", "rm", "--file", manifest, "--name", Name},
			},
		)
		_ = options.Executor.Run(
			activationruntime.Command{Argv: []string{"distrobox", "rm", "--force", LegacyName}},
		)
	}
	if err := options.Executor.Run(
		activationruntime.Command{
			Argv: []string{"distrobox", "assemble", "create", "--file", manifest, "--name", Name},
		},
	); err != nil {
		return err
	}
	if err := options.Executor.Run(
		activationruntime.Command{
			Argv: []string{
				"distrobox",
				"enter",
				"--name",
				Name,
				"--",
				"env",
				"PATH=" + NixPath(options.HomeDir),
				"nix",
				"--version",
			},
		},
	); err != nil {
		return fmt.Errorf(
			"managed Distrobox container has no working Nix; rerun with --reset-containers",
		)
	}

	nixCommand := func(args ...string) []string {
		command := []string{
			"distrobox",
			"enter",
			"--name",
			Name,
			"--",
			"env",
			"PATH=" + NixPath(options.HomeDir),
			"nix",
			"--extra-experimental-features",
			"nix-command flakes",
		}
		return slices.Concat(command, args)
	}
	if options.Update {
		if err := options.Executor.Run(
			activationruntime.Command{Argv: nixCommand("flake", "update", "--flake", flake)},
		); err != nil {
			return err
		}
	}
	_ = options.Executor.Run(
		activationruntime.Command{Argv: nixCommand("profile", "remove", "immutable-profile")},
	)
	if err := options.Executor.Run(
		activationruntime.Command{
			Argv: nixCommand("profile", "install", "path:"+flake+"#immutable-profile"),
		},
	); err != nil {
		return err
	}

	if err := os.RemoveAll(exportDir); err != nil {
		return err
	}
	if err := os.MkdirAll(exportDir, 0o755); err != nil {
		return err
	}
	launcherDir := filepath.Join(launcherRoot, Name)
	env := []string{
		"NIX_DOTFILES_CONTAINER_PATH=" + strings.Join([]string{
			filepath.Join(options.HomeDir, ".local/bin"),
			filepath.Join(options.HomeDir, ".cache/.bun/bin"),
			filepath.Join(options.HomeDir, ".cargo/bin"),
			filepath.Join(options.HomeDir, ".nix-profile/bin"),
			systemPath,
		}, ":"),
		"NIX_DOTFILES_EXPORT_DIR=" + exportDir,
		"NIX_DOTFILES_LAUNCHER_DIR=" + launcherDir,
	}
	if err := options.Executor.Run(activationruntime.Command{
		Argv: append(
			[]string{"distrobox", "enter", "--name", Name, "--", "env"},
			append(env, "bash", "-s")...,
		),
		Stdin: exportScript,
	}); err != nil {
		return err
	}
	if err := wrappers.RemoveLegacyContainer(binHome); err != nil {
		return err
	}
	if !options.SkipAnsible {
		if err := options.Executor.Run(
			activationruntime.Command{
				Argv: []string{
					"ansible-playbook",
					"-i",
					filepath.Join(flake, "ansible/inventory/localhost.yml"),
					filepath.Join(flake, "ansible/playbooks/userland.yml"),
				},
			},
		); err != nil {
			return err
		}
	}
	fmt.Fprintf(
		options.Stdout,
		"immutable-activate: activated path:%s#immutable-profile through %s\n",
		flake,
		Name,
	)
	fmt.Fprintf(options.Stdout, "immutable-activate: Distrobox exports managed in %s\n", exportDir)
	return nil
}

func ResolveManifest(options config.Options) (string, error) {
	candidates := []string{}
	if options.DistroboxManifest != "" {
		candidates = append(candidates, options.DistroboxManifest)
	}
	if exe, err := os.Executable(); err == nil {
		exeDir := filepath.Dir(exe)
		candidates = append(
			candidates,
			filepath.Join(exeDir, "immutable-distrobox.ini"),
			filepath.Clean(filepath.Join(exeDir, "../share/nix-dotfiles/immutable/distrobox.ini")),
		)
	}
	candidates = append(
		candidates,
		filepath.Join(options.WorkDir, "internal/immutableactivate/container/distrobox.ini"),
		filepath.Join(options.WorkDir, "immutable-distrobox.ini"),
	)
	for _, candidate := range candidates {
		info, err := os.Stat(candidate)
		if err == nil && !info.IsDir() {
			return candidate, nil
		}
	}
	if options.DistroboxManifest != "" {
		return "", fmt.Errorf("missing Distrobox manifest: %s", options.DistroboxManifest)
	}
	return "", fmt.Errorf("missing Distrobox manifest")
}

func NixPath(home string) string {
	return strings.Join([]string{
		filepath.Join(home, ".nix-profile/bin"),
		"/nix/var/nix/profiles/default/bin",
		systemPath,
	}, ":")
}
