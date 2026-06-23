package config

import (
	"bytes"
	_ "embed"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"text/template"

	"github.com/FlameFlag/nix-dotfiles/internal/common/envx"
	"github.com/FlameFlag/nix-dotfiles/internal/ndtools/provider"
	"github.com/pelletier/go-toml/v2"
)

//go:embed defaults.toml
var defaults []byte

type Config struct {
	ManifestPath string          `toml:"manifest_path"`
	LockName     string          `toml:"lock_name"`
	PathPrefixes []string        `toml:"path_prefixes"`
	Immutable    Immutable       `toml:"immutable"`
	Schedule     Schedule        `toml:"schedule"`
	Providers    []provider.Spec `toml:"providers"`
}

type Immutable struct {
	Container string `toml:"container"`
}

type Schedule struct {
	Name              string `toml:"name"`
	IntervalHours     int    `toml:"interval_hours"`
	StartDelayMinutes int    `toml:"start_delay_minutes"`
}

type templateValues struct {
	Home       string
	ConfigHome string
}

type environment struct {
	Config       string `env:"ND_TOOLS_CONFIG"`
	LegacyConfig string `env:"NIX_DOTFILES_TOOL_UPDATE_CONFIG"`
	ConfigHome   string `env:"XDG_CONFIG_HOME"`
}

func Load() (Config, error) {
	return LoadFile(Path())
}

func LoadFile(path string) (Config, error) {
	config, err := parse(defaults)
	if err != nil {
		return Config{}, fmt.Errorf("parse embedded nd-tools defaults: %w", err)
	}

	if path != "" {
		override, err := os.ReadFile(path)
		switch {
		case err == nil:
			parsed, err := parse(override)
			if err != nil {
				return Config{}, fmt.Errorf("parse nd-tools config %s: %w", path, err)
			}
			config = merge(config, parsed)
		case errors.Is(err, os.ErrNotExist):
		default:
			return Config{}, fmt.Errorf("read nd-tools config %s: %w", path, err)
		}
	}

	if err := validate(config); err != nil {
		return Config{}, err
	}
	return resolve(config), nil
}

func Path() string {
	environment := envx.MustParse[environment]()
	if environment.Config != "" {
		return environment.Config
	}
	if environment.LegacyConfig != "" {
		return environment.LegacyConfig
	}
	return filepath.Join(configHome(), "nix-dotfiles", "nd-tools.toml")
}

func parse(data []byte) (Config, error) {
	var config Config
	if err := toml.Unmarshal(data, &config); err != nil {
		return Config{}, err
	}
	return config, nil
}

func merge(base, override Config) Config {
	if override.ManifestPath != "" {
		base.ManifestPath = override.ManifestPath
	}
	if override.LockName != "" {
		base.LockName = override.LockName
	}
	if len(override.PathPrefixes) > 0 {
		base.PathPrefixes = override.PathPrefixes
	}
	if override.Immutable.Container != "" {
		base.Immutable.Container = override.Immutable.Container
	}
	if override.Schedule.Name != "" {
		base.Schedule.Name = override.Schedule.Name
	}
	if override.Schedule.IntervalHours > 0 {
		base.Schedule.IntervalHours = override.Schedule.IntervalHours
	}
	if override.Schedule.StartDelayMinutes > 0 {
		base.Schedule.StartDelayMinutes = override.Schedule.StartDelayMinutes
	}
	if len(override.Providers) > 0 {
		base.Providers = mergeProviders(base.Providers, override.Providers)
	}
	return base
}

func mergeProviders(base, override []provider.Spec) []provider.Spec {
	index := map[string]int{}
	merged := slices.Clone(base)
	for i, spec := range merged {
		index[spec.Name] = i
	}
	for _, spec := range override {
		if i, ok := index[spec.Name]; ok {
			merged[i] = spec
			continue
		}
		index[spec.Name] = len(merged)
		merged = append(merged, spec)
	}
	return merged
}

func validate(config Config) error {
	if config.ManifestPath == "" {
		return fmt.Errorf("nd-tools config requires manifest_path")
	}
	if config.LockName == "" {
		return fmt.Errorf("nd-tools config requires lock_name")
	}
	if config.Immutable.Container == "" {
		return fmt.Errorf("nd-tools config requires immutable.container")
	}
	if config.Schedule.Name == "" {
		return fmt.Errorf("nd-tools config requires schedule.name")
	}
	if config.Schedule.IntervalHours <= 0 {
		return fmt.Errorf("nd-tools config requires schedule.interval_hours greater than zero")
	}
	if config.Schedule.StartDelayMinutes < 0 {
		return fmt.Errorf("nd-tools config requires schedule.start_delay_minutes to be zero or greater")
	}
	if len(config.Providers) == 0 {
		return fmt.Errorf("nd-tools config requires at least one provider")
	}
	seen := map[string]bool{}
	for _, spec := range config.Providers {
		if spec.Name == "" {
			return fmt.Errorf("nd-tools config contains a provider without a name")
		}
		if len(spec.Argv) == 0 {
			return fmt.Errorf("nd-tools provider %q requires argv", spec.Name)
		}
		if seen[spec.Name] {
			return fmt.Errorf("nd-tools config contains duplicate provider %q", spec.Name)
		}
		seen[spec.Name] = true
	}
	return nil
}

func resolve(config Config) Config {
	values := templateValues{
		Home:       homeDir(),
		ConfigHome: configHome(),
	}
	config.ManifestPath = renderConfigTemplate(config.ManifestPath, values)
	for i, prefix := range config.PathPrefixes {
		config.PathPrefixes[i] = renderConfigTemplate(prefix, values)
	}
	return config
}

func renderConfigTemplate(text string, values templateValues) string {
	tmpl, err := template.New("nd-tools-config").Option("missingkey=error").Parse(text)
	if err != nil {
		return text
	}
	var rendered bytes.Buffer
	if err := tmpl.Execute(&rendered, values); err != nil {
		return text
	}
	return rendered.String()
}

func homeDir() string {
	home, _ := os.UserHomeDir()
	return home
}

func configHome() string {
	environment := envx.MustParse[environment]()
	if environment.ConfigHome != "" {
		return environment.ConfigHome
	}
	return filepath.Join(homeDir(), ".config")
}
