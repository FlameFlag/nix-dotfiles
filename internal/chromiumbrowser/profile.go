package chromiumbrowser

func (browser Browser) applyInstallSettings(options *InstallOptions) error {
	if !options.ApplySettings {
		return nil
	}
	profile := browser.DefaultProfileDir(options.Mode)
	if profile == "" {
		return nil
	}
	return browser.ApplyProfileSettings(ApplyOptions{
		ProfileDir:           profile,
		Settings:             options.Settings,
		CookieAutoDeleteTOML: options.CookieAutoDeleteTOML,
		SettingsSource:       options.SettingsSource,
		ExtensionIDAliases:   options.extensionIDAliases,
		GitHubToken:          true,
	})
}
