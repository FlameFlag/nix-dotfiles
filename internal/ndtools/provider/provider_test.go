package provider

import (
	"slices"
	"testing"

	"github.com/FlameFlag/nix-dotfiles/internal/ndtools/manifest"
)

func TestRenderUsesPackageTargetAlias(t *testing.T) {
	argv, err := Render(
		Spec{
			Name:     "uv-tool-source",
			Argv:     []string{"uv", "tool", "install", "{{ .Package }} @ {{ .Source }}"},
			Required: []string{"package", "source"},
		},
		manifest.Tool{
			Name:     "yt-dlp",
			Provider: "uv-tool-source",
			Target:   "yt-dlp[default]",
			Source:   "https://example.test/yt-dlp.tar.gz",
		},
	)
	if err != nil {
		t.Fatal(err)
	}

	want := []string{"uv", "tool", "install", "yt-dlp[default] @ https://example.test/yt-dlp.tar.gz"}
	if !slices.Equal(argv, want) {
		t.Fatalf("argv = %#v, want %#v", argv, want)
	}
}

func TestRenderValidatesRequiredFields(t *testing.T) {
	_, err := Render(
		Spec{
			Name:     "source-tool",
			Argv:     []string{"tool", "{{ .Source }}"},
			Required: []string{"source"},
		},
		manifest.Tool{Name: "example", Provider: "source-tool", Package: "example"},
	)
	if err == nil {
		t.Fatal("expected error")
	}
}
