package updater

import (
	"bufio"
	_ "embed"
	"fmt"
	"os"
	"slices"
	"strings"

	"github.com/FlameFlag/nix-dotfiles/internal/immutableactivate/config"
	activationruntime "github.com/FlameFlag/nix-dotfiles/internal/immutableactivate/runtime"
	"github.com/pelletier/go-toml/v2"
)

//go:embed defaults.toml
var defaultConfigData []byte

const (
	osReleaseIDKey     = "ID"
	osReleaseIDLikeKey = "ID_LIKE"
)

var defaultConfig = mustLoadDefaultConfig(defaultConfigData)

type defaultConfigFile struct {
	Native        []nativeUpdaterSpec        `toml:"native_updater"`
	Opportunistic []opportunisticUpdaterSpec `toml:"opportunistic_updater"`
	OSRelease     []osReleaseUpdaterSpec     `toml:"os_release_updater"`
}

type nativeUpdaterSpec struct {
	Name     string     `toml:"name"`
	Commands [][]string `toml:"commands"`
}

type opportunisticUpdaterSpec struct {
	Program  string     `toml:"program"`
	Commands [][]string `toml:"commands"`
}

type osReleaseUpdaterSpec struct {
	ID      string `toml:"id"`
	Updater string `toml:"updater"`
}

type updaterConfig struct {
	NativeCommands map[string][][]string
	Opportunistic  []opportunisticUpdaterSpec
	OSRelease      map[string]string
}

func mustLoadDefaultConfig(data []byte) updaterConfig {
	config, err := loadDefaultConfig(data)
	if err != nil {
		panic(err)
	}
	return config
}

func loadDefaultConfig(data []byte) (updaterConfig, error) {
	var file defaultConfigFile
	if err := toml.Unmarshal(data, &file); err != nil {
		return updaterConfig{}, fmt.Errorf("parse embedded updater defaults: %w", err)
	}
	config := updaterConfig{
		NativeCommands: map[string][][]string{},
		OSRelease:      map[string]string{},
	}
	for _, spec := range file.Native {
		if spec.Name == "" {
			return updaterConfig{}, fmt.Errorf(
				"embedded updater defaults contain a native updater without a name",
			)
		}
		if err := validateCommands(spec.Commands); err != nil {
			return updaterConfig{}, fmt.Errorf("native updater %q: %w", spec.Name, err)
		}
		config.NativeCommands[spec.Name] = spec.Commands
	}
	if _, ok := config.NativeCommands["none"]; !ok {
		return updaterConfig{}, fmt.Errorf("embedded updater defaults must define the none updater")
	}
	for _, spec := range file.Opportunistic {
		if spec.Program == "" {
			return updaterConfig{}, fmt.Errorf(
				"embedded updater defaults contain an opportunistic updater without a program",
			)
		}
		if err := validateCommands(spec.Commands); err != nil {
			return updaterConfig{}, fmt.Errorf("opportunistic updater %q: %w", spec.Program, err)
		}
		config.Opportunistic = append(config.Opportunistic, spec)
	}
	for _, spec := range file.OSRelease {
		if spec.ID == "" || spec.Updater == "" {
			return updaterConfig{}, fmt.Errorf(
				"embedded updater defaults contain an incomplete OS release mapping",
			)
		}
		if _, ok := config.NativeCommands[spec.Updater]; !ok {
			return updaterConfig{}, fmt.Errorf(
				"OS release %q references unknown updater %q",
				spec.ID,
				spec.Updater,
			)
		}
		config.OSRelease[spec.ID] = spec.Updater
	}
	return config, nil
}

func validateCommands(commands [][]string) error {
	for _, command := range commands {
		if len(command) == 0 {
			return fmt.Errorf("command argv must not be empty")
		}
	}
	return nil
}

func RunNative(options config.Options, hostUpdater string) error {
	updater, err := Detect(options, hostUpdater)
	if err != nil {
		return err
	}
	commands, ok := defaultConfig.NativeCommands[updater]
	if !ok {
		return fmt.Errorf("unknown host updater: %s", updater)
	}
	if err := runCommands(options, commands); err != nil {
		return err
	}
	for _, spec := range defaultConfig.Opportunistic {
		if options.CommandExists(spec.Program) {
			if err := runCommands(options, spec.Commands); err != nil {
				return err
			}
		}
	}
	return nil
}

func runCommands(options config.Options, argvSet [][]string) error {
	for _, argv := range argvSet {
		if err := options.Executor.Run(
			activationruntime.Command{Argv: slices.Clone(argv)},
		); err != nil {
			return err
		}
	}
	return nil
}

func Detect(options config.Options, hostUpdater string) (string, error) {
	if hostUpdater == "auto" {
		return detectAuto(options), nil
	}
	if _, ok := defaultConfig.NativeCommands[hostUpdater]; ok {
		return hostUpdater, nil
	}
	return "", fmt.Errorf("unknown host updater: %s", hostUpdater)
}

func detectAuto(options config.Options) string {
	if _, err := os.Stat(options.OstreeBootedPath); err == nil {
		return "rpm-ostree"
	}
	for _, word := range OSReleaseWords(options.OSReleasePath) {
		if updater := defaultConfig.OSRelease[word]; updater != "" {
			return updater
		}
	}
	return "none"
}

func OSReleaseWords(path string) []string {
	file, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer file.Close()

	var words []string
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		key, value, ok := strings.Cut(scanner.Text(), "=")
		relevantKey := key == osReleaseIDKey || key == osReleaseIDLikeKey
		if !ok || !relevantKey {
			continue
		}
		value = strings.Trim(value, `"`)
		for word := range strings.FieldsSeq(value) {
			words = append(words, word)
		}
	}
	if scanner.Err() != nil {
		return nil
	}
	return words
}
