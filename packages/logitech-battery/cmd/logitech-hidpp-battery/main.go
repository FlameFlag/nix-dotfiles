package main

import (
	"encoding/binary"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/charmbracelet/log"
)

const (
	logitechVendorID = 0x046d

	hidppShortReportID = 0x10
	hidppLongReportID  = 0x11
	hidppShortSize     = 7
	hidppLongSize      = 20
	hidppMaxReadSize   = 32

	devDirect = 0xff

	featureRoot          = 0x0000
	featureDeviceName    = 0x0005
	featureBatteryStatus = 0x1000
	featureBatteryVolt   = 0x1001
	featureUnifiedBatt   = 0x1004
	featureADCMeasure    = 0x1f20
)

var nextSoftwareID atomic.Uint32

type deviceSummary struct {
	Path       string `json:"path"`
	Name       string `json:"name"`
	Kind       string `json:"kind"`
	Percentage int    `json:"percentage"`
	Charging   bool   `json:"charging"`
	State      string `json:"state,omitempty"`
}

type hidrawDevice struct {
	devnode    string
	hidrawName string
	busID      int
	vendorID   int
	productID  int
	hidName    string
	hidPhys    string
	hidUniq    string
	hidppShort bool
	hidppLong  bool
}

type hidppDevice struct {
	handle      *os.File
	devnumber   byte
	path        string
	fallback    string
	kindHint    string
	longMessage bool
	protocol    float64
	timeout     time.Duration
	features    map[uint16]byte
}

type battery struct {
	percentage int
	charging   bool
}

func main() {
	jsonOutput := flag.Bool("json", false, "emit JSON output")
	timeout := flag.Duration("timeout", time.Second, "per-request HID++ timeout")
	verbose := flag.Bool("verbose", false, "log read errors")
	flag.Parse()

	summaries := make([]deviceSummary, 0)
	for _, raw := range hidrawDevices() {
		devices, err := batterySummaries(raw, *timeout)
		if err != nil {
			if *verbose {
				log.Warn("failed to read battery summary", "device", raw.devnode, "error", err)
			}
			continue
		}
		summaries = append(summaries, devices...)
	}
	sort.SliceStable(summaries, func(i, j int) bool {
		return summaries[i].Path < summaries[j].Path
	})

	if *jsonOutput {
		encoder := json.NewEncoder(os.Stdout)
		encoder.SetEscapeHTML(false)
		if err := encoder.Encode(summaries); err != nil {
			log.Error("encode JSON", "error", err)
			os.Exit(1)
		}
		return
	}

	for _, device := range summaries {
		suffix := ""
		if device.Charging {
			suffix = " charging"
		}
		fmt.Printf("%s: %d%%%s\n", device.Name, device.Percentage, suffix)
	}
}

func hidrawDevices() []hidrawDevice {
	paths, err := filepath.Glob("/sys/class/hidraw/hidraw*")
	if err != nil {
		return nil
	}

	devices := make([]hidrawDevice, 0, len(paths))
	for _, path := range paths {
		values := readUevent(filepath.Join(path, "device", "uevent"))
		bus, vid, pid, ok := parseHIDID(values["HID_ID"])
		if !ok || vid != logitechVendorID {
			continue
		}

		info := hidrawDevice{
			devnode:    filepath.Join("/dev", filepath.Base(path)),
			hidrawName: filepath.Base(path),
			busID:      bus,
			vendorID:   vid,
			productID:  pid,
			hidName:    values["HID_NAME"],
			hidPhys:    values["HID_PHYS"],
			hidUniq:    values["HID_UNIQ"],
		}
		info.hidppShort, info.hidppLong = hidppReportSupport(filepath.Join(path, "device", "report_descriptor"))

		if isReceiver(info) {
			if info.hidppShort || info.hidppLong {
				devices = append(devices, info)
			}
			continue
		}
		if isDirectDevice(info) && (info.hidppShort || info.hidppLong) {
			devices = append(devices, info)
		}
	}

	return devices
}

func batterySummaries(raw hidrawDevice, timeout time.Duration) ([]deviceSummary, error) {
	handle, err := os.OpenFile(raw.devnode, os.O_RDWR|syscall.O_SYNC, 0)
	if err != nil {
		return nil, err
	}
	defer handle.Close()

	if isReceiver(raw) {
		return receiverBatterySummaries(handle, raw, timeout), nil
	}
	return directBatterySummary(handle, raw, timeout)
}

func receiverBatterySummaries(handle *os.File, raw hidrawDevice, timeout time.Duration) []deviceSummary {
	summaries := make([]deviceSummary, 0)
	for devnumber := byte(1); devnumber <= 6; devnumber++ {
		device := hidppDevice{
			handle:      handle,
			devnumber:   devnumber,
			path:        fmt.Sprintf("hidpp:%s:%d", raw.devnode, devnumber),
			fallback:    fmt.Sprintf("Logitech Device %d", devnumber),
			kindHint:    "Device",
			longMessage: raw.hidppLong,
			timeout:     timeout,
			features:    make(map[uint16]byte),
		}
		protocol, err := device.ping()
		if err != nil || protocol < 2.0 {
			continue
		}
		device.protocol = protocol
		if summary, ok := device.summary(); ok {
			summaries = append(summaries, summary)
		}
	}
	return summaries
}

func directBatterySummary(handle *os.File, raw hidrawDevice, timeout time.Duration) ([]deviceSummary, error) {
	device := hidppDevice{
		handle:      handle,
		devnumber:   devDirect,
		path:        "hidpp:" + raw.devnode,
		fallback:    fallbackName(raw),
		kindHint:    kindFromHIDName(raw.hidName),
		longMessage: raw.hidppLong || raw.busID == 0x0005,
		timeout:     timeout,
		features:    make(map[uint16]byte),
	}
	protocol, err := device.ping()
	if err != nil || protocol < 2.0 {
		return nil, err
	}
	device.protocol = protocol
	if summary, ok := device.summary(); ok {
		return []deviceSummary{summary}, nil
	}
	return nil, nil
}

func (device *hidppDevice) summary() (deviceSummary, bool) {
	batt, ok := device.battery()
	if !ok {
		return deviceSummary{}, false
	}

	name := device.name()
	if name == "" {
		name = device.fallback
	}
	kind := device.kind()
	if kind == "" {
		kind = device.kindHint
	}

	return deviceSummary{
		Path:       device.path,
		Name:       name,
		Kind:       kind,
		Percentage: batt.percentage,
		Charging:   batt.charging,
		State:      "online",
	}, true
}

func (device *hidppDevice) name() string {
	index, ok := device.featureIndex(featureDeviceName)
	if !ok {
		return ""
	}
	reply, err := device.featureRequestWithRetry(index, 0x00, nil)
	if err != nil || len(reply) == 0 || reply[0] == 0 {
		return ""
	}

	nameLength := int(reply[0])
	name := make([]byte, 0, nameLength)
	for len(name) < nameLength {
		reply, err = device.featureRequestWithRetry(index, 0x10, []byte{byte(len(name))})
		if err != nil || len(reply) == 0 {
			return ""
		}
		remaining := nameLength - len(name)
		if remaining > len(reply) {
			remaining = len(reply)
		}
		name = append(name, reply[:remaining]...)
	}
	return strings.TrimSpace(string(name))
}

func (device *hidppDevice) kind() string {
	index, ok := device.featureIndex(featureDeviceName)
	if !ok {
		return ""
	}
	reply, err := device.featureRequestWithRetry(index, 0x20, nil)
	if err != nil || len(reply) == 0 {
		return ""
	}
	switch reply[0] {
	case 0x00:
		return "Keyboard"
	case 0x03:
		return "Mouse"
	case 0x04:
		return "Touchpad"
	case 0x05:
		return "Mouse"
	case 0x06:
		return "Presenter"
	default:
		return "Device"
	}
}

func (device *hidppDevice) battery() (battery, bool) {
	queries := []struct {
		feature  uint16
		function byte
		parse    func([]byte) (battery, bool)
	}{
		{featureBatteryStatus, 0x00, parseBatteryStatus},
		{featureBatteryVolt, 0x00, parseBatteryVoltage},
		{featureUnifiedBatt, 0x10, parseUnifiedBattery},
		{featureADCMeasure, 0x00, parseADCMeasurement},
	}
	for _, query := range queries {
		index, ok := device.featureIndex(query.feature)
		if !ok {
			continue
		}
		reply, err := device.featureRequest(index, query.function, nil)
		if err != nil {
			continue
		}
		if batt, ok := query.parse(reply); ok {
			return batt, true
		}
	}
	return battery{}, false
}

func (device *hidppDevice) featureIndex(feature uint16) (byte, bool) {
	if index, ok := device.features[feature]; ok {
		return index, index != 0
	}

	params := []byte{byte(feature >> 8), byte(feature)}
	reply, err := device.request(featureRoot, params)
	if err != nil || len(reply) < 1 || reply[0] == 0 {
		device.features[feature] = 0
		return 0, false
	}
	device.features[feature] = reply[0]
	return reply[0], true
}

func (device *hidppDevice) featureRequest(index byte, function byte, params []byte) ([]byte, error) {
	requestID := uint16(index)<<8 | uint16(function)
	return device.request(requestID, params)
}

func (device *hidppDevice) featureRequestWithRetry(index byte, function byte, params []byte) ([]byte, error) {
	reply, err := device.featureRequest(index, function, params)
	if err == nil {
		return reply, nil
	}
	return device.featureRequest(index, function, params)
}

func (device *hidppDevice) ping() (float64, error) {
	mark := byte(time.Now().UnixNano())
	requestID := withSoftwareID(0x0010)
	data := []byte{byte(requestID >> 8), byte(requestID), 0x00, 0x00, mark}
	if err := device.flush(); err != nil {
		return 0, err
	}
	if err := device.write(data); err != nil {
		return 0, err
	}

	deadline := time.Now().Add(device.timeout)
	for time.Now().Before(deadline) {
		reply, err := device.read(time.Until(deadline))
		if err != nil {
			return 0, err
		}
		if len(reply.data) < 5 || !matchingDevice(reply.devnumber, device.devnumber) {
			continue
		}
		if reply.data[0] == data[0] && reply.data[1] == data[1] && reply.data[4] == mark {
			return float64(reply.data[2]) + float64(reply.data[3])/10.0, nil
		}
		if reply.reportID == hidppShortReportID && len(reply.data) >= 4 && reply.data[0] == 0x8f && reply.data[1] == data[0] && reply.data[2] == data[1] {
			return 0, fmt.Errorf("ping error 0x%02x", reply.data[3])
		}
	}
	return 0, errors.New("ping timeout")
}

func (device *hidppDevice) request(requestID uint16, params []byte) ([]byte, error) {
	if requestID < 0x8000 {
		requestID = withSoftwareID(requestID)
	}
	data := []byte{byte(requestID >> 8), byte(requestID)}
	data = append(data, params...)

	if err := device.flush(); err != nil {
		return nil, err
	}
	if err := device.write(data); err != nil {
		return nil, err
	}

	deadline := time.Now().Add(device.timeout)
	for time.Now().Before(deadline) {
		reply, err := device.read(time.Until(deadline))
		if err != nil {
			return nil, err
		}
		if len(reply.data) < 2 || !matchingDevice(reply.devnumber, device.devnumber) {
			continue
		}
		if len(reply.data) >= 4 && reply.reportID == hidppShortReportID && reply.data[0] == 0x8f && reply.data[1] == data[0] && reply.data[2] == data[1] {
			return nil, fmt.Errorf("hid++ 1.0 error 0x%02x", reply.data[3])
		}
		if len(reply.data) >= 4 && reply.data[0] == 0xff && reply.data[1] == data[0] && reply.data[2] == data[1] {
			return nil, fmt.Errorf("hid++ 2.0 error 0x%02x", reply.data[3])
		}
		if reply.data[0] == data[0] && reply.data[1] == data[1] {
			return reply.data[2:], nil
		}
	}
	return nil, fmt.Errorf("request 0x%04x timeout", requestID)
}

func (device *hidppDevice) write(data []byte) error {
	var packet []byte
	if device.longMessage || len(data) > hidppShortSize-2 || data[0] == 0x82 {
		packet = make([]byte, hidppLongSize)
		packet[0] = hidppLongReportID
		packet[1] = device.devnumber
		copy(packet[2:], data)
	} else {
		packet = make([]byte, hidppShortSize)
		packet[0] = hidppShortReportID
		packet[1] = device.devnumber
		copy(packet[2:], data)
	}
	written, err := device.handle.Write(packet)
	if err != nil {
		return err
	}
	if written != len(packet) {
		return io.ErrShortWrite
	}
	return nil
}

type hidppReply struct {
	reportID  byte
	devnumber byte
	data      []byte
}

func (device *hidppDevice) flush() error {
	for {
		_, err := device.read(0)
		if errors.Is(err, errReadTimeout) {
			return nil
		}
		if err != nil {
			return err
		}
	}
}

var errReadTimeout = errors.New("read timeout")

func (device *hidppDevice) read(timeout time.Duration) (hidppReply, error) {
	fd := int(device.handle.Fd())
	var readfds syscall.FdSet
	var exceptfds syscall.FdSet
	fdSet(fd, &readfds)
	fdSet(fd, &exceptfds)

	var tv syscall.Timeval
	timeoutPtr := (*syscall.Timeval)(nil)
	if timeout >= 0 {
		if timeout < 0 {
			timeout = 0
		}
		tv = syscall.NsecToTimeval(timeout.Nanoseconds())
		timeoutPtr = &tv
	}

	ready, err := syscall.Select(fd+1, &readfds, nil, &exceptfds, timeoutPtr)
	if err != nil {
		return hidppReply{}, err
	}
	if ready == 0 {
		return hidppReply{}, errReadTimeout
	}
	if fdIsSet(fd, &exceptfds) {
		return hidppReply{}, syscall.EIO
	}
	if !fdIsSet(fd, &readfds) {
		return hidppReply{}, errReadTimeout
	}

	buffer := make([]byte, hidppMaxReadSize)
	n, err := device.handle.Read(buffer)
	if err != nil {
		return hidppReply{}, err
	}
	if n < 2 {
		return hidppReply{}, errReadTimeout
	}
	buffer = buffer[:n]
	switch buffer[0] {
	case hidppShortReportID:
		if n != hidppShortSize {
			return hidppReply{}, nil
		}
	case hidppLongReportID:
		if n != hidppLongSize {
			return hidppReply{}, nil
		}
	default:
		return hidppReply{}, nil
	}
	return hidppReply{reportID: buffer[0], devnumber: buffer[1], data: buffer[2:]}, nil
}

func fdSet(fd int, set *syscall.FdSet) {
	set.Bits[fd/64] |= 1 << (uint(fd) % 64)
}

func fdIsSet(fd int, set *syscall.FdSet) bool {
	return set.Bits[fd/64]&(1<<(uint(fd)%64)) != 0
}

func withSoftwareID(requestID uint16) uint16 {
	id := byte(nextSoftwareID.Add(1)&0x07) | 0x08
	return (requestID & 0xfff0) | uint16(id)
}

func matchingDevice(replyDev byte, requestDev byte) bool {
	return replyDev == requestDev || replyDev == requestDev^0xff
}

func parseBatteryStatus(report []byte) (battery, bool) {
	if len(report) < 3 {
		return battery{}, false
	}
	percentage := int(report[0])
	if percentage == 0 {
		percentage = percentageFromStatus(report[2])
	}
	return normalizedBattery(percentage, chargingStatus(report[2]))
}

func parseUnifiedBattery(report []byte) (battery, bool) {
	if len(report) < 4 {
		return battery{}, false
	}
	percentage := int(report[0])
	if percentage == 0 {
		percentage = percentageFromUnifiedLevel(report[1])
	}
	return normalizedBattery(percentage, chargingStatus(report[2]))
}

func parseBatteryVoltage(report []byte) (battery, bool) {
	if len(report) < 3 {
		return battery{}, false
	}
	voltage := int(binary.BigEndian.Uint16(report[:2]))
	percentage := estimateBatteryPercentage(voltage)
	flags := report[2]
	charging := flags&(1<<7) != 0
	return normalizedBattery(percentage, charging)
}

func parseADCMeasurement(report []byte) (battery, bool) {
	if len(report) < 3 || report[2]&0x01 == 0 {
		return battery{}, false
	}
	voltage := int(binary.BigEndian.Uint16(report[:2]))
	return normalizedBattery(estimateBatteryPercentage(voltage), report[2]&0x02 != 0)
}

func normalizedBattery(percentage int, charging bool) (battery, bool) {
	if percentage < 0 || percentage > 100 {
		return battery{}, false
	}
	return battery{percentage: percentage, charging: charging}, true
}

func percentageFromStatus(status byte) int {
	switch status {
	case 0x03:
		return 100
	case 0x02, 0x01:
		return 50
	case 0x04:
		return 20
	default:
		return 0
	}
}

func percentageFromUnifiedLevel(level byte) int {
	switch level {
	case 8:
		return 100
	case 4:
		return 50
	case 2:
		return 20
	case 1:
		return 5
	default:
		return 0
	}
}

func chargingStatus(status byte) bool {
	return status == 0x01 || status == 0x02 || status == 0x03 || status == 0x04
}

func estimateBatteryPercentage(voltage int) int {
	points := []struct {
		mv      int
		percent int
	}{
		{4186, 100},
		{4067, 90},
		{3989, 80},
		{3922, 70},
		{3859, 60},
		{3811, 50},
		{3778, 40},
		{3751, 30},
		{3717, 20},
		{3671, 10},
		{3646, 5},
		{3579, 2},
		{3500, 0},
	}
	if voltage >= points[0].mv {
		return points[0].percent
	}
	if voltage <= points[len(points)-1].mv {
		return points[len(points)-1].percent
	}
	for i := 0; i < len(points)-1; i++ {
		high := points[i]
		low := points[i+1]
		if voltage >= low.mv && voltage <= high.mv {
			percent := float64(low.percent) + float64(high.percent-low.percent)*float64(voltage-low.mv)/float64(high.mv-low.mv)
			return int(math.Round(percent))
		}
	}
	return 0
}

func isReceiver(device hidrawDevice) bool {
	return device.busID == 0x0003 && device.productID >= 0xc500 && device.productID <= 0xc5ff
}

func isDirectDevice(device hidrawDevice) bool {
	switch device.busID {
	case 0x0003:
		return (device.productID >= 0xc07d && device.productID <= 0xc094) ||
			(device.productID >= 0xc32b && device.productID <= 0xc344)
	case 0x0005:
		return (device.productID >= 0xb012 && device.productID <= 0xb0ff) ||
			(device.productID >= 0xb317 && device.productID <= 0xb3ff)
	default:
		return false
	}
}

func fallbackName(device hidrawDevice) string {
	if strings.TrimSpace(device.hidName) != "" {
		return strings.TrimSpace(device.hidName)
	}
	return "Logitech Device"
}

func kindFromHIDName(name string) string {
	normalized := strings.ToLower(name)
	switch {
	case strings.Contains(normalized, "keyboard"), strings.Contains(normalized, "keys"):
		return "Keyboard"
	case strings.Contains(normalized, "mouse"), strings.Contains(normalized, "trackball"):
		return "Mouse"
	default:
		return "Device"
	}
}

func readUevent(path string) map[string]string {
	content, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	values := make(map[string]string)
	for _, line := range strings.Split(string(content), "\n") {
		key, value, ok := strings.Cut(line, "=")
		if ok {
			values[key] = value
		}
	}
	return values
}

func parseHIDID(hidID string) (int, int, int, bool) {
	parts := strings.Split(hidID, ":")
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

func hidppReportSupport(path string) (bool, bool) {
	descriptor, err := os.ReadFile(path)
	if err != nil {
		return false, false
	}
	inputSizes := inputReportSizes(descriptor)
	return inputSizes[hidppShortReportID] == 6*8, inputSizes[hidppLongReportID] == 19*8
}

func inputReportSizes(descriptor []byte) map[byte]int {
	sizes := make(map[byte]int)
	var reportID byte
	var reportSize int
	var reportCount int

	for i := 0; i < len(descriptor); {
		prefix := descriptor[i]
		i++
		if prefix == 0xfe {
			if i+2 > len(descriptor) {
				break
			}
			size := int(descriptor[i])
			i += 2 + size
			continue
		}

		sizeCode := int(prefix & 0x03)
		size := sizeCode
		if sizeCode == 3 {
			size = 4
		}
		if i+size > len(descriptor) {
			break
		}
		value := itemValue(descriptor[i : i+size])
		i += size

		itemType := (prefix >> 2) & 0x03
		tag := (prefix >> 4) & 0x0f
		if itemType == 1 {
			switch tag {
			case 7:
				reportSize = value
			case 8:
				reportID = byte(value)
			case 9:
				reportCount = value
			}
			continue
		}
		if itemType == 0 && tag == 8 && reportID != 0 && reportSize > 0 && reportCount > 0 {
			bits := reportSize * reportCount
			if bits > sizes[reportID] {
				sizes[reportID] = bits
			}
		}
	}
	return sizes
}

func itemValue(data []byte) int {
	value := 0
	for i, b := range data {
		value |= int(b) << (8 * i)
	}
	return value
}
