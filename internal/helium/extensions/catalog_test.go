package extensions

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestCatalogIsValid(t *testing.T) {
	catalog, err := LoadCatalog()
	if err != nil {
		t.Fatal(err)
	}
	if len(catalog.ChromeStore) == 0 {
		t.Fatal("Chrome Store extensions are empty")
	}
	if len(catalog.CRX) == 0 {
		t.Fatal("CRX extensions are empty")
	}
	if len(catalog.ZIP) == 0 {
		t.Fatal("ZIP extensions are empty")
	}
}

func TestInstallUsesUpdateURLForChromeStoreExtensions(t *testing.T) {
	root := t.TempDir()
	home := filepath.Join(root, "home")
	t.Setenv("HOME", home)

	_, err := Install(Options{
		Mode: "macos",
		Root: filepath.Join(root, "cache"),
		Download: func(path, url string) error {
			if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
				return err
			}
			return os.WriteFile(path, []byte(url), 0o644)
		},
		Resolve: func(rawURL string) (string, error) {
			t.Fatalf("Chrome Store extensions should use external_update_url, not resolve %s", rawURL)
			return "", nil
		},
		Unzip: func(zipPath, dst string) error {
			bundles := filepath.Join(dst, "bundles")
			if err := os.MkdirAll(bundles, 0o755); err != nil {
				return err
			}
			return os.WriteFile(
				filepath.Join(bundles, "common-background.bundle.js"),
				[]byte(`case"install":yield browser.runtime.openOptionsPage();break;case"update":`),
				0o644,
			)
		},
	})
	if err != nil {
		t.Fatal(err)
	}

	path := filepath.Join(
		home,
		"Library/Application Support/net.imput.helium/External Extensions/aeblfdkhhhdcdjpifhhbdiojplfjncoa.json",
	)
	store := readExternalJSONTest(t, path)
	if got := store["external_update_url"]; got != "https://clients2.google.com/service/update2/crx" {
		t.Fatalf("Chrome Store update URL = %q, want Chrome Store update endpoint", got)
	}
	if _, ok := store["external_crx"]; ok {
		t.Fatalf("Chrome Store extension should use update URL instead of pinned CRX: %#v", store)
	}
	if _, ok := store["external_version"]; ok {
		t.Fatalf("Chrome Store extension should not include external_version: %#v", store)
	}
}

func readExternalJSONTest(t *testing.T, path string) map[string]string {
	t.Helper()

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	value := map[string]string{}
	if err := json.Unmarshal(data, &value); err != nil {
		t.Fatal(err)
	}
	return value
}
