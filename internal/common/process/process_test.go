package process

import (
	"os"
	"path/filepath"
	"testing"
)

func TestPathOfWithPath(t *testing.T) {
	dir := t.TempDir()
	bin := filepath.Join(dir, "demo")
	if err := WriteTestExecutable(bin); err != nil {
		t.Fatal(err)
	}
	got, ok := PathOfWithPath("demo", dir)
	if !ok || got != bin {
		t.Fatalf("PathOfWithPath = %q, %v; want %q, true", got, ok, bin)
	}
}

func TestPathOfRejectsPathLikeNonExecutable(t *testing.T) {
	path := filepath.Join(t.TempDir(), "not-executable")
	if err := os.WriteFile(path, []byte("#!/bin/sh\nexit 0\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got, ok := PathOf(path); ok {
		t.Fatalf("PathOf = %q, true; want false", got)
	}
	if got, ok := PathOfWithPath(path, ""); ok {
		t.Fatalf("PathOfWithPath = %q, true; want false", got)
	}
}

func WriteTestExecutable(path string) error {
	return osWriteFileExecutable(path, []byte("#!/bin/sh\nexit 0\n"))
}
