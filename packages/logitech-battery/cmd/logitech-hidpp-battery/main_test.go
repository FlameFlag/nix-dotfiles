package main

import "testing"

func TestParseUnifiedBattery(t *testing.T) {
	batt, ok := parseUnifiedBattery([]byte{87, 8, 0, 0})
	if !ok {
		t.Fatal("battery should parse")
	}
	if batt.percentage != 87 {
		t.Fatalf("percentage = %d, want 87", batt.percentage)
	}
	if batt.charging {
		t.Fatal("battery should not be charging")
	}
}

func TestParseUnifiedBatteryApproximation(t *testing.T) {
	batt, ok := parseUnifiedBattery([]byte{0, 2, 1, 0})
	if !ok {
		t.Fatal("battery should parse")
	}
	if batt.percentage != 20 {
		t.Fatalf("percentage = %d, want 20", batt.percentage)
	}
	if !batt.charging {
		t.Fatal("battery should be charging")
	}
}

func TestEstimateBatteryPercentage(t *testing.T) {
	if got := estimateBatteryPercentage(4186); got != 100 {
		t.Fatalf("estimateBatteryPercentage(4186) = %d, want 100", got)
	}
	if got := estimateBatteryPercentage(3500); got != 0 {
		t.Fatalf("estimateBatteryPercentage(3500) = %d, want 0", got)
	}
	if got := estimateBatteryPercentage(3811); got != 50 {
		t.Fatalf("estimateBatteryPercentage(3811) = %d, want 50", got)
	}
}

func TestInputReportSizes(t *testing.T) {
	descriptor := []byte{
		0x85, 0x10, // Report ID 0x10
		0x75, 0x08, // Report Size 8
		0x95, 0x06, // Report Count 6
		0x81, 0x02, // Input
		0x85, 0x11, // Report ID 0x11
		0x75, 0x08, // Report Size 8
		0x95, 0x13, // Report Count 19
		0x81, 0x02, // Input
	}
	sizes := inputReportSizes(descriptor)
	if got := sizes[hidppShortReportID]; got != 48 {
		t.Fatalf("short report size = %d, want 48", got)
	}
	if got := sizes[hidppLongReportID]; got != 152 {
		t.Fatalf("long report size = %d, want 152", got)
	}
}
