//go:build linux

package backend

import "testing"

func TestParseMode(t *testing.T) {
	if got, err := ParseMode("0"); err != nil || got {
		t.Fatalf("ParseMode(0) = %v, %v", got, err)
	}
	if got, err := ParseMode("1"); err != nil || !got {
		t.Fatalf("ParseMode(1) = %v, %v", got, err)
	}
	if _, err := ParseMode("2"); err == nil {
		t.Fatalf("ParseMode(2) did not fail")
	}
}
