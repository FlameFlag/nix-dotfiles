package hyperwindow

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/charmbracelet/log"
	"github.com/euvlok/nix-dotfiles/internal/common/process"
	"github.com/euvlok/nix-dotfiles/internal/common/userdirs"
)

const (
	gnomeAttr          = "hyper-window-tiling-gnome"
	kdeAttr            = "hyper-window-tiling-kde"
	gnomeExtensionUUID = "hyper-window-tiling@flame.local"
	gnomeSchema        = "org.gnome.shell.extensions.hyper-window-tiling"
	kdePluginID        = "hyper-window-tiling"
	osReleasePath      = "/etc/os-release"
	osReleaseID        = "ID"
	osReleaseIDLike    = "ID_LIKE"
	nixosID            = "nixos"

	gnomeDesktopEnv      = "gnome"
	gnomeShellProgram    = "gnome-shell"
	gnomeShellSystemDir  = "/usr/share/gnome-shell"
	gnomeWaylandSession  = "/usr/share/wayland-sessions/gnome.desktop"
	kdeDesktopEnv        = "kde"
	plasmaDesktopEnv     = "plasma"
	kwinProgram          = "kwin_wayland"
	plasmaProgram        = "plasmashell"
	plasmaSystemDir      = "/usr/share/plasma"
	plasmaWaylandSession = "/usr/share/wayland-sessions/plasma.desktop"
)

type Config struct {
	HomeDir   string
	SourceDir string
}

func Install(config Config) error {
	if isNixOS() {
		log.Info("NixOS host detected; hyper window tiling is managed by NixOS modules")
		return nil
	}
	if _, ok := process.PathOf("nix"); !ok {
		log.Warn("nix is not available; skipping hyper window tiling install")
		return nil
	}
	repoDir, err := flakeRepoDir(config.SourceDir)
	if err != nil {
		return err
	}
	stateDir := filepath.Join(
		userdirs.StateHome(config.HomeDir),
		"nix-dotfiles/hyper-window-tiling",
	)
	dataDir := userdirs.DataHome(config.HomeDir)
	installed := false
	gnomeInstalled := desktopEnvContains(gnomeDesktopEnv) ||
		commandExists(gnomeShellProgram) ||
		directoryExists(gnomeShellSystemDir) ||
		fileExists(gnomeWaylandSession)
	if gnomeInstalled {
		packagePath, err := buildPackage(repoDir, stateDir, gnomeAttr)
		if err != nil {
			return err
		}
		source := filepath.Join(packagePath, "share/gnome-shell/extensions", gnomeExtensionUUID)
		destination := filepath.Join(dataDir, "gnome-shell/extensions", gnomeExtensionUUID)
		if err := replaceWithSymlink(source, destination); err != nil {
			return err
		}
		schemaDir := filepath.Join(destination, "schemas")
		setGnomeKey(schemaDir, "move-up", "['<Super><Control><Alt><Shift>w']")
		setGnomeKey(schemaDir, "move-left", "['<Super><Control><Alt><Shift>a']")
		setGnomeKey(schemaDir, "move-down", "['<Super><Control><Alt><Shift>s']")
		setGnomeKey(schemaDir, "move-right", "['<Super><Control><Alt><Shift>d']")
		setGnomeKey(schemaDir, "move-max-almost", "['<Super><Control><Alt><Shift>Return']")
		setGnomeKey(schemaDir, "move-max", "['<Super><Control><Alt><Shift>backslash']")
		runOptional([]string{"gnome-extensions", "enable", gnomeExtensionUUID})
		log.Info("GNOME hyper window tiling extension installed")
		installed = true
	}
	plasmaInstalled := desktopEnvContains(kdeDesktopEnv) ||
		desktopEnvContains(plasmaDesktopEnv) ||
		commandExists(kwinProgram) ||
		commandExists(plasmaProgram) ||
		directoryExists(plasmaSystemDir) ||
		fileExists(plasmaWaylandSession)
	if plasmaInstalled {
		packagePath, err := buildPackage(repoDir, stateDir, kdeAttr)
		if err != nil {
			return err
		}
		source := filepath.Join(packagePath, "share/kwin-wayland/scripts", kdePluginID)
		kpackage, ok := process.PathOf("kpackagetool6")
		if !ok {
			kpackage, ok = process.PathOf("kpackagetool5")
		}
		installedWithKPackage := false
		if ok {
			upgrade, err := process.CaptureWithEnvAndStdin(
				[]string{kpackage, "--type", "KWin/Script", "--upgrade", source},
				nil,
				nil,
			)
			if err == nil && upgrade.Success {
				installedWithKPackage = true
			} else {
				install, err := process.CaptureWithEnvAndStdin(
					[]string{kpackage, "--type", "KWin/Script", "--install", source},
					nil,
					nil,
				)
				installedWithKPackage = err == nil && install.Success
			}
		}
		if !installedWithKPackage {
			if err := replaceWithSymlink(
				source,
				filepath.Join(dataDir, "kwin/scripts", kdePluginID),
			); err != nil {
				return err
			}
			if err := replaceWithSymlink(
				source,
				filepath.Join(dataDir, "kwin-wayland/scripts", kdePluginID),
			); err != nil {
				return err
			}
		}
		runFirstAvailable(
			[]string{"kwriteconfig6", "kwriteconfig5"},
			[]string{
				"--file",
				"kwinrc",
				"--group",
				"Plugins",
				"--key",
				"hyper-window-tilingEnabled",
				"true",
			},
		)
		runFirstAvailable(
			[]string{"qdbus6", "qdbus"},
			[]string{"org.kde.KWin", "/KWin", "reconfigure"},
		)
		log.Info("KDE hyper window tiling script installed")
		installed = true
	}
	if !installed {
		log.Info(
			"neither GNOME nor KDE Plasma appears to be installed; skipping hyper window tiling",
		)
	}
	return nil
}

func buildPackage(repoDir, stateDir, attr string) (string, error) {
	if err := os.MkdirAll(stateDir, 0o755); err != nil {
		return "", err
	}
	outLink := filepath.Join(stateDir, attr)
	if err := process.RunInWithEnvAndStdin(
		"",
		[]string{
			"nix",
			"--extra-experimental-features",
			"nix-command flakes",
			"build",
			"--out-link",
			outLink,
			fmt.Sprintf("%s#%s", repoDir, attr),
		},
		nil,
		os.Stdin,
	); err != nil {
		return "", err
	}
	return filepath.EvalSymlinks(outLink)
}

func setGnomeKey(schemaDir, key, value string) {
	if _, ok := process.PathOf("gsettings"); !ok {
		return
	}
	err := process.RunInWithEnvAndStdin(
		"",
		[]string{"gsettings", "set", gnomeSchema, key, value},
		[]string{"GSETTINGS_SCHEMA_DIR=" + schemaDir},
		os.Stdin,
	)
	if err != nil && os.Getenv("DBUS_SESSION_BUS_ADDRESS") != "" {
		log.Warn("failed to set GNOME hyper window tiling key", "key", key)
	}
}

func runFirstAvailable(programs, arguments []string) {
	for _, program := range programs {
		path, ok := process.PathOf(program)
		if !ok {
			continue
		}
		runOptional(slices.Concat([]string{path}, arguments))
		return
	}
}

func runOptional(argv []string) {
	if len(argv) == 0 {
		return
	}
	if _, ok := process.PathOf(argv[0]); ok {
		_, _ = process.CaptureWithEnvAndStdin(argv, nil, nil)
	}
}

func replaceWithSymlink(source, destination string) error {
	info, err := os.Stat(source)
	if err != nil || !info.IsDir() {
		return fmt.Errorf("missing package directory %s", source)
	}
	if err := os.MkdirAll(filepath.Dir(destination), 0o755); err != nil {
		return err
	}
	if info, err := os.Lstat(destination); err == nil {
		if info.IsDir() && info.Mode()&os.ModeSymlink == 0 {
			if err := os.RemoveAll(destination); err != nil {
				return err
			}
		} else if err := os.Remove(destination); err != nil {
			return err
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return os.Symlink(source, destination)
}

func flakeRepoDir(sourceDir string) (string, error) {
	for dir := sourceDir; ; dir = filepath.Dir(dir) {
		flakeInfo, flakeErr := os.Stat(filepath.Join(dir, "flake.nix"))
		packageInfo, packageErr := os.Stat(filepath.Join(dir, "packages/hyper-window-tiling.nix"))
		if flakeErr == nil && !flakeInfo.IsDir() && packageErr == nil && !packageInfo.IsDir() {
			return dir, nil
		}
		next := filepath.Dir(dir)
		if next == dir {
			break
		}
	}
	return "", fmt.Errorf("could not find flake root from %s", sourceDir)
}

func isNixOS() bool {
	data, err := os.ReadFile(osReleasePath)
	if err != nil {
		return false
	}
	for line := range strings.SplitSeq(string(data), "\n") {
		name, value, ok := strings.Cut(line, "=")
		relevantKey := name == osReleaseID || name == osReleaseIDLike
		if !ok || !relevantKey {
			continue
		}
		for item := range strings.FieldsSeq(strings.Trim(value, `"`)) {
			if item == nixosID {
				return true
			}
		}
	}
	return false
}

func commandExists(name string) bool {
	_, ok := process.PathOf(name)
	return ok
}

func directoryExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

func desktopEnvContains(needle string) bool {
	for _, name := range []string{"XDG_CURRENT_DESKTOP", "DESKTOP_SESSION", "GDMSESSION"} {
		value := strings.ToLower(os.Getenv(name))
		for part := range strings.FieldsFuncSeq(value, func(r rune) bool { return r == ':' || r == ';' }) {
			if strings.Contains(part, needle) {
				return true
			}
		}
	}
	return false
}
