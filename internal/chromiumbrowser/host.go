package chromiumbrowser

import (
	"errors"
	"os"
	"os/exec"
	"strings"
)

func isNixOS() (bool, error) {
	data, err := os.ReadFile("/etc/os-release")
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return false, nil
		}
		return false, err
	}
	for line := range strings.SplitSeq(string(data), "\n") {
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		value = strings.Trim(value, `"`)
		if key == "ID" && value == "nixos" {
			return true, nil
		}
		if key == "ID_LIKE" {
			for item := range strings.FieldsSeq(value) {
				if item == "nixos" {
					return true, nil
				}
			}
		}
	}
	return false, nil
}

func run(name string, args ...string) error {
	command := exec.Command(name, args...)
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	return command.Run()
}
