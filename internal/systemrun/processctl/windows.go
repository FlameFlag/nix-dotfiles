//go:build windows

package processctl

import "os/exec"

func SetGroup(cmd *exec.Cmd) {}

func Terminate(cmd *exec.Cmd) {
	if cmd != nil && cmd.Process != nil {
		_ = cmd.Process.Kill()
	}
}

func StatusText(exitErr *exec.ExitError) string {
	return ""
}
