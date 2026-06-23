package schedule

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"time"

	"github.com/FlameFlag/nix-dotfiles/internal/common/envx"
	"github.com/FlameFlag/nix-dotfiles/internal/ndtools/config"
)

type Options struct {
	Stdout io.Writer
	Stderr io.Writer
}

type environment struct {
	Exe       string `env:"ND_TOOLS_EXE"`
	LegacyExe string `env:"NIX_DOTFILES_TOOL_UPDATE_EXE"`
}

func Install(ctx context.Context, options Options) error {
	options = normalizeOptions(options)
	toolConfig, err := config.Load()
	if err != nil {
		return err
	}
	if runtime.GOOS != "windows" {
		return fmt.Errorf("task scheduler installation is only supported on Windows")
	}

	updater, err := findUpdaterExecutable()
	if err != nil {
		return err
	}
	schtasks, err := exec.LookPath("schtasks.exe")
	if err != nil {
		return fmt.Errorf("schtasks.exe is required to install the scheduled updater: %w", err)
	}

	cmd := exec.CommandContext(
		ctx, schtasks,
		"/Create",
		"/TN", toolConfig.Schedule.Name,
		"/SC", "HOURLY",
		"/MO", strconv.Itoa(toolConfig.Schedule.IntervalHours),
		"/ST", startTime(toolConfig.Schedule.StartDelayMinutes),
		"/TR", quoteWindowsCommand(updater)+" update",
		"/F",
	)
	cmd.Stdout = options.Stdout
	cmd.Stderr = options.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("install scheduled updater: %w", err)
	}
	return nil
}

func startTime(delayMinutes int) string {
	return time.Now().Add(time.Duration(delayMinutes) * time.Minute).Format("15:04")
}

func findUpdaterExecutable() (string, error) {
	environment := envx.MustParse[environment]()
	for _, value := range []string{environment.Exe, environment.LegacyExe} {
		if value == "" {
			continue
		}
		if pathExists(value) {
			return value, nil
		}
		return "", fmt.Errorf("updater executable not found: %s", value)
	}

	home, _ := os.UserHomeDir()
	for _, path := range []string{
		filepath.Join(home, ".local", "bin", "nd-tools.exe"),
		filepath.Join(home, ".local", "bin", "nd-tools"),
	} {
		if pathExists(path) {
			return path, nil
		}
	}
	return "", fmt.Errorf(
		"updater executable not found: %s",
		filepath.Join(home, ".local", "bin", "nd-tools.exe"),
	)
}

func normalizeOptions(options Options) Options {
	if options.Stdout == nil {
		options.Stdout = os.Stdout
	}
	if options.Stderr == nil {
		options.Stderr = os.Stderr
	}
	return options
}

func pathExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func quoteWindowsCommand(path string) string {
	return `"` + path + `"`
}
