package zellijtheme

import (
	"math"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
)

type Colors struct {
	FG string
	BG string
}

type Theme struct {
	Name   string
	Colors Colors
}

type TerminalThemeMode int

const (
	Dark TerminalThemeMode = iota
	Light
)

var (
	Frappe = Theme{Name: "catppuccin-frappe-pink", Colors: Colors{FG: "#c6d0f5", BG: "#303446"}}
	Latte  = Theme{Name: "catppuccin-latte-pink", Colors: Colors{FG: "#4c4f69", BG: "#eff1f5"}}
)

type themeProbePlan struct {
	fallback Theme
	commands [][]string
}

var unixThemeProbeCommands = [][]string{
	{"gsettings", "get", "org.gnome.desktop.interface", "color-scheme"},
	{"gsettings", "get", "org.gnome.desktop.interface", "gtk-theme"},
}

var systemThemeProbePlans = map[string]themeProbePlan{
	"darwin": {
		fallback: Latte,
		commands: [][]string{
			{"defaults", "read", "-g", "AppleInterfaceStyle"},
		},
	},
	"linux":     {fallback: Frappe, commands: unixThemeProbeCommands},
	"freebsd":   {fallback: Frappe, commands: unixThemeProbeCommands},
	"dragonfly": {fallback: Frappe, commands: unixThemeProbeCommands},
	"netbsd":    {fallback: Frappe, commands: unixThemeProbeCommands},
	"openbsd":   {fallback: Frappe, commands: unixThemeProbeCommands},
}

func DetectSystemTheme() Theme {
	plan, ok := systemThemeProbePlans[runtime.GOOS]
	if !ok {
		return Frappe
	}
	for _, command := range plan.commands {
		output, err := exec.Command(command[0], command[1:]...).Output()
		if err == nil {
			if mode, ok := themeModeFromText(string(output)); ok {
				return themeForMode(mode)
			}
		}
	}
	return plan.fallback
}

func themeForMode(mode TerminalThemeMode) Theme {
	if mode == Light {
		return Latte
	}
	return Frappe
}

func themeModeFromText(text string) (TerminalThemeMode, bool) {
	text = strings.ToLower(strings.TrimSpace(text))
	if strings.Contains(text, "dark") {
		return Dark, true
	}
	if strings.Contains(text, "light") {
		return Light, true
	}
	switch strings.Trim(text, "'\"") {
	case "default", "adwaita":
		return Light, true
	}
	return Dark, false
}

func ParseTerminalThemeReport(buffer []byte) (TerminalThemeMode, bool) {
	text := string(buffer)
	if strings.Contains(text, "\x1b[?997;1n") {
		return Dark, true
	}
	if strings.Contains(text, "\x1b[?997;2n") {
		return Light, true
	}
	rest := text
	for {
		start := strings.Index(rest, "\x1b]11;")
		if start < 0 {
			return Dark, false
		}
		after := rest[start+len("\x1b]11;"):]
		bell := strings.IndexByte(after, '\a')
		st := strings.Index(after, "\x1b\\")
		var end int
		skip := 1
		switch {
		case bell >= 0 && (st < 0 || bell < st):
			end = bell
		case st >= 0:
			end = st
			skip = 2
		default:
			return Dark, false
		}
		value := strings.TrimPrefix(after[:end], "rgb:")
		red, restValue, ok := strings.Cut(value, "/")
		if ok {
			green, blue, ok := strings.Cut(restValue, "/")
			if !ok || strings.Contains(blue, "/") {
				rest = after[end+skip:]
				continue
			}
			r, ok := parseColorComponent(red)
			if !ok {
				rest = after[end+skip:]
				continue
			}
			g, ok := parseColorComponent(green)
			if !ok {
				rest = after[end+skip:]
				continue
			}
			b, ok := parseColorComponent(blue)
			if !ok {
				rest = after[end+skip:]
				continue
			}
			channel := func(value uint8) float64 {
				v := float64(value) / 255
				if v <= 0.04045 {
					return v / 12.92
				}
				return math.Pow((v+0.055)/1.055, 2.4)
			}
			luminance := 0.2126*channel(r) + 0.7152*channel(g) + 0.0722*channel(b)
			if luminance > 0.5 {
				return Light, true
			}
			return Dark, true
		}
		rest = after[end+skip:]
	}
}

func parseColorComponent(value string) (uint8, bool) {
	if value == "" || len(value) > 4 {
		return 0, false
	}
	parsed, err := strconv.ParseUint(value, 16, 16)
	if err != nil {
		return 0, false
	}
	maxValue := uint64(1<<(len(value)*4)) - 1
	return uint8((parsed*255 + maxValue/2) / maxValue), true
}
