//go:build windows

package zellijtheme

import "time"

func detectTerminalTheme(time.Duration) (TerminalThemeMode, bool) {
	return Dark, false
}
