package extensions

import (
	"encoding/json"
	"net/url"
	"os"
	"path/filepath"
	"strings"
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

func TestInstallPinsChromeStoreExtensionsToCRXFiles(t *testing.T) {
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
			parsed, err := url.Parse(rawURL)
			if err != nil {
				return "", err
			}
			rawX := parsed.Query().Get("x")
			id, _, ok := strings.Cut(strings.TrimPrefix(rawX, "id="), "&")
			if !ok {
				t.Fatalf("unexpected Chrome Store x query = %q", rawX)
			}
			return "https://clients2.googleusercontent.com/crx/blobs/example/" +
				strings.ToUpper(id) + "_8_12_24_34.crx", nil
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
	if got := store["external_crx"]; got == "" {
		t.Fatalf("external_crx is empty: %#v", store)
	}
	if got := store["external_version"]; got != "8.12.24.34" {
		t.Fatalf("external_version = %q, want resolved Chrome Store CRX version", got)
	}
	if _, ok := store["external_update_url"]; ok {
		t.Fatalf("Chrome Store extension should be pinned to external_crx: %#v", store)
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
