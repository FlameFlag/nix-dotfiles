package runtime

import (
	"io"
	"os"
	"strings"

	"github.com/FlameFlag/nix-dotfiles/internal/common/process"
)

type Executor interface {
	Run(Command) error
}

type Command struct {
	Argv  []string
	Cwd   string
	Env   []string
	Stdin string
}

type ProcessExecutor struct{}

func (ProcessExecutor) Run(command Command) error {
	var stdin io.Reader = os.Stdin
	if command.Stdin != "" {
		stdin = strings.NewReader(command.Stdin)
	}
	return process.RunInWithEnvAndStdin(command.Cwd, command.Argv, command.Env, stdin)
}
