package chromiumbrowser

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"

	"github.com/pelletier/go-toml/v2"
)

const defaultCookieAutoDeleteID = "hebmefdjnehapihcomeennjpdjghcpdn"

type cookieAutoDeleteConfig struct {
	Settings map[string]any                  `toml:"settings"`
	Lists    map[string]cookieAutoDeleteList `toml:"lists"`
	Allow    []cookieAutoDeleteExpression    `toml:"allow"`
	Deny     []cookieAutoDeleteExpression    `toml:"deny"`
	Rules    []cookieAutoDeleteRule          `toml:"rules"`
	Stores   []cookieAutoDeleteStore         `toml:"store"`
}

type cookieAutoDeleteList struct {
	Allow []string `toml:"allow"`
	Deny  []string `toml:"deny"`
}

type cookieAutoDeleteRule struct {
	StoreID           string   `toml:"store"`
	List              string   `toml:"list"`
	Match             string   `toml:"match"`
	ID                string   `toml:"id"`
	CleanAllCookies   *bool    `toml:"clean_all_cookies"`
	CleanLocalStorage *bool    `toml:"clean_local_storage"`
	CleanSiteData     []string `toml:"clean_site_data"`
	CookieNames       []string `toml:"cookie_names"`
}

type cookieAutoDeleteStore struct {
	ID    string                       `toml:"id"`
	Allow []cookieAutoDeleteExpression `toml:"allow"`
	Deny  []cookieAutoDeleteExpression `toml:"deny"`
}

type cookieAutoDeleteExpression struct {
	StoreID           string   `toml:"store_id"`
	Match             string   `toml:"match"`
	ID                string   `toml:"id"`
	CleanAllCookies   *bool    `toml:"clean_all_cookies"`
	CleanLocalStorage *bool    `toml:"clean_local_storage"`
	CleanSiteData     []string `toml:"clean_site_data"`
	CookieNames       []string `toml:"cookie_names"`
}

func CookieAutoDeleteSettingsSourceFromTOML(name string, data []byte) (SettingsSource, error) {
	return CookieAutoDeleteSettingsSourceForExtensionFromTOML(name, data, defaultCookieAutoDeleteID)
}

func CookieAutoDeleteSettingsSourceForExtensionFromTOML(
	name string,
	data []byte,
	extensionID string,
) (SettingsSource, error) {
	if extensionID == "" {
		extensionID = defaultCookieAutoDeleteID
	}
	var config cookieAutoDeleteConfig
	if err := toml.Unmarshal(data, &config); err != nil {
		return SettingsSource{}, fmt.Errorf("parse Cookie AutoDelete TOML file %s: %w", name, err)
	}
	settings := map[string]any{}
	for key, value := range config.Settings {
		settings[key] = map[string]any{
			"name":  key,
			"value": value,
		}
	}
	if _, ok := settings["manualNotifications"]; !ok {
		settings["manualNotifications"] = settingObject("manualNotifications", false)
	}
	if _, ok := settings["showNotificationAfterCleanup"]; !ok {
		settings["showNotificationAfterCleanup"] = settingObject("showNotificationAfterCleanup", false)
	}

	lists := map[string][]map[string]any{}
	hasDeny := false
	for storeID, list := range config.Lists {
		if storeID == "" {
			storeID = "default"
		}
		for _, match := range list.Allow {
			entry, err := cookieAutoDeleteEntry(
				storeID,
				"WHITE",
				cookieAutoDeleteExpression{Match: match},
			)
			if err != nil {
				return SettingsSource{}, err
			}
			lists[storeID] = append(lists[storeID], entry)
		}
		for _, match := range list.Deny {
			entry, err := cookieAutoDeleteEntry(
				storeID,
				"GREY",
				cookieAutoDeleteExpression{Match: match},
			)
			if err != nil {
				return SettingsSource{}, err
			}
			lists[storeID] = append(lists[storeID], entry)
			hasDeny = true
		}
	}
	for _, rule := range config.Rules {
		listType, err := cookieAutoDeleteListType(rule.List)
		if err != nil {
			return SettingsSource{}, err
		}
		storeID := rule.StoreID
		if storeID == "" {
			storeID = "default"
		}
		entry, err := cookieAutoDeleteEntry(storeID, listType, cookieAutoDeleteExpression{
			Match:             rule.Match,
			ID:                rule.ID,
			CleanAllCookies:   rule.CleanAllCookies,
			CleanLocalStorage: rule.CleanLocalStorage,
			CleanSiteData:     rule.CleanSiteData,
			CookieNames:       rule.CookieNames,
		})
		if err != nil {
			return SettingsSource{}, err
		}
		lists[storeID] = append(lists[storeID], entry)
		if listType == "GREY" {
			hasDeny = true
		}
	}
	for _, expression := range config.Allow {
		storeID := expression.StoreID
		if storeID == "" {
			storeID = "default"
		}
		entry, err := cookieAutoDeleteEntry(storeID, "WHITE", expression)
		if err != nil {
			return SettingsSource{}, err
		}
		lists[storeID] = append(lists[storeID], entry)
	}
	for _, expression := range config.Deny {
		storeID := expression.StoreID
		if storeID == "" {
			storeID = "default"
		}
		entry, err := cookieAutoDeleteEntry(storeID, "GREY", expression)
		if err != nil {
			return SettingsSource{}, err
		}
		lists[storeID] = append(lists[storeID], entry)
		hasDeny = true
	}
	for _, store := range config.Stores {
		storeID := store.ID
		if storeID == "" {
			storeID = "default"
		}
		for _, expression := range store.Allow {
			entry, err := cookieAutoDeleteEntry(storeID, "WHITE", expression)
			if err != nil {
				return SettingsSource{}, err
			}
			lists[storeID] = append(lists[storeID], entry)
		}
		for _, expression := range store.Deny {
			entry, err := cookieAutoDeleteEntry(storeID, "GREY", expression)
			if err != nil {
				return SettingsSource{}, err
			}
			lists[storeID] = append(lists[storeID], entry)
			hasDeny = true
		}
	}
	if hasDeny {
		settings["enableGreyListCleanup"] = settingObject("enableGreyListCleanup", true)
	}

	state, err := json.Marshal(map[string]any{
		"activityLog":                 []any{},
		"cache":                       map[string]any{},
		"cookieDeletedCounterSession": 0,
		"cookieDeletedCounterTotal":   0,
		"lists":                       lists,
		"settings":                    settings,
	})
	if err != nil {
		return SettingsSource{}, fmt.Errorf("encode Cookie AutoDelete state: %w", err)
	}
	settingsJSON, err := json.Marshal(settingsFile{
		Local: []extensionSettings{
			{
				ID: extensionID,
				Values: map[string]any{
					"state": string(state),
				},
			},
		},
	})
	if err != nil {
		return SettingsSource{}, fmt.Errorf("encode Cookie AutoDelete settings: %w", err)
	}
	return SettingsSource{Name: name, Data: settingsJSON}, nil
}

func settingObject(name string, value any) map[string]any {
	return map[string]any{"name": name, "value": value}
}

func cookieAutoDeleteListType(list string) (string, error) {
	switch list {
	case "allow", "white", "WHITE":
		return "WHITE", nil
	case "deny", "grey", "gray", "GREY":
		return "GREY", nil
	default:
		return "", fmt.Errorf("unsupported Cookie AutoDelete rule list: %s", list)
	}
}

func cookieAutoDeleteEntry(
	storeID string,
	listType string,
	expression cookieAutoDeleteExpression,
) (map[string]any, error) {
	if expression.Match == "" {
		return nil, fmt.Errorf("cookie AutoDelete %s entry in store %s is missing match", listType, storeID)
	}
	id := expression.ID
	if id == "" {
		id = deterministicCookieAutoDeleteID(storeID, listType, expression.Match)
	}
	entry := map[string]any{
		"cleanSiteData": expression.CleanSiteData,
		"cookieNames":   expression.CookieNames,
		"expression":    expression.Match,
		"id":            id,
		"listType":      listType,
		"storeId":       storeID,
	}
	if expression.CleanAllCookies != nil {
		entry["cleanAllCookies"] = *expression.CleanAllCookies
	}
	if expression.CleanLocalStorage != nil {
		entry["cleanLocalStorage"] = *expression.CleanLocalStorage
	}
	return entry, nil
}

func deterministicCookieAutoDeleteID(storeID, listType, expression string) string {
	sum := sha256.Sum256([]byte(storeID + "\x00" + listType + "\x00" + expression))
	return "cad-" + hex.EncodeToString(sum[:8])
}
