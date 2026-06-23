//go:build !linux

package backend

import "errors"

func IsSupportedLenovo() (bool, error) {
	return false, nil
}

func ReadMode() (bool, error) {
	return false, errors.New("unsupported operating system")
}

func WriteMode(_ bool) error {
	return errors.New("unsupported operating system")
}

func ParseMode(_ string) (bool, error) {
	return false, errors.New("unsupported operating system")
}
