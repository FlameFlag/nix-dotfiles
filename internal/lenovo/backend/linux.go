//go:build linux

package backend

import (
	"errors"
	"fmt"
	"os"
	"strings"
)

const (
	ConservationModePath = "/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode"
	dmiVendorPath        = "/sys/class/dmi/id/sys_vendor"
	dmiBoardVendorPath   = "/sys/class/dmi/id/board_vendor"
	dmiProductNamePath   = "/sys/class/dmi/id/product_name"
)

var modeValues = map[string]bool{
	"0": false,
	"1": true,
}

func IsSupportedLenovo() (bool, error) {
	lenovoMachine := false
	for _, path := range []string{dmiVendorPath, dmiBoardVendorPath, dmiProductNamePath} {
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		value := strings.ToLower(strings.TrimSpace(string(data)))
		if strings.Contains(value, "lenovo") || strings.Contains(value, "legion") {
			lenovoMachine = true
			break
		}
	}
	if !lenovoMachine {
		return false, nil
	}
	_, err := os.Stat(ConservationModePath)
	if err == nil {
		return true, nil
	}
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	if errors.Is(err, os.ErrPermission) {
		return true, nil
	}
	return false, err
}

func ReadMode() (bool, error) {
	data, err := os.ReadFile(ConservationModePath)
	if err != nil {
		return false, mapNodeError(err)
	}
	return ParseMode(strings.TrimSpace(string(data)))
}

func WriteMode(enabled bool) error {
	value := "0\n"
	if enabled {
		value = "1\n"
	}
	return mapNodeError(os.WriteFile(ConservationModePath, []byte(value), 0o644))
}

func ParseMode(value string) (bool, error) {
	mode, ok := modeValues[value]
	if !ok {
		return false, fmt.Errorf("unexpected conservation mode value: %s", value)
	}
	return mode, nil
}

func mapNodeError(err error) error {
	if err == nil {
		return nil
	}
	if errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("conservation mode sysfs node not found: %s", ConservationModePath)
	}
	if errors.Is(err, os.ErrPermission) {
		return fmt.Errorf("permission denied reading or writing conservation mode; run as root")
	}
	return err
}
