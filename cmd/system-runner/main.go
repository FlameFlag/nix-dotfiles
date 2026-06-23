package main

import (
	"context"
	"fmt"
	"io/fs"
	"os"
	"runtime"
	"slices"
	"strings"

	"github.com/FlameFlag/nix-dotfiles/internal/common/cli"
	"github.com/FlameFlag/nix-dotfiles/internal/common/process"
	"github.com/spf13/cobra"
)

const (
	defaultRunnerPath = "/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/sbin:/usr/local/bin:/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/root/bin"
	pathEnvKey        = "PATH"
)

var version = "dev"

func main() {
	var envOverrides []string
	cmd := &cobra.Command{
		Use:   "system-runner [flags] COMMAND [ARG...]",
		Short: "Execute a command with a controlled root PATH",
		Args:  cobra.MinimumNArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			for _, value := range envOverrides {
				key, _, ok := strings.Cut(value, "=")
				if !ok {
					return fmt.Errorf("--env requires KEY=VALUE")
				}
				if key == "" {
					return fmt.Errorf("--env variable name must not be empty")
				}
			}

			pathEnv := defaultRunnerPath
			for index := len(envOverrides) - 1; index >= 0; index-- {
				key, value, ok := strings.Cut(envOverrides[index], "=")
				if ok && key == pathEnvKey {
					pathEnv = value
					break
				}
			}

			program := args[0]
			execArgs := slices.Clone(args[1:])
			if process.IsPathLike(program) {
				info, err := os.Stat(program)
				if err == nil && isNonExecutableUnixFile(info) {
					execArgs = slices.Concat([]string{program}, execArgs)
					program = "/bin/cat"
				}
			} else if path, ok := process.PathOfWithPath(program, pathEnv); ok {
				program = path
			}

			values := map[string]string{}
			var order []string
			for _, item := range slices.Concat(os.Environ(), envOverrides, []string{pathEnvKey + "=" + pathEnv}) {
				key, value, ok := strings.Cut(item, "=")
				if !ok {
					continue
				}
				if _, seen := values[key]; !seen {
					order = append(order, key)
				}
				values[key] = value
			}
			env := make([]string, 0, len(order))
			for _, key := range order {
				env = append(env, key+"="+values[key])
			}
			return execProgram(program, slices.Concat([]string{program}, execArgs), env)
		},
	}
	cmd.Flags().SetInterspersed(false)
	cmd.Flags().StringArrayVar(&envOverrides, "env", nil, "Environment override as KEY=VALUE")
	if err := cli.Execute(context.Background(), cmd, os.Args[1:], version); err != nil {
		os.Exit(2)
	}
}

func isNonExecutableUnixFile(info fs.FileInfo) bool {
	return !info.IsDir() && runtime.GOOS != "windows" && info.Mode()&0o111 == 0
}
