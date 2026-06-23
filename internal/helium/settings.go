package helium

import (
	"bytes"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"

	lzstring "github.com/daku10/go-lz-string"
	"github.com/syndtr/goleveldb/leveldb"
)

const refinedGitHubID = "hlepfoohegkhhmjieoechaddaejaokhf"

type ApplyOptions struct {
	ProfileDir         string
	Settings           []string
	SettingsSource     []SettingsSource
	ExtensionIDAliases map[string]string
	GitHubToken        bool
	TokenFunc          func() string
}

type SettingsSource struct {
	Name string
	Data []byte
}

type settingsFile struct {
	Local []extensionSettings `json:"local"`
	Sync  []extensionSettings `json:"sync"`
}

type extensionSettings struct {
	ID     string         `json:"id"`
	Values map[string]any `json:"values"`
}

const defaultSettingsDir = "settings/default"

//go:embed settings/default/*.json
var defaultSettingsFS embed.FS

func DefaultSettingsSources() ([]SettingsSource, error) {
	entries, err := fs.ReadDir(defaultSettingsFS, defaultSettingsDir)
	if err != nil {
		return nil, fmt.Errorf("read embedded default Helium extension settings: %w", err)
	}
	sources := make([]SettingsSource, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".json") {
			continue
		}
		path := defaultSettingsDir + "/" + entry.Name()
		data, err := defaultSettingsFS.ReadFile(path)
		if err != nil {
			return nil, fmt.Errorf(
				"read embedded default Helium extension settings file %s: %w",
				path,
				err,
			)
		}
		sources = append(sources, SettingsSource{Name: "embedded " + path, Data: data})
	}
	if len(sources) == 0 {
		return nil, fmt.Errorf("embedded default Helium extension settings are empty")
	}
	return sources, nil
}

func ApplyExtensionSettings(options ApplyOptions) error {
	sources := slices.Clone(options.SettingsSource)
	for _, path := range options.Settings {
		data, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("read settings file %s: %w", path, err)
		}
		sources = append(sources, SettingsSource{Name: path, Data: data})
	}

	for _, source := range sources {
		var settings settingsFile
		decoder := json.NewDecoder(bytes.NewReader(source.Data))
		decoder.UseNumber()
		if err := decoder.Decode(&settings); err != nil {
			return fmt.Errorf("parse settings file %s: %w", source.Name, err)
		}
		for _, entry := range settings.Local {
			entry.ID = resolveExtensionID(options.ExtensionIDAliases, entry.ID)
			if err := writeStorageValues(
				options.ProfileDir,
				"Local Extension Settings",
				entry,
			); err != nil {
				return err
			}
		}
		for _, entry := range settings.Sync {
			entry.ID = resolveExtensionID(options.ExtensionIDAliases, entry.ID)
			if err := writeStorageValues(
				options.ProfileDir,
				"Sync Extension Settings",
				entry,
			); err != nil {
				return err
			}
		}
	}

	if !options.GitHubToken {
		return nil
	}
	tokenFunc := options.TokenFunc
	if tokenFunc == nil {
		tokenFunc = func() string {
			command := exec.Command("gh", "auth", "token")
			output, err := command.Output()
			if err == nil {
				return strings.TrimSpace(string(output))
			}
			fmt.Fprintln(
				os.Stderr,
				"helium-browser: gh auth token failed; skipping Refined GitHub token setup",
			)
			return ""
		}
	}
	token := tokenFunc()
	if token == "" {
		return nil
	}

	return withStorage(
		options.ProfileDir,
		"Sync Extension Settings",
		refinedGitHubID,
		func(db *leveldb.DB) error {
			raw, err := db.Get([]byte("options"), nil)
			refinedOptions := map[string]any{}
			if err == nil {
				var compressed string
				if err := json.Unmarshal(raw, &compressed); err != nil {
					return fmt.Errorf("parse stored Refined GitHub options: %w", err)
				}
				decompressed, err := lzstring.DecompressFromEncodedURIComponent(compressed)
				if err != nil {
					return fmt.Errorf("decompress Refined GitHub options: %w", err)
				}
				if decompressed != "" {
					decoder := json.NewDecoder(strings.NewReader(decompressed))
					decoder.UseNumber()
					if err := decoder.Decode(&refinedOptions); err != nil {
						return fmt.Errorf("parse Refined GitHub options: %w", err)
					}
				}
			} else if !errors.Is(err, leveldb.ErrNotFound) {
				return fmt.Errorf("read Refined GitHub options: %w", err)
			}
			refinedOptions["personalToken"] = token

			encoded, err := json.Marshal(refinedOptions)
			if err != nil {
				return fmt.Errorf("encode Refined GitHub options: %w", err)
			}
			compressed, err := lzstring.CompressToEncodedURIComponent(string(encoded))
			if err != nil {
				return fmt.Errorf("compress Refined GitHub options: %w", err)
			}
			stored, err := json.Marshal(compressed)
			if err != nil {
				return fmt.Errorf("encode compressed Refined GitHub options: %w", err)
			}
			return db.Put([]byte("options"), stored, nil)
		},
	)
}

func resolveExtensionID(aliases map[string]string, id string) string {
	if alias := aliases[id]; alias != "" {
		return alias
	}
	return id
}

func ApplyBrowserProfilePreferences(
	profileDir string,
	extensionIDAliases map[string]string,
	flags string,
) error {
	preferencesPath := filepath.Join(profileDir, "Preferences")
	preferences := map[string]any{}
	data, err := os.ReadFile(preferencesPath)
	if err == nil && len(bytes.TrimSpace(data)) > 0 {
		decoder := json.NewDecoder(bytes.NewReader(data))
		decoder.UseNumber()
		if err := decoder.Decode(&preferences); err != nil {
			return fmt.Errorf("parse Helium Preferences: %w", err)
		}
	} else if err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("read Helium Preferences: %w", err)
	}

	applyThemePreferencesFromFlags(preferences, flags)
	cleanupStaleCookieAutoDeleteExtensions(preferences, extensionIDAliases)

	if err := os.MkdirAll(profileDir, 0o755); err != nil {
		return err
	}
	encoded, err := json.MarshalIndent(preferences, "", "  ")
	if err != nil {
		return fmt.Errorf("encode Helium Preferences: %w", err)
	}
	encoded = append(encoded, '\n')
	if err := os.WriteFile(preferencesPath, encoded, 0o600); err != nil {
		return fmt.Errorf("write Helium Preferences: %w", err)
	}
	return nil
}

func applyThemePreferencesFromFlags(preferences map[string]any, flags string) {
	userColor, ok := userColorFromFlags(flags)
	if !ok {
		return
	}
	browser := nestedPreferenceObject(preferences, "browser")
	theme := nestedPreferenceObject(browser, "theme")
	theme["color_variant2"] = 1
	theme["is_grayscale2"] = false
	theme["user_color2"] = userColor

	extensions := nestedPreferenceObject(preferences, "extensions")
	extensionTheme := nestedPreferenceObject(extensions, "theme")
	extensionTheme["id"] = "user_color_theme_id"
}

func userColorFromFlags(flags string) (int64, bool) {
	for _, field := range strings.Fields(flags) {
		value, ok := strings.CutPrefix(field, "--set-user-color=")
		if !ok {
			continue
		}
		parts := strings.Split(value, ",")
		if len(parts) != 3 {
			return 0, false
		}
		var rgb [3]int64
		for i, part := range parts {
			parsed, err := strconv.ParseInt(part, 10, 64)
			if err != nil || parsed < 0 || parsed > 255 {
				return 0, false
			}
			rgb[i] = parsed
		}
		argb := int64(0xff000000 | rgb[0]<<16 | rgb[1]<<8 | rgb[2])
		if argb >= 1<<31 {
			argb -= 1 << 32
		}
		return argb, true
	}
	return 0, false
}

func cleanupStaleCookieAutoDeleteExtensions(
	preferences map[string]any,
	extensionIDAliases map[string]string,
) {
	currentID := resolveExtensionID(extensionIDAliases, "hebmefdjnehapihcomeennjpdjghcpdn")
	extensions, ok := preferences["extensions"].(map[string]any)
	if !ok {
		return
	}
	settings, ok := extensions["settings"].(map[string]any)
	if !ok {
		return
	}
	for id, raw := range settings {
		if id == currentID {
			continue
		}
		entry, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		path, _ := entry["path"].(string)
		if strings.HasSuffix(path, "/extensions/unpacked/hebmefdjnehapihcomeennjpdjghcpdn") {
			delete(settings, id)
		}
	}
}

func nestedPreferenceObject(root map[string]any, key string) map[string]any {
	value, ok := root[key].(map[string]any)
	if !ok {
		value = map[string]any{}
		root[key] = value
	}
	return value
}

func writeStorageValues(profileDir, area string, entry extensionSettings) error {
	return withStorage(profileDir, area, entry.ID, func(db *leveldb.DB) error {
		batch := new(leveldb.Batch)
		for key, value := range entry.Values {
			encoded, err := json.Marshal(value)
			if err != nil {
				return fmt.Errorf("encode %s/%s/%s: %w", area, entry.ID, key, err)
			}
			batch.Put([]byte(key), encoded)
		}
		return db.Write(batch, nil)
	})
}

func withStorage(profileDir, area, extensionID string, operation func(*leveldb.DB) error) error {
	path := filepath.Join(profileDir, area, extensionID)
	if err := os.MkdirAll(path, 0o755); err != nil {
		return fmt.Errorf("create storage directory %s: %w", path, err)
	}
	db, err := leveldb.OpenFile(path, nil)
	if err != nil {
		return fmt.Errorf("open storage %s: %w", path, err)
	}
	defer db.Close()
	return operation(db)
}
