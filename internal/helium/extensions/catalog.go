package extensions

import (
	_ "embed"
	"fmt"
	"slices"

	"github.com/pelletier/go-toml/v2"
)

//go:embed extensions.toml
var catalogData []byte

type Catalog struct {
	ChromeStoreUpdateURL string                 `toml:"chrome_store_update_url"`
	ChromeStore          []ChromeStoreExtension `toml:"chrome_store_extensions"`
	CRX                  []DownloadedExtension  `toml:"crx_extensions"`
	ZIP                  []DownloadedExtension  `toml:"zip_extensions"`
}

type ChromeStoreExtension struct {
	ID   string `toml:"id"`
	Name string `toml:"name"`
}

type DownloadedExtension struct {
	ID           string `toml:"id"`
	Name         string `toml:"name"`
	Version      string `toml:"version"`
	URL          string `toml:"url"`
	LoadUnpacked bool   `toml:"load_unpacked"`
}

func LoadCatalog() (Catalog, error) {
	var catalog Catalog
	if err := toml.Unmarshal(catalogData, &catalog); err != nil {
		return catalog, fmt.Errorf("parse embedded Helium extension catalog: %w", err)
	}
	if catalog.ChromeStoreUpdateURL == "" {
		return catalog, fmt.Errorf("helium extension catalog is missing chrome_store_update_url")
	}
	for _, extension := range catalog.ChromeStore {
		if extension.ID == "" {
			return catalog, fmt.Errorf(
				"helium extension catalog contains a Chrome Store entry without an id",
			)
		}
	}
	for _, extension := range slices.Concat(catalog.CRX, catalog.ZIP) {
		missingID := extension.ID == ""
		missingVersion := extension.Version == ""
		missingURL := extension.URL == ""
		if missingID || missingVersion || missingURL {
			return catalog, fmt.Errorf(
				"helium extension catalog contains an incomplete downloaded extension entry",
			)
		}
	}
	return catalog, nil
}
