package provider

import (
	"bytes"
	"fmt"
	"strings"
	"text/template"

	"github.com/euvlok/nix-dotfiles/internal/ndtools/manifest"
)

type Spec struct {
	Name     string   `toml:"name"`
	Argv     []string `toml:"argv"`
	Required []string `toml:"required"`
}

type Values struct {
	Name     string
	Provider string
	Package  string
	Target   string
	Source   string
}

func Render(spec Spec, tool manifest.Tool) ([]string, error) {
	values := valuesFor(tool)
	if err := validateRequired(spec, values); err != nil {
		return nil, err
	}
	if len(spec.Argv) == 0 {
		return nil, fmt.Errorf("provider %q has no argv", spec.Name)
	}

	argv := make([]string, 0, len(spec.Argv))
	for _, arg := range spec.Argv {
		rendered, err := renderArg(spec.Name, arg, values)
		if err != nil {
			return nil, err
		}
		argv = append(argv, rendered)
	}
	return argv, nil
}

func valuesFor(tool manifest.Tool) Values {
	pkg := strings.TrimSpace(tool.Package)
	target := strings.TrimSpace(tool.Target)
	if pkg == "" {
		pkg = target
	}
	if target == "" {
		target = pkg
	}
	return Values{
		Name:     strings.TrimSpace(tool.Name),
		Provider: strings.TrimSpace(tool.Provider),
		Package:  pkg,
		Target:   target,
		Source:   strings.TrimSpace(tool.Source),
	}
}

func validateRequired(spec Spec, values Values) error {
	for _, field := range spec.Required {
		switch strings.ToLower(strings.TrimSpace(field)) {
		case "name":
			if values.Name == "" {
				return fmt.Errorf("provider %q requires name", spec.Name)
			}
		case "provider":
			if values.Provider == "" {
				return fmt.Errorf("provider %q requires provider", spec.Name)
			}
		case "package":
			if values.Package == "" {
				return fmt.Errorf("provider %q requires package", spec.Name)
			}
		case "target":
			if values.Target == "" {
				return fmt.Errorf("provider %q requires target", spec.Name)
			}
		case "source":
			if values.Source == "" {
				return fmt.Errorf("provider %q requires source", spec.Name)
			}
		default:
			return fmt.Errorf("provider %q requires unknown field %q", spec.Name, field)
		}
	}
	return nil
}

func renderArg(providerName, arg string, values Values) (string, error) {
	tmpl, err := template.New(providerName).Option("missingkey=error").Parse(arg)
	if err != nil {
		return "", fmt.Errorf("provider %q argv template %q: %w", providerName, arg, err)
	}
	var rendered bytes.Buffer
	if err := tmpl.Execute(&rendered, values); err != nil {
		return "", fmt.Errorf("provider %q argv template %q: %w", providerName, arg, err)
	}
	return rendered.String(), nil
}
