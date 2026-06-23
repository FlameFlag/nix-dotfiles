package chezmoi

import (
	"errors"
	"os"
	"path/filepath"
	"strings"

	"github.com/FlameFlag/nix-dotfiles/internal/common/process"
	"github.com/pelletier/go-toml/v2"
)

type extensionManifest struct {
	Extensions []extensionSpec `toml:"extensions"`
}

type extensionIDManifest struct {
	Extensions []string `toml:"extensions"`
}

type extensionSpec struct {
	ID string `toml:"id"`
}

func InstallVSExtensions(options Options) error {
	if _, ok := process.PathOf("code"); !ok {
		return nil
	}
	ctx, err := ContextWithOptions(options)
	if err != nil {
		return err
	}
	extensionsFile := filepath.Join(ctx.SourceDir, "dot_config/Code/User/vscode-extensions.toml")
	if _, err := os.Stat(extensionsFile); errors.Is(err, os.ErrNotExist) {
		return nil
	}
	installed, err := commandText([]string{"code", "--list-extensions"})
	if err != nil {
		return err
	}
	for _, extension := range extensionIDsFromFile(extensionsFile) {
		alreadyInstalled := false
		for line := range strings.SplitSeq(installed, "\n") {
			if strings.EqualFold(strings.TrimSpace(line), extension) {
				alreadyInstalled = true
				break
			}
		}
		if alreadyInstalled {
			continue
		}
		if err := process.RunInWithEnvAndStdin(
			"",
			[]string{"code", "--install-extension", extension, "--force"},
			nil,
			os.Stdin,
		); err != nil {
			return err
		}
	}
	return nil
}

func extensionIDsFromFile(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}

	var idManifest extensionIDManifest
	if err := toml.Unmarshal(data, &idManifest); err == nil {
		return cleanExtensionIDs(idManifest.Extensions)
	}

	var manifest extensionManifest
	if err := toml.Unmarshal(data, &manifest); err != nil {
		return nil
	}
	var ids []string
	for _, extension := range manifest.Extensions {
		ids = append(ids, extension.ID)
	}
	return cleanExtensionIDs(ids)
}

func cleanExtensionIDs(ids []string) []string {
	var out []string
	for _, id := range ids {
		id = strings.TrimSpace(id)
		if id != "" {
			out = append(out, id)
		}
	}
	return out
}
