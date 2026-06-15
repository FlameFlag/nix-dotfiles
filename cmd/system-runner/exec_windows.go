//go:build windows

package main

import (
	"errors"
	"os"
	"os/exec"
)

func execProgram(program string, args, env []string) error {
	cmd := exec.Command(program, args[1:]...)
	cmd.Env = env
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err := cmd.Run()
	if exitErr, ok := errors.AsType[*exec.ExitError](err); ok {
		os.Exit(exitErr.ExitCode())
	}
	return err
}
