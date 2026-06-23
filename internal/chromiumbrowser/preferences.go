package chromiumbrowser

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const (
	PreferencesFilename = "Preferences"
)

type PreferencePatch func(map[string]any)

func (browser Browser) ApplyBrowserPreferenceSettings(profileDir string) error {
	preferences, err := readPreferences(profileDir)
	if err != nil {
		return err
	}

	for _, patch := range browser.PreferencePatches {
		patch(preferences)
	}

	return writePreferences(profileDir, preferences)
}

func readPreferences(profileDir string) (map[string]any, error) {
	path := filepath.Join(profileDir, PreferencesFilename)
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return map[string]any{}, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read Chromium Preferences: %w", err)
	}
	if len(bytes.TrimSpace(data)) == 0 {
		return map[string]any{}, nil
	}

	preferences := map[string]any{}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.UseNumber()
	if err := decoder.Decode(&preferences); err != nil {
		return nil, fmt.Errorf("parse Chromium Preferences: %w", err)
	}
	return preferences, nil
}

func writePreferences(profileDir string, preferences map[string]any) error {
	if err := os.MkdirAll(profileDir, 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(preferences, "", "  ")
	if err != nil {
		return fmt.Errorf("encode Chromium Preferences: %w", err)
	}
	data = append(data, '\n')
	if err := os.WriteFile(filepath.Join(profileDir, PreferencesFilename), data, 0o600); err != nil {
		return fmt.Errorf("write Chromium Preferences: %w", err)
	}
	return nil
}

func NestedObject(root map[string]any, dottedPath string) map[string]any {
	current := root
	parts := strings.Split(dottedPath, ".")
	for _, part := range parts {
		next, ok := current[part].(map[string]any)
		if !ok {
			next = map[string]any{}
			current[part] = next
		}
		current = next
	}
	return current
}

func SetNestedValue(root map[string]any, dottedPath string, value any) {
	index := strings.LastIndex(dottedPath, ".")
	if index < 0 {
		root[dottedPath] = value
		return
	}
	parentPath := dottedPath[:index]
	key := dottedPath[index+1:]
	NestedObject(root, parentPath)[key] = value
}

func EnsureAcceleratorAdded(customAccelerators map[string]any, commandID, accelerator string) {
	command, ok := customAccelerators[commandID].(map[string]any)
	if !ok {
		command = map[string]any{}
		customAccelerators[commandID] = command
	}

	added, ok := command["added"].([]any)
	if !ok {
		added = []any{}
	}
	for _, existing := range added {
		if existing == accelerator {
			command["added"] = added
			return
		}
	}
	command["added"] = append(added, accelerator)
}
