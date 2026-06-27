package extensions

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"

	"github.com/FlameFlag/nix-dotfiles/internal/common/fileutil"
)

type Options struct {
	Root         string
	ExternalDirs []string
	Download     func(path, url string) error
	Resolve      func(url string) (string, error)
	Unzip        func(zipPath, dst string) error
}

type Result struct {
	LoadExtensionPaths []string
}

type installedCRXExtension struct {
	DownloadedExtension
	Path string
}

type installedUnpackedExtension struct {
	DownloadedExtension
	Path string
}

func Install(options Options) (Result, error) {
	catalog, err := LoadCatalog()
	if err != nil {
		return Result{}, err
	}

	crxDir := filepath.Join(options.Root, "extensions/crx")
	unpackedDir := filepath.Join(options.Root, "extensions/unpacked")
	if err := os.MkdirAll(crxDir, 0o755); err != nil {
		return Result{}, err
	}
	if err := os.MkdirAll(unpackedDir, 0o755); err != nil {
		return Result{}, err
	}

	crxExtensions := make([]installedCRXExtension, 0, len(catalog.CRX)+len(catalog.ChromeStore))
	for _, extension := range catalog.ChromeStore {
		crxURL, err := chromeStoreCRXDownloadURL(catalog.ChromeStoreUpdateURL, extension.ID)
		if err != nil {
			return Result{}, err
		}
		resolvedURL := crxURL
		if options.Resolve != nil {
			resolvedURL, err = options.Resolve(crxURL)
			if err != nil {
				return Result{}, err
			}
		}
		version, err := chromeStoreVersionFromCRXURL(extension.ID, resolvedURL)
		if err != nil {
			return Result{}, err
		}
		crxPath := filepath.Join(crxDir, extension.ID+".crx")
		if err := options.Download(crxPath, crxURL); err != nil {
			return Result{}, err
		}
		crxExtensions = append(crxExtensions, installedCRXExtension{
			DownloadedExtension: DownloadedExtension{
				ID:      extension.ID,
				Name:    extension.Name,
				Version: version,
				URL:     crxURL,
			},
			Path: crxPath,
		})
	}
	for _, extension := range catalog.CRX {
		crxPath := filepath.Join(crxDir, extension.ID+".crx")
		if err := options.Download(crxPath, extension.URL); err != nil {
			return Result{}, err
		}
		crxExtensions = append(crxExtensions, installedCRXExtension{
			DownloadedExtension: extension,
			Path:                crxPath,
		})
	}

	unpackedExtensions := make([]installedUnpackedExtension, 0, len(catalog.ZIP))
	for _, extension := range catalog.ZIP {
		zipPath := filepath.Join(
			options.Root,
			"extensions",
			extension.ID+"-"+extension.Version+".zip",
		)
		extensionDir := filepath.Join(unpackedDir, extension.ID)
		if err := options.Download(zipPath, extension.URL); err != nil {
			return Result{}, err
		}
		if err := os.RemoveAll(extensionDir); err != nil {
			return Result{}, err
		}
		if err := options.Unzip(zipPath, extensionDir); err != nil {
			return Result{}, err
		}
		if err := patchUnpackedExtension(extensionDir); err != nil {
			return Result{}, err
		}
		unpackedExtensions = append(unpackedExtensions, installedUnpackedExtension{
			DownloadedExtension: extension,
			Path:                extensionDir,
		})
	}

	for _, externalDir := range options.ExternalDirs {
		if err := os.MkdirAll(externalDir, 0o755); err != nil {
			return Result{}, err
		}
		for _, extension := range crxExtensions {
			if err := writeExternalJSON(
				filepath.Join(externalDir, extension.ID+".json"),
				map[string]string{
					"external_crx":     extension.Path,
					"external_version": extension.Version,
				},
			); err != nil {
				return Result{}, err
			}
		}
		for _, extension := range catalog.UpdateURL {
			if err := writeExternalJSON(
				filepath.Join(externalDir, extension.ID+".json"),
				map[string]string{
					"external_update_url": extension.UpdateURL,
				},
			); err != nil {
				return Result{}, err
			}
		}
	}

	result := Result{}
	for _, extension := range unpackedExtensions {
		if extension.LoadUnpacked {
			result.LoadExtensionPaths = append(result.LoadExtensionPaths, extension.Path)
		}
	}
	return result, nil
}

func writeExternalJSON(path string, value map[string]string) error {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	_, err = fileutil.WriteTextIfChanged(path, string(data))
	return err
}

func patchUnpackedExtension(path string) error {
	backgroundBundle := filepath.Join(path, "bundles/common-background.bundle.js")
	data, err := os.ReadFile(backgroundBundle)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	text := string(data)
	text = strings.ReplaceAll(
		text,
		`case"install":yield browser.runtime.openOptionsPage();break;case"update":`,
		`case"install":break;case"update":`,
	)
	_, err = fileutil.WriteTextIfChanged(backgroundBundle, text)
	return err
}

func chromeStoreCRXDownloadURL(updateURL, id string) (string, error) {
	parsed, err := url.Parse(updateURL)
	if err != nil {
		return "", fmt.Errorf("parse Chrome Store update URL for %s: %w", id, err)
	}
	query := parsed.Query()
	query.Set("response", "redirect")
	query.Set("prodversion", "140.0.0.0")
	query.Set("acceptformat", "crx2,crx3")
	query.Set("x", "id="+id+"&uc")
	parsed.RawQuery = query.Encode()
	return parsed.String(), nil
}

func chromeStoreVersionFromCRXURL(id, crxURL string) (string, error) {
	parsed, err := url.Parse(crxURL)
	if err != nil {
		return "", fmt.Errorf("parse Chrome Store CRX URL for %s: %w", id, err)
	}
	file := filepath.Base(parsed.Path)
	prefix := strings.ToUpper(id) + "_"
	if !strings.HasPrefix(file, prefix) || !strings.HasSuffix(file, ".crx") {
		return "", fmt.Errorf("parse Chrome Store CRX version for %s from %s", id, crxURL)
	}
	version := strings.TrimSuffix(strings.TrimPrefix(file, prefix), ".crx")
	return strings.ReplaceAll(version, "_", "."), nil
}

func UnpackedExtensionID(path string) string {
	sum := sha256.Sum256([]byte(filepath.Clean(path)))
	id := make([]byte, 32)
	for i, value := range sum[:16] {
		id[i*2] = 'a' + value>>4
		id[i*2+1] = 'a' + value&0x0f
	}
	return string(id)
}
