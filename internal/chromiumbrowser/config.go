package chromiumbrowser

import (
	"fmt"
	"path/filepath"
	"strings"

	"github.com/FlameFlag/nix-dotfiles/internal/common/userdirs"
	"github.com/pelletier/go-toml/v2"
)

type Config struct {
	Name           string                   `toml:"name"`
	LogPrefix      string                   `toml:"log_prefix"`
	ExecutableName string                   `toml:"executable_name"`
	AliasName      string                   `toml:"alias_name"`
	Linux          LinuxConfig              `toml:"linux"`
	MacOS          MacOSConfig              `toml:"macos"`
	Paths          map[string]ModePaths     `toml:"paths"`
	Preferences    PreferenceDefaultsConfig `toml:"preferences"`
	ExtensionIDs   ExtensionIDs             `toml:"extensions"`
}

type LinuxConfig struct {
	DesktopID    string   `toml:"desktop_id"`
	WrapperFlags []string `toml:"wrapper_flags"`
	LauncherName string   `toml:"launcher_name"`
	DesktopName  string   `toml:"desktop_name"`
	DesktopExec  string   `toml:"desktop_exec"`
	IconName     string   `toml:"icon_name"`
	IconSource   string   `toml:"icon_source"`
}

type MacOSConfig struct {
	AppDir       string `toml:"app_dir"`
	LauncherPath string `toml:"launcher_path"`
}

type ModePaths struct {
	ProfileDir            string   `toml:"profile_dir"`
	ExternalExtensionDirs []string `toml:"external_extension_dirs"`
}

type PreferenceDefaultsConfig struct {
	Values       []PreferenceValueConfig       `toml:"values"`
	Accelerators []PreferenceAcceleratorConfig `toml:"accelerators"`
}

type PreferenceValueConfig struct {
	Path  string `toml:"path"`
	Value any    `toml:"value"`
}

type PreferenceAcceleratorConfig struct {
	Path        string `toml:"path"`
	CommandID   string `toml:"command_id"`
	Accelerator string `toml:"accelerator"`
}

func LoadConfig(data []byte, name string) (Config, error) {
	var config Config
	if err := toml.Unmarshal(data, &config); err != nil {
		return Config{}, fmt.Errorf("parse %s Chromium browser config: %w", name, err)
	}
	if err := config.validate(name); err != nil {
		return Config{}, err
	}
	return config, nil
}

func (config Config) Browser() Browser {
	browser := Browser{
		Name:              config.Name,
		LogPrefix:         config.LogPrefix,
		ExecutableName:    config.ExecutableName,
		AliasName:         config.AliasName,
		LinuxDesktopID:    config.Linux.DesktopID,
		LinuxWrapperFlags: slicesClone(config.Linux.WrapperFlags),
		LinuxLauncherName: config.Linux.LauncherName,
		LinuxDesktopName:  config.Linux.DesktopName,
		LinuxDesktopExec:  config.Linux.DesktopExec,
		LinuxIconName:     config.Linux.IconName,
		LinuxIconSource:   config.Linux.IconSource,
		MacOSAppDir:       expandPathTemplate(config.MacOS.AppDir),
		MacOSLauncherPath: filepath.FromSlash(config.MacOS.LauncherPath),
		ExternalDirs:      config.ExternalExtensionDirs,
		DefaultProfileDir: config.DefaultProfileDir,
		ExtensionIDs:      config.ExtensionIDs,
	}
	if config.Preferences.HasDefaults() {
		browser.PreferencePatches = []PreferencePatch{config.Preferences.Patch}
	}
	return browser
}

func (config Config) DefaultProfileDir(mode string) string {
	return expandPathTemplate(config.Paths[mode].ProfileDir)
}

func (config Config) ExternalExtensionDirs(mode string) []string {
	paths := config.Paths[mode].ExternalExtensionDirs
	if len(paths) == 0 {
		return nil
	}
	resolved := make([]string, 0, len(paths))
	for _, path := range paths {
		resolved = append(resolved, expandPathTemplate(path))
	}
	return resolved
}

func (config PreferenceDefaultsConfig) HasDefaults() bool {
	return len(config.Values) > 0 || len(config.Accelerators) > 0
}

func (config PreferenceDefaultsConfig) Patch(preferences map[string]any) {
	for _, value := range config.Values {
		SetNestedValue(preferences, value.Path, value.Value)
	}
	for _, accelerator := range config.Accelerators {
		customAccelerators := NestedObject(preferences, accelerator.Path)
		EnsureAcceleratorAdded(customAccelerators, accelerator.CommandID, accelerator.Accelerator)
	}
}

func (config Config) validate(name string) error {
	if config.ExecutableName == "" {
		return fmt.Errorf("%s Chromium browser config is missing executable_name", name)
	}
	for _, flag := range config.Linux.WrapperFlags {
		if flag == "" {
			return fmt.Errorf("%s Chromium browser config contains an empty linux.wrapper_flags entry", name)
		}
	}
	for mode, paths := range config.Paths {
		if strings.TrimSpace(mode) == "" {
			return fmt.Errorf("%s Chromium browser config contains an empty paths mode", name)
		}
		if paths.ProfileDir == "" {
			return fmt.Errorf("%s Chromium browser config is missing paths.%s.profile_dir", name, mode)
		}
		for _, dir := range paths.ExternalExtensionDirs {
			if dir == "" {
				return fmt.Errorf("%s Chromium browser config contains an empty paths.%s.external_extension_dirs entry", name, mode)
			}
		}
	}
	for _, value := range config.Preferences.Values {
		if value.Path == "" {
			return fmt.Errorf("%s Chromium browser config contains a preference value without a path", name)
		}
	}
	for _, accelerator := range config.Preferences.Accelerators {
		if accelerator.Path == "" || accelerator.CommandID == "" || accelerator.Accelerator == "" {
			return fmt.Errorf("%s Chromium browser config contains an incomplete preference accelerator", name)
		}
	}
	return nil
}

func expandPathTemplate(path string) string {
	if path == "" {
		return ""
	}
	home := homeDir()
	return filepath.FromSlash(strings.NewReplacer(
		"${home}", home,
		"${config_home}", userdirs.ConfigHome(home),
		"${data_home}", userdirs.DataHome(home),
	).Replace(path))
}

func slicesClone[T any](values []T) []T {
	if values == nil {
		return nil
	}
	return append([]T{}, values...)
}
