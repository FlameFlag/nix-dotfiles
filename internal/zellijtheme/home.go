package zellijtheme

import (
	"errors"
	"os"
)

func HomeDir() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return "", errors.New("HOME is not set")
	}
	return home, nil
}
