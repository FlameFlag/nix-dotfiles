package chezmoi

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/log"
	"github.com/euvlok/nix-dotfiles/internal/common/fileutil"
	"github.com/euvlok/nix-dotfiles/internal/common/process"
)

func writeCommandTextIfAvailable(bin, path string, argv []string) error {
	if _, ok := process.PathOf(bin); !ok {
		return nil
	}
	text, err := commandText(argv)
	if err != nil {
		return err
	}
	_, err = fileutil.WriteTextIfChanged(path, text)
	return err
}

func commandText(argv []string) (string, error) {
	output, err := process.CaptureWithEnvAndStdin(argv, nil, nil)
	if err != nil {
		return "", err
	}
	if !output.Success {
		label := "<empty>"
		if len(argv) > 0 {
			label = argv[0]
		}
		return "", fmt.Errorf("command failed: %s", label)
	}
	return string(output.Stdout), nil
}

func warnIfFailed(name string, output process.Output) {
	if output.Success {
		return
	}
	message := strings.TrimSpace(string(output.Stderr))
	if message == "" {
		message = strings.TrimSpace(string(output.Stdout))
	}
	if message == "" {
		log.Warn("failed to generate completions", "name", name)
	} else {
		log.Warn("failed to generate completions", "name", name, "message", message)
	}
}
