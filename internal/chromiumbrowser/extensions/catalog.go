package extensions

import (
	_ "embed"
	"fmt"
	"net/url"
	"slices"
	"strings"

	"github.com/pelletier/go-toml/v2"
)

//go:embed extensions.toml
var catalogData []byte

type Catalog struct {
	ChromeStoreUpdateURL string                 `toml:"chrome_store_update_url"`
	ChromeStore          []ChromeStoreExtension `toml:"chrome_store_extensions"`
	UpdateURL            []UpdateURLExtension   `toml:"update_url_extensions"`
	CRX                  []DownloadedExtension  `toml:"crx_extensions"`
	ZIP                  []DownloadedExtension  `toml:"zip_extensions"`
}

type ChromeStoreExtension struct {
	ID   string `toml:"id"`
	Name string `toml:"name"`
}

type UpdateURLExtension struct {
	ID        string `toml:"id"`
	Name      string `toml:"name"`
	UpdateURL string `toml:"update_url"`
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
		return catalog, fmt.Errorf("parse embedded Chromium extension catalog: %w", err)
	}
	if catalog.ChromeStoreUpdateURL == "" {
		return catalog, fmt.Errorf("chromium extension catalog is missing chrome_store_update_url")
	}
	if !validExternalUpdateURL(catalog.ChromeStoreUpdateURL) {
		return catalog, fmt.Errorf("chromium extension catalog has an invalid chrome_store_update_url")
	}
	for _, extension := range catalog.ChromeStore {
		if !validExtensionID(extension.ID) {
			return catalog, fmt.Errorf(
				"chromium extension catalog contains a Chrome Store entry with an invalid id",
			)
		}
	}
	for _, extension := range catalog.UpdateURL {
		if !validExtensionID(extension.ID) || !validExternalUpdateURL(extension.UpdateURL) {
			return catalog, fmt.Errorf(
				"chromium extension catalog contains an incomplete update URL extension entry",
			)
		}
	}
	for _, extension := range slices.Concat(catalog.CRX, catalog.ZIP) {
		missingID := extension.ID == ""
		missingVersion := extension.Version == ""
		missingURL := extension.URL == ""
		if missingID || missingVersion || missingURL ||
			!validExtensionID(extension.ID) ||
			!validExternalVersion(extension.Version) ||
			!validExternalUpdateURL(extension.URL) {
			return catalog, fmt.Errorf(
				"chromium extension catalog contains an incomplete downloaded extension entry",
			)
		}
	}
	return catalog, nil
}

func validExtensionID(id string) bool {
	if len(id) != 32 {
		return false
	}
	for _, char := range id {
		if char < 'a' || char > 'p' {
			return false
		}
	}
	return true
}

func validExternalUpdateURL(rawURL string) bool {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return false
	}
	return parsed.Scheme != "" && parsed.Host != ""
}

func validExternalVersion(version string) bool {
	parts := strings.Split(version, ".")
	if len(parts) == 0 {
		return false
	}
	for _, part := range parts {
		if part == "" {
			return false
		}
		for _, char := range part {
			if char < '0' || char > '9' {
				return false
			}
		}
	}
	return true
}
