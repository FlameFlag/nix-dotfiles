package manifest

import (
	"os"
	"slices"

	"github.com/pelletier/go-toml/v2"
)

type Tool struct {
	Name     string `toml:"name"`
	Provider string `toml:"provider"`
	Package  string `toml:"package"`
	Target   string `toml:"target"`
	Source   string `toml:"source"`
	Enabled  *bool  `toml:"enabled"`
}

type File struct {
	Tools []Tool `toml:"tools"`
	Tool  []Tool `toml:"tool"`
}

func Read(path string) ([]Tool, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var file File
	if err := toml.Unmarshal(data, &file); err != nil {
		return nil, err
	}
	return slices.Concat(file.Tools, file.Tool), nil
}
