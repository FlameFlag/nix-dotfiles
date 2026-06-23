package helium

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/buildkite/shellwords"
)

func TestWriteWrapperParsesAndQuotesFlags(t *testing.T) {
	target := filepath.Join(t.TempDir(), "helium-browser")
	options := &InstallOptions{
		Flags: `--user-data-dir "/tmp/Helium Profile" --name "O'Brien"`,
	}

	if err := writeWrapper(target, "/opt/Helium/helium-wrapper", options); err != nil {
		t.Fatal(err)
	}

	data, err := os.ReadFile(target)
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	for _, want := range []string{
		shellwords.QuotePosix("/opt/Helium/helium-wrapper"),
		"--user-data-dir",
		shellwords.QuotePosix("/tmp/Helium Profile"),
		"--name",
		shellwords.QuotePosix("O'Brien"),
	} {
		if !strings.Contains(text, want) {
			t.Fatalf("wrapper %q does not contain %q", text, want)
		}
	}
}
