package main

import "testing"

func TestParseBatteryReportLiveNovaProSample(t *testing.T) {
	report := batteryReportSample()

	parsed, err := parseBatteryReport(report)
	if err != nil {
		t.Fatalf("parseBatteryReport returned error: %v", err)
	}

	if !parsed.headsetOnline {
		t.Fatal("headset should be online")
	}
	if parsed.headsetCharging {
		t.Fatal("headset should not be charging")
	}
	if parsed.headsetRaw != 3 {
		t.Fatalf("headset raw = %d, want 3", parsed.headsetRaw)
	}
	if parsed.headsetPercentage != 38 {
		t.Fatalf("headset percentage = %d, want 38", parsed.headsetPercentage)
	}

	if !parsed.chargerAvailable {
		t.Fatal("charger battery should be available")
	}
	if parsed.chargerCharging {
		t.Fatal("charger battery should not be charging")
	}
	if parsed.chargerRaw != 5 {
		t.Fatalf("charger raw = %d, want 5", parsed.chargerRaw)
	}
	if parsed.chargerPercentage != 63 {
		t.Fatalf("charger percentage = %d, want 63", parsed.chargerPercentage)
	}
}

func TestParseBatteryReportChargingStates(t *testing.T) {
	report := batteryReportSample()
	report[headsetStatusByte] = headsetCableCharging
	report[chargerStatusByte] = headsetCableCharging

	parsed, err := parseBatteryReport(report)
	if err != nil {
		t.Fatalf("parseBatteryReport returned error: %v", err)
	}

	if !parsed.headsetCharging {
		t.Fatal("headset should be charging")
	}
	if !parsed.chargerCharging {
		t.Fatal("charger battery should be charging")
	}
	if !parsed.headsetOnline {
		t.Fatal("charging headset should still be considered online")
	}
	if !parsed.chargerAvailable {
		t.Fatal("charging spare battery should still be considered available")
	}
}

func TestParseBatteryReportLiveOnlineChargingSample(t *testing.T) {
	report := batteryReportFromFirst16(
		0x06, 0xb0, 0x00, 0x00, 0x01, 0x00, 0x04, 0x00,
		0x0a, 0x00, 0x00, 0x0a, 0x05, 0x00, 0x08, 0x02,
	)

	parsed, err := parseBatteryReport(report)
	if err != nil {
		t.Fatalf("parseBatteryReport returned error: %v", err)
	}

	if !parsed.headsetOnline {
		t.Fatal("headset should be online")
	}
	if !parsed.headsetCharging {
		t.Fatal("headset should be charging")
	}
	if parsed.headsetRaw != 4 {
		t.Fatalf("headset raw = %d, want 4", parsed.headsetRaw)
	}
	if parsed.headsetPercentage != 50 {
		t.Fatalf("headset percentage = %d, want 50", parsed.headsetPercentage)
	}
	if !parsed.chargerAvailable {
		t.Fatal("charger battery should be available")
	}
	if parsed.chargerCharging {
		t.Fatal("charger battery should not be charging")
	}
	if parsed.chargerRaw != 5 {
		t.Fatalf("charger raw = %d, want 5", parsed.chargerRaw)
	}
	if parsed.chargerPercentage != 63 {
		t.Fatalf("charger percentage = %d, want 63", parsed.chargerPercentage)
	}
}

func TestParseBatteryReportLiveChargingBucketAdvanceSample(t *testing.T) {
	report := batteryReportFromFirst16(
		0x06, 0xb0, 0x00, 0x00, 0x01, 0x00, 0x05, 0x00,
		0x0a, 0x00, 0x00, 0x0a, 0x05, 0x00, 0x08, 0x02,
	)

	parsed, err := parseBatteryReport(report)
	if err != nil {
		t.Fatalf("parseBatteryReport returned error: %v", err)
	}

	if !parsed.headsetOnline {
		t.Fatal("headset should be online")
	}
	if !parsed.headsetCharging {
		t.Fatal("headset should be charging")
	}
	if parsed.headsetRaw != 5 {
		t.Fatalf("headset raw = %d, want 5", parsed.headsetRaw)
	}
	if parsed.headsetPercentage != 63 {
		t.Fatalf("headset percentage = %d, want 63", parsed.headsetPercentage)
	}
	if !parsed.chargerAvailable {
		t.Fatal("charger battery should be available")
	}
	if parsed.chargerRaw != 5 {
		t.Fatalf("charger raw = %d, want 5", parsed.chargerRaw)
	}
	if parsed.chargerPercentage != 63 {
		t.Fatalf("charger percentage = %d, want 63", parsed.chargerPercentage)
	}
}

func TestParseBatteryReportLiveOfflineSpareSample(t *testing.T) {
	report := batteryReportFromFirst16(
		0x06, 0xb0, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
		0x0a, 0x00, 0x00, 0x0a, 0x05, 0x00, 0x04, 0x01,
	)

	parsed, err := parseBatteryReport(report)
	if err != nil {
		t.Fatalf("parseBatteryReport returned error: %v", err)
	}

	if parsed.headsetOnline {
		t.Fatal("headset should be offline")
	}
	if parsed.headsetCharging {
		t.Fatal("offline headset should not be charging")
	}
	if parsed.headsetRaw != 0 {
		t.Fatalf("headset raw = %d, want 0", parsed.headsetRaw)
	}
	if !parsed.chargerAvailable {
		t.Fatal("charger battery should be available")
	}
	if parsed.chargerCharging {
		t.Fatal("charger battery should not be charging")
	}
	if parsed.chargerRaw != 5 {
		t.Fatalf("charger raw = %d, want 5", parsed.chargerRaw)
	}
	if parsed.chargerPercentage != 63 {
		t.Fatalf("charger percentage = %d, want 63", parsed.chargerPercentage)
	}
}

func TestParseBatteryReportUnavailableStates(t *testing.T) {
	report := batteryReportSample()
	report[headsetStatusByte] = headsetOffline
	report[chargerStatusByte] = headsetOffline

	parsed, err := parseBatteryReport(report)
	if err != nil {
		t.Fatalf("parseBatteryReport returned error: %v", err)
	}

	if parsed.headsetOnline {
		t.Fatal("headset should be offline")
	}
	if parsed.chargerAvailable {
		t.Fatal("charger battery should be unavailable")
	}
}

func TestParseBatteryReportRejectsUnknownStatusBytes(t *testing.T) {
	report := batteryReportSample()
	report[headsetStatusByte] = 0x7f
	report[chargerStatusByte] = 0x7f

	parsed, err := parseBatteryReport(report)
	if err != nil {
		t.Fatalf("parseBatteryReport returned error: %v", err)
	}

	if parsed.headsetOnline {
		t.Fatal("headset should not be online for an unknown status byte")
	}
	if parsed.chargerAvailable {
		t.Fatal("charger battery should not be available for an unknown status byte")
	}
}

func TestBatterySummariesHideSecondaryBucketWhenHeadsetOffline(t *testing.T) {
	device := hidrawDevice{
		devnode:   "/dev/hidraw-test",
		productID: 0x225d,
	}
	parsed := batteryReport{
		headsetPercentage: 0,
		headsetOnline:     false,
		chargerPercentage: 63,
		chargerAvailable:  true,
	}

	summaries := batterySummariesFromParsed(device, parsed)
	if len(summaries) != 0 {
		t.Fatalf("len(summaries) = %d, want 0", len(summaries))
	}
}

func TestBatterySummariesExposeHeadsetState(t *testing.T) {
	device := hidrawDevice{
		devnode:   "/dev/hidraw-test",
		productID: 0x225d,
	}
	parsed := batteryReport{
		headsetPercentage: 50,
		headsetCharging:   true,
		headsetOnline:     true,
		chargerPercentage: 63,
		chargerAvailable:  true,
	}

	summaries := batterySummariesFromParsed(device, parsed)
	if len(summaries) != 1 {
		t.Fatalf("len(summaries) = %d, want 1", len(summaries))
	}
	if summaries[0].State != stateCharging {
		t.Fatalf("headset state = %q, want %q", summaries[0].State, stateCharging)
	}

	parsed.headsetCharging = false
	parsed.chargerCharging = true
	summaries = batterySummariesFromParsed(device, parsed)
	if summaries[0].State != stateOnline {
		t.Fatalf("headset state = %q, want %q", summaries[0].State, stateOnline)
	}
}

func TestParseBatteryReportRejectsInvalidReports(t *testing.T) {
	if _, err := parseBatteryReport([]byte{0x06, 0xb0}); err == nil {
		t.Fatal("short report should fail")
	}

	report := batteryReportSample()
	report[1] = 0x00
	if _, err := parseBatteryReport(report); err == nil {
		t.Fatal("unexpected command echo should fail")
	}
}

func TestBatteryBucketPercentageClampsToDeviceRange(t *testing.T) {
	tests := []struct {
		raw  int
		want int
	}{
		{raw: -1, want: 0},
		{raw: 0, want: 0},
		{raw: 3, want: 38},
		{raw: 5, want: 63},
		{raw: 8, want: 100},
		{raw: 9, want: 100},
	}

	for _, test := range tests {
		if got := batteryBucketPercentage(test.raw); got != test.want {
			t.Fatalf("batteryBucketPercentage(%d) = %d, want %d", test.raw, got, test.want)
		}
	}
}

func batteryReportSample() []byte {
	return batteryReportFromFirst16(
		0x06, 0xb0, 0x00, 0x00, 0x01, 0x00, 0x03, 0x00,
		0x0a, 0x00, 0x00, 0x0a, 0x05, 0x00, 0x08, 0x08,
	)
}

func batteryReportFromFirst16(first16 ...byte) []byte {
	report := make([]byte, 64)
	copy(report, first16)
	return report
}
