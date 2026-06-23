package chezmoi

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"

	"github.com/FlameFlag/nix-dotfiles/internal/common/envx"
	"github.com/FlameFlag/nix-dotfiles/internal/common/fileutil"
	"github.com/FlameFlag/nix-dotfiles/internal/common/process"
	"github.com/FlameFlag/nix-dotfiles/internal/common/userdirs"
)

type completionSpec struct {
	bin    string
	name   string
	argv0  string
	before []string
	after  []string
}

var completionSpecs = []completionSpec{
	{bin: "chezmoi", name: "chezmoi", argv0: "chezmoi", before: []string{"completion"}},
	{bin: "jj", name: "jj", argv0: "jj", before: []string{"util", "completion"}},
	{
		bin:    "zellij",
		name:   "zellij",
		argv0:  "zellij",
		before: []string{"setup", "--generate-completion"},
	},
	{bin: "starship", name: "starship", argv0: "starship", before: []string{"completions"}},
	{bin: "deno", name: "deno", argv0: "deno", before: []string{"completions"}},
	{bin: "delta", name: "delta", argv0: "delta", before: []string{"--generate-completion"}},
	{bin: "tv", name: "tv", argv0: "tv", before: []string{"completions"}},
	{bin: "rustup", name: "rustup", argv0: "rustup", before: []string{"completions"}},
	{
		bin:    "rustup",
		name:   "cargo",
		argv0:  "rustup",
		before: []string{"completions"},
		after:  []string{"cargo"},
	},
}

func ShellInit() error {
	home, err := shellHomeDir()
	if err != nil {
		return err
	}
	cacheHome := userdirs.CacheHome(home)
	for _, dir := range []string{
		filepath.Join(cacheHome, "starship"),
		filepath.Join(cacheHome, "zoxide"),
		filepath.Join(cacheHome, "atuin"),
		filepath.Join(cacheHome, "television"),
		filepath.Join(cacheHome, "zsh/completions"),
		filepath.Join(cacheHome, "bash/completions"),
	} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	for _, shell := range []string{"zsh", "bash"} {
		commands := []struct {
			bin    string
			dir    string
			suffix []string
		}{
			{"starship", "starship", nil},
			{"zoxide", "zoxide", nil},
			{"atuin", "atuin", []string{"--disable-up-arrow"}},
			{"tv", "television", nil},
		}
		for _, command := range commands {
			if _, ok := process.PathOf(command.bin); !ok {
				continue
			}
			args := slices.Concat([]string{command.bin, "init", shell}, command.suffix)
			path := filepath.Join(cacheHome, command.dir, "init."+shell)
			if err := writeCommandTextIfAvailable(command.bin, path, args); err != nil {
				return err
			}
		}

		outdir := filepath.Join(cacheHome, shell, "completions")
		prefix := ""
		if shell == "zsh" {
			prefix = "_"
		}
		if _, ok := process.PathOf("atuin"); ok {
			args := []string{"atuin", "gen-completions", "--shell", shell, "--out-dir", outdir}
			output, err := process.CaptureWithEnvAndStdin(args, nil, nil)
			if err == nil {
				warnIfFailed("atuin completions", output)
			}
		}
		for _, spec := range completionSpecs {
			if _, ok := process.PathOf(spec.bin); !ok {
				continue
			}
			args := slices.Concat([]string{spec.argv0}, spec.before, []string{shell}, spec.after)
			output, err := process.CaptureWithEnvAndStdin(args, nil, nil)
			if err != nil {
				return err
			}
			if !output.Success {
				warnIfFailed(spec.name, output)
				continue
			}
			if _, err := fileutil.WriteTextIfChanged(
				filepath.Join(outdir, prefix+spec.name),
				string(output.Stdout),
			); err != nil {
				return err
			}
		}
	}
	return nil
}

func shellHomeDir() (string, error) {
	environment, err := envx.Parse[environment]()
	if err != nil {
		return "", err
	}
	if environment.HomeDir != "" {
		return environment.HomeDir, nil
	}
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return "", fmt.Errorf("environment variable HOME is required")
	}
	return home, nil
}
