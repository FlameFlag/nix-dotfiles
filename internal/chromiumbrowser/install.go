package chromiumbrowser

import "fmt"

type InstallOptions struct {
	Mode                 string
	Root                 string
	AppDir               string
	BinDir               string
	Flags                string
	Settings             []string
	SettingsSource       []SettingsSource
	CookieAutoDeleteTOML []string
	ApplySettings        bool

	extraWrapperFlags  []string
	extensionIDAliases map[string]string
}

func (browser Browser) Install(options InstallOptions) error {
	normalized, err := browser.normalized()
	if err != nil {
		return err
	}
	switch options.Mode {
	case "macos":
		return normalized.installMacOS(&options)
	case "linux":
		return normalized.installLinux(&options)
	default:
		return fmt.Errorf("unsupported installer mode: %s", options.Mode)
	}
}
