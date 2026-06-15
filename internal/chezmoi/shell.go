package chezmoi

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/euvlok/nix-dotfiles/internal/common/fileutil"
	"github.com/euvlok/nix-dotfiles/internal/common/process"
	"github.com/euvlok/nix-dotfiles/internal/common/userdirs"
)

type completionSpec struct {
	bin    string
	name   string
	argv0  string
	before []string
	after  []string
}

var completionSpecs = []completionSpec{
	{bin: "scaffold", name: "scaffold", argv0: "scaffold", before: []string{"completions"}},
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

func NushellInit() error {
	home, err := shellHomeDir()
	if err != nil {
		return err
	}
	cacheHome := userdirs.CacheHome(home)
	dataHome := userdirs.DataHome(home)
	for _, dir := range []string{
		filepath.Join(cacheHome, "starship"),
		filepath.Join(cacheHome, "zoxide"),
		filepath.Join(dataHome, "atuin"),
	} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	if err := writeCommandTextIfAvailable(
		"starship",
		filepath.Join(cacheHome, "starship/init.nu"),
		[]string{"starship", "init", "nu"},
	); err != nil {
		return err
	}
	if err := writeCommandTextIfAvailable(
		"zoxide",
		filepath.Join(cacheHome, "zoxide/init.nu"),
		[]string{"zoxide", "init", "nushell", "--cmd", "z"},
	); err != nil {
		return err
	}
	atuin := filepath.Join(dataHome, "atuin/init.nu")
	if err := writeCommandTextIfAvailable(
		"atuin",
		atuin,
		[]string{"atuin", "init", "nu", "--disable-up-arrow"},
	); err != nil {
		return err
	}
	if current, err := os.ReadFile(atuin); err == nil {
		_, err := fileutil.WriteTextIfChanged(
			atuin,
			strings.ReplaceAll(string(current), "$cmd e>| complete", "$cmd | complete"),
		)
		if err != nil {
			return err
		}
	}
	return nil
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
	if value := os.Getenv("CHEZMOI_HOME_DIR"); value != "" {
		return value, nil
	}
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return "", fmt.Errorf("environment variable HOME is required")
	}
	return home, nil
}
