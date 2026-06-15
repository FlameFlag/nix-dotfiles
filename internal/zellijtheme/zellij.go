package zellijtheme

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"time"
)

func RunZellij(extraArgs []string) (int, error) {
	uid := os.Getenv("UID")
	digits := uid != ""
	for _, ch := range uid {
		if ch < '0' || ch > '9' {
			digits = false
			break
		}
	}
	if !digits {
		output, err := exec.Command("id", "-u").Output()
		if err == nil {
			uid = strings.TrimSpace(string(output))
		}
		if uid == "" {
			uid = "0"
		}
	}
	socketDir := filepath.Join(os.TempDir(), "zellij-"+uid)
	if err := os.MkdirAll(socketDir, 0o755); err != nil {
		return 1, err
	}
	var args []string
	runner, ok, err := configuredRunner("zellij")
	if err == nil && ok {
		args = slices.Clone(runner.DefaultArgs)
	} else {
		args = []string{
			"options",
			"--default-layout",
			"compact",
			"--attach-to-session",
			"false",
			"--mirror-session",
			"false",
			"--on-force-close",
			"quit",
		}
	}
	args = append(args, extraArgs...)
	return RunInheritEnv("zellij", args, append(os.Environ(), "ZELLIJ_SOCKET_DIR="+socketDir))
}

type StartupPaneColor struct {
	enabled bool
}

func StartStartupPaneColor() StartupPaneColor {
	_, err := exec.LookPath("zellij")
	enabled := os.Getenv("ZELLIJ") != "" && err == nil
	if enabled {
		theme := DetectSystemTheme()
		stdoutLock.Lock()
		info, err := os.Stdout.Stat()
		if err == nil && info.Mode()&os.ModeCharDevice != 0 {
			fmt.Fprintf(
				os.Stdout,
				"\x1b]10;%s\x1b\\\x1b]11;%s\x1b\\",
				theme.Colors.FG,
				theme.Colors.BG,
			)
			_ = os.Stdout.Sync()
		}
		stdoutLock.Unlock()

		paneID := os.Getenv("ZELLIJ_PANE_ID")
		go func() {
			if paneID != "" {
				for range 3 {
					time.Sleep(500 * time.Millisecond)
					RunSilent("zellij", "action", "write", "--pane-id", paneID, "27", "91", "73")
				}
				time.Sleep(1500 * time.Millisecond)
			} else {
				time.Sleep(3 * time.Second)
			}
			RunSilent("zellij", "action", "set-pane-color", "--reset")
		}()
	}
	return StartupPaneColor{enabled: enabled}
}

func (s StartupPaneColor) Close() {
	if s.enabled {
		RunSilent("zellij", "action", "set-pane-color", "--reset")
	}
}

var stdoutLock sync.Mutex
