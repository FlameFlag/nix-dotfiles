package extensions

import (
	"encoding/json"
	"os"
	"path/filepath"

	"github.com/euvlok/nix-dotfiles/internal/common/fileutil"
	"github.com/euvlok/nix-dotfiles/internal/common/userdirs"
)

type Options struct {
	Mode     string
	Root     string
	Download func(path, url string) error
	Unzip    func(zipPath, dst string) error
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

	crxExtensions := make([]installedCRXExtension, 0, len(catalog.CRX))
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
		unpackedExtensions = append(unpackedExtensions, installedUnpackedExtension{
			DownloadedExtension: extension,
			Path:                extensionDir,
		})
	}

	var externalDirs []string
	switch options.Mode {
	case "macos":
		externalDirs = []string{
			filepath.Join(
				os.Getenv("HOME"),
				"Library/Application Support/net.imput.helium/External Extensions",
			),
			filepath.Join(
				os.Getenv("HOME"),
				"Library/Application Support/Helium/External Extensions",
			),
		}
	case "linux":
		externalDirs = []string{
			filepath.Join(
				userdirs.ConfigHome(os.Getenv("HOME")),
				"net.imput.helium/External Extensions",
			),
		}
	}

	for _, externalDir := range externalDirs {
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
		for _, extension := range catalog.ChromeStore {
			if err := writeExternalJSON(
				filepath.Join(externalDir, extension.ID+".json"),
				map[string]string{
					"external_update_url": catalog.ChromeStoreUpdateURL,
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
