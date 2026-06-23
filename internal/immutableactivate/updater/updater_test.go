package updater

import (
	"bufio"
	"os"
	"strings"
	"testing"
)

func TestDefaultConfigLoads(t *testing.T) {
	config, err := loadDefaultConfig(defaultConfigData)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := config.NativeCommands["none"]; !ok {
		t.Fatalf("native updaters missing none: %#v", config.NativeCommands)
	}
	if got := config.OSRelease["fedora"]; got != "dnf" {
		t.Fatalf("fedora updater = %q; want dnf", got)
	}
	if len(config.Opportunistic) == 0 {
		t.Fatalf("opportunistic updaters were not loaded")
	}
}

func TestDefaultConfigRejectsUnknownOSReleaseUpdater(t *testing.T) {
	_, err := loadDefaultConfig([]byte(`
[[native_updater]]
name = "none"

[[os_release_updater]]
id = "demo"
updater = "missing"
`))
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestOSReleaseWordsReturnsNilOnScanError(t *testing.T) {
	file, err := os.CreateTemp(t.TempDir(), "os-release")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := file.WriteString(
		"ID=" + strings.Repeat("x", bufio.MaxScanTokenSize) + "\n",
	); err != nil {
		t.Fatal(err)
	}
	if err := file.Close(); err != nil {
		t.Fatal(err)
	}

	if got := OSReleaseWords(file.Name()); got != nil {
		t.Fatalf("OSReleaseWords() = %#v; want nil", got)
	}
}
