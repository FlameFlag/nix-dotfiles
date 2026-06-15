package lenovo

import "testing"

func TestStateLabels(t *testing.T) {
	if StateLabel(true) != "ENABLED (60% charge)" {
		t.Fatalf("enabled label mismatch")
	}
	if StateLabel(false) != "DISABLED (100% charge)" {
		t.Fatalf("disabled label mismatch")
	}
}

func TestParseAction(t *testing.T) {
	if got, err := ParseAction(""); err != nil || got != Toggle {
		t.Fatalf("empty action = %q, %v", got, err)
	}
	if _, err := ParseAction("wat"); err == nil {
		t.Fatalf("invalid action did not fail")
	}
}
