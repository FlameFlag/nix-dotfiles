package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/charmbracelet/log"
)

const (
	vendorID             = 0x1038
	headsetOffline       = 0x01
	headsetCableCharging = 0x02
	chargerSlotPresent   = 0x04
	headsetRadioOnline   = 0x08
	headsetStatusByte    = 15
	chargerBatteryByte   = 12
	chargerStatusByte    = 14
	stateAvailable       = "available"
	stateCharging        = "charging"
	stateOnline          = "online"
)

var (
	// USB product IDs are the transmitter/base-station IDs. SteelSeries GG stores
	// these as packed VID/PID values; for example 0x1038225d is the Xbox White
	// transmitter and 0x10382260 is its receiver/headset side. Receiver-only IDs
	// are intentionally not listed because this battery query is handled by the
	// transmitter's control interface.
	knownTransmitterProductIDs = map[int]string{
		0x12e0: "SteelSeries Arctis Nova Pro Wireless",
		0x12e5: "SteelSeries Arctis Nova Pro Wireless Xbox",
		0x225d: "SteelSeries Arctis Nova Pro Wireless Xbox White",
	}

	// SteelSeries legacy HID command:
	//   report ID 0x06, command 0xb0, padded to the device's 31-byte output report.
	// GG's renderer asks its local engine for read_battery_status/read_connection_status,
	// but HeadsetControl and live hidraw traces both show this direct packet as the
	// underlying lightweight poll we need. The response echoes 0x06 0xb0, then
	// includes the headset battery/status.
	batteryRequest = append([]byte{0x06, 0xb0}, make([]byte, 29)...)
)

type deviceSummary struct {
	Path       string `json:"path"`
	Name       string `json:"name"`
	Kind       string `json:"kind"`
	Percentage int    `json:"percentage"`
	Charging   bool   `json:"charging"`
	State      string `json:"state,omitempty"`
}

type batteryReport struct {
	headsetRaw        int
	headsetPercentage int
	headsetCharging   bool
	headsetOnline     bool
	chargerRaw        int
	chargerPercentage int
	chargerCharging   bool
	chargerAvailable  bool
}

type hidrawDevice struct {
	devnode   string
	productID int
	uevent    map[string]string
}

func main() {
	jsonOutput := flag.Bool("json", false, "emit JSON output")
	timeout := flag.Duration("timeout", 2*time.Second, "battery query timeout")
	verbose := flag.Bool("verbose", false, "log read errors")
	flag.Parse()

	devices := make([]deviceSummary, 0)
	for _, device := range hidrawDevices() {
		summaries, err := batterySummaries(device, *timeout)
		if err != nil {
			if *verbose {
				log.Warn("failed to read battery summary", "device", device.devnode, "error", err)
			}
			continue
		}
		devices = append(devices, summaries...)
	}

	if *jsonOutput {
		encoder := json.NewEncoder(os.Stdout)
		encoder.SetEscapeHTML(false)
		if err := encoder.Encode(devices); err != nil {
			log.Error("encode JSON", "error", err)
			os.Exit(1)
		}
		return
	}

	for _, device := range devices {
		suffix := ""
		switch device.State {
		case stateCharging:
			suffix = " charging"
		case stateAvailable:
			suffix = " available"
		default:
			if device.Charging {
				suffix = " charging"
			}
		}
		fmt.Printf("%s: %d%%%s\n", device.Name, device.Percentage, suffix)
	}
}

func hidrawDevices() []hidrawDevice {
	paths, err := filepath.Glob("/sys/class/hidraw/hidraw*")
	if err != nil {
		return nil
	}

	var devices []hidrawDevice
	for _, path := range paths {
		values := readUevent(filepath.Join(path, "device", "uevent"))
		bus, vid, pid, ok := parseHIDID(values["HID_ID"])
		if !ok || bus != 0x0003 || vid != vendorID {
			continue
		}
		if _, ok := knownTransmitterProductIDs[pid]; !ok {
			continue
		}

		// The Nova Pro exposes more than one hidraw node with the same VID/PID.
		// The useful one advertises vendor-defined report 0x06 with input,
		// output, and feature reports. Older kernels or permissions may block
		// report_descriptor reads, so keep the observed Linux interface number
		// as a fallback rather than as the primary selector.
		hasBatteryReport, checkedReportDescriptor := exposesBatteryReport(path)
		if checkedReportDescriptor {
			if !hasBatteryReport {
				continue
			}
		} else if phys := values["HID_PHYS"]; phys != "" && !strings.HasSuffix(phys, "/input4") {
			continue
		}

		devices = append(devices, hidrawDevice{
			devnode:   filepath.Join("/dev", filepath.Base(path)),
			productID: pid,
			uevent:    values,
		})
	}
	return devices
}

func exposesBatteryReport(hidrawPath string) (bool, bool) {
	descriptor, err := os.ReadFile(filepath.Join(hidrawPath, "device", "report_descriptor"))
	if err != nil || len(descriptor) == 0 {
		return false, false
	}

	hasInput, hasOutput, hasFeature := steelSeriesVendorReportCapabilities(descriptor, 0x06)
	return hasInput && hasOutput && hasFeature, true
}

// Parse just enough of the HID report descriptor to answer:
// "does report ID 0x06 on SteelSeries' vendor usage page support the report
// kinds we need?" This avoids hard-coding /input4 when Linux already exposes
// the protocol shape in sysfs.
func steelSeriesVendorReportCapabilities(descriptor []byte, targetReportID byte) (bool, bool, bool) {
	const (
		mainItem   = 0
		globalItem = 1

		inputTag     = 8
		outputTag    = 9
		featureTag   = 11
		usagePageTag = 0
		reportIDTag  = 8
	)

	var usagePage uint32
	var reportID byte
	var hasInput, hasOutput, hasFeature bool

	for offset := 0; offset < len(descriptor); {
		prefix := descriptor[offset]
		offset++

		// Long HID items are rare here and not meaningful for this check.
		if prefix == 0xfe {
			if offset+1 >= len(descriptor) {
				break
			}
			size := int(descriptor[offset])
			offset += 2 + size
			continue
		}

		size := int(prefix & 0x03)
		if size == 3 {
			size = 4
		}
		if offset+size > len(descriptor) {
			break
		}

		itemType := (prefix >> 2) & 0x03
		tag := prefix >> 4
		value := hidItemValue(descriptor[offset : offset+size])
		offset += size

		switch itemType {
		case globalItem:
			switch tag {
			case usagePageTag:
				usagePage = value
			case reportIDTag:
				reportID = byte(value)
			}
		case mainItem:
			// 0xffc0 is the vendor-defined usage page used by this SteelSeries
			// control interface. Main items then tell us whether the current
			// report ID has input, output, and feature reports.
			if usagePage != 0xffc0 || reportID != targetReportID {
				continue
			}
			switch tag {
			case inputTag:
				hasInput = true
			case outputTag:
				hasOutput = true
			case featureTag:
				hasFeature = true
			}
		}
	}

	return hasInput, hasOutput, hasFeature
}

func hidItemValue(data []byte) uint32 {
	var value uint32
	for i, b := range data {
		value |= uint32(b) << (8 * i)
	}
	return value
}

func readUevent(path string) map[string]string {
	values := make(map[string]string)
	data, err := os.ReadFile(path)
	if err != nil {
		return values
	}
	for _, line := range strings.Split(string(data), "\n") {
		key, value, ok := strings.Cut(line, "=")
		if ok && key != "" && value != "" {
			values[key] = value
		}
	}
	return values
}

func parseHIDID(value string) (int, int, int, bool) {
	parts := strings.Split(value, ":")
	if len(parts) != 3 {
		return 0, 0, 0, false
	}

	bus, err := strconv.ParseInt(parts[0], 16, 32)
	if err != nil {
		return 0, 0, 0, false
	}
	vid, err := strconv.ParseInt(parts[1], 16, 32)
	if err != nil {
		return 0, 0, 0, false
	}
	pid, err := strconv.ParseInt(parts[2], 16, 32)
	if err != nil {
		return 0, 0, 0, false
	}
	return int(bus), int(vid), int(pid), true
}

func batterySummaries(device hidrawDevice, timeout time.Duration) ([]deviceSummary, error) {
	report, err := readBattery(device.devnode, timeout)
	if err != nil {
		return nil, err
	}
	parsed, err := parseBatteryReport(report)
	if err != nil {
		return nil, err
	}
	return batterySummariesFromParsed(device, parsed), nil
}

func batterySummariesFromParsed(device hidrawDevice, parsed batteryReport) []deviceSummary {
	name := knownTransmitterProductIDs[device.productID]
	if name == "" {
		name = device.uevent["HID_NAME"]
	}

	devices := make([]deviceSummary, 0, 2)
	if parsed.headsetOnline {
		devices = append(devices, deviceSummary{
			Path:       "steelseries-arctis:" + device.devnode,
			Name:       name,
			Kind:       "Headset",
			Percentage: parsed.headsetPercentage,
			Charging:   parsed.headsetCharging,
			State:      headsetStateName(parsed),
		})
	}
	return devices
}

func headsetStateName(parsed batteryReport) string {
	if parsed.headsetCharging {
		return stateCharging
	}
	return stateOnline
}

func parseBatteryReport(report []byte) (batteryReport, error) {
	if len(report) < 16 {
		return batteryReport{}, fmt.Errorf("short battery report: %d bytes", len(report))
	}
	if report[0] != 0x06 || report[1] != 0xb0 {
		return batteryReport{}, fmt.Errorf("unexpected battery report echo: %02x %02x", report[0], report[1])
	}

	// Response byte 6 is a coarse battery bucket from 0..8. SteelSeries GG's UI
	// displays the same effective buckets as 0, 12, 25, 37, 50, 62, 75, 87, 100.
	headsetRaw := clampBatteryBucket(int(report[6]))
	headsetState := report[headsetStatusByte]
	// Response byte 15 is the direct HID headset state. HeadsetControl maps
	// 0x01 to offline, 0x02 to cable charging, and 0x08 to online; GG's
	// higher-level UI labels the surrounding states as PAIRED_CONNECTED,
	// PAIRED_NOT_CONNECTED, PLUGGED_IN_CHARGING, and PLUGGED_IN_NOT_CHARGING.
	headsetCharging := headsetState == headsetCableCharging

	// SteelSeries GG's Nova Pro Wireless UI reads both headset_battery_level and
	// charger_battery_level from the same read_battery_status call. The direct
	// 0x06/0xb0 response carries that second 0..8 bucket at byte 12, with an
	// adjacent status byte at byte 14. On this host it has stayed at 63% even
	// when no physical spare battery exists, so we parse it for diagnostics but
	// do not expose it as a GNOME battery row.
	chargerRaw := clampBatteryBucket(int(report[chargerBatteryByte]))
	chargerState := report[chargerStatusByte]

	return batteryReport{
		headsetRaw:        headsetRaw,
		headsetPercentage: batteryBucketPercentage(headsetRaw),
		headsetCharging:   headsetCharging,
		headsetOnline:     knownAvailableState(headsetState),
		chargerRaw:        chargerRaw,
		chargerPercentage: batteryBucketPercentage(chargerRaw),
		chargerCharging:   chargerState == headsetCableCharging,
		chargerAvailable:  knownAvailableState(chargerState) || chargerState == chargerSlotPresent,
	}, nil
}

func knownAvailableState(state byte) bool {
	return state == headsetCableCharging || state == headsetRadioOnline
}

func clampBatteryBucket(rawLevel int) int {
	if rawLevel < 0 {
		return 0
	}
	if rawLevel > 8 {
		return 8
	}
	return rawLevel
}

func batteryBucketPercentage(rawLevel int) int {
	return (clampBatteryBucket(rawLevel)*100 + 4) / 8
}

func readBattery(devnode string, timeout time.Duration) ([]byte, error) {
	fd, err := syscall.Open(devnode, syscall.O_RDWR|syscall.O_NONBLOCK, 0)
	if err != nil {
		return nil, err
	}
	defer syscall.Close(fd)

	if _, err := syscall.Write(fd, batteryRequest); err != nil {
		return nil, err
	}

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		remaining := time.Until(deadline)
		timeoutValue := syscall.NsecToTimeval(remaining.Nanoseconds())
		readSet := &syscall.FdSet{}
		fdSet(fd, readSet)

		ready, err := syscall.Select(fd+1, readSet, nil, nil, &timeoutValue)
		if err != nil {
			if err == syscall.EINTR {
				continue
			}
			return nil, err
		}
		if ready == 0 {
			break
		}

		buffer := make([]byte, 128)
		n, err := syscall.Read(fd, buffer)
		if err != nil {
			if err == syscall.EAGAIN || err == syscall.EWOULDBLOCK {
				continue
			}
			return nil, err
		}
		report := buffer[:n]
		// hidraw can surface unrelated input reports; wait for the command echo
		// that identifies the battery response.
		if len(report) >= 16 && report[0] == 0x06 && report[1] == 0xb0 {
			return report, nil
		}
	}

	return nil, os.ErrDeadlineExceeded
}

func fdSet(fd int, set *syscall.FdSet) {
	set.Bits[fd/64] |= 1 << (fd % 64)
}
