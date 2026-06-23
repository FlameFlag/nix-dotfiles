package systemrun

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/FlameFlag/nix-dotfiles/internal/systemrun/pathprobe"
)

const (
	defaultTimeout = 300 * time.Second
	maxTimeout     = 1800 * time.Second
)

type Params struct {
	Command    string `json:"command"`
	Cwd        string `json:"cwd,omitempty"`
	TimeoutSec uint64 `json:"timeout_sec,omitempty"`
}

func RunSystemCommand(ctx context.Context, params Params) (CommandOutput, error) {
	if strings.TrimSpace(params.Command) == "" {
		return CommandOutput{}, invalidParams("command must not be empty")
	}
	timeout, err := CommandTimeout(params.TimeoutSec)
	if err != nil {
		return CommandOutput{}, invalidParams(err.Error())
	}
	runner, err := SystemRunnerPath()
	if err != nil {
		return CommandOutput{}, fmt.Errorf(
			"failed to locate sibling command runner binary: %w",
			err,
		)
	}
	args := []string{"-n", runner}
	if path := pathprobe.UserShellPath(); path != "" {
		args = append(args, "--env", "PATH="+path)
	}
	args = append(args, "--", "/bin/sh", "-c", params.Command)
	cmd := exec.Command("sudo", args...)
	cmd.Stdin = nil
	if strings.TrimSpace(params.Cwd) != "" {
		cmd.Dir = params.Cwd
	}
	return RunWithContext(ctx, cmd, timeout)
}

func CommandTimeout(seconds uint64) (time.Duration, error) {
	if seconds == 0 {
		return defaultTimeout, nil
	}
	timeout := time.Duration(seconds) * time.Second
	if timeout > maxTimeout {
		return 0, fmt.Errorf("timeout_sec must not exceed %d seconds", int(maxTimeout.Seconds()))
	}
	return timeout, nil
}

func SystemRunnerPath() (string, error) {
	exe, err := os.Executable()
	if err != nil {
		return "", err
	}
	return filepath.Join(filepath.Dir(exe), "system-runner"), nil
}

func DecodeParams(raw json.RawMessage) (Params, error) {
	var params Params
	if len(raw) == 0 || bytes.Equal(raw, []byte("null")) {
		return params, nil
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&params); err != nil {
		return Params{}, invalidParams(err.Error())
	}
	return params, nil
}

type invalidParams string

func (e invalidParams) Error() string { return string(e) }
