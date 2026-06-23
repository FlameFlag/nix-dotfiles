package systemrun

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"strconv"
	"sync"
	"time"

	"github.com/FlameFlag/nix-dotfiles/internal/systemrun/processctl"
)

const (
	outputLimit = 1024 * 1024
)

type CommandOutput struct {
	ExitStatus      string `json:"exit_status"`
	Success         bool   `json:"success"`
	TimedOut        bool   `json:"timed_out"`
	Stdout          string `json:"stdout"`
	Stderr          string `json:"stderr"`
	StdoutTruncated bool   `json:"stdout_truncated"`
	StderrTruncated bool   `json:"stderr_truncated"`
}

type capturedOutput struct {
	bytes     []byte
	truncated bool
	err       error
}

func RunWithTimeout(cmd *exec.Cmd, commandTimeout time.Duration) (CommandOutput, error) {
	processctl.SetGroup(cmd)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return CommandOutput{}, err
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return CommandOutput{}, err
	}
	if err := cmd.Start(); err != nil {
		return CommandOutput{}, err
	}

	var wg sync.WaitGroup
	wg.Add(2)
	stdoutCh := make(chan capturedOutput, 1)
	stderrCh := make(chan capturedOutput, 1)
	go func() {
		defer wg.Done()
		stdoutCh <- readLimited(stdout)
	}()
	go func() {
		defer wg.Done()
		stderrCh <- readLimited(stderr)
	}()

	waitCh := make(chan error, 1)
	go func() { waitCh <- cmd.Wait() }()

	var waitErr error
	timedOut := false
	timer := time.NewTimer(commandTimeout)
	defer timer.Stop()
	select {
	case waitErr = <-waitCh:
	case <-timer.C:
		timedOut = true
		processctl.Terminate(cmd)
		waitErr = <-waitCh
	}
	wg.Wait()
	stdoutResult := <-stdoutCh
	stderrResult := <-stderrCh
	if stdoutResult.err != nil {
		return CommandOutput{}, stdoutResult.err
	}
	if stderrResult.err != nil {
		return CommandOutput{}, stderrResult.err
	}

	exitStatus := "0"
	success := true
	if waitErr != nil {
		success = false
		if exitErr, ok := errors.AsType[*exec.ExitError](waitErr); ok {
			exitStatus = strconv.Itoa(exitErr.ExitCode())
			if text := processctl.StatusText(exitErr); text != "" {
				exitStatus = text
			}
		} else {
			exitStatus = waitErr.Error()
		}
	}
	if timedOut {
		exitStatus = fmt.Sprintf("timed out after %d seconds", int(commandTimeout.Seconds()))
		success = false
	}
	return CommandOutput{
		ExitStatus:      exitStatus,
		Success:         success,
		TimedOut:        timedOut,
		Stdout:          string(stdoutResult.bytes),
		Stderr:          string(stderrResult.bytes),
		StdoutTruncated: stdoutResult.truncated,
		StderrTruncated: stderrResult.truncated,
	}, nil
}

func RunWithContext(
	ctx context.Context,
	cmd *exec.Cmd,
	commandTimeout time.Duration,
) (CommandOutput, error) {
	done := make(chan struct{})
	var output CommandOutput
	var err error
	go func() {
		output, err = RunWithTimeout(cmd, commandTimeout)
		close(done)
	}()
	select {
	case <-done:
		return output, err
	case <-ctx.Done():
		processctl.Terminate(cmd)
		<-done
		output.ExitStatus = "cancelled"
		output.Success = false
		output.TimedOut = false
		return output, err
	}
}

func readLimited(reader io.Reader) capturedOutput {
	data, err := io.ReadAll(io.LimitReader(reader, outputLimit+1))
	truncated := len(data) > outputLimit
	if truncated {
		data = data[:outputLimit]
	}
	return capturedOutput{bytes: data, truncated: truncated, err: err}
}
