package chromiumbrowser

import (
	"fmt"
	"os"
	"path/filepath"
)

func (browser Browser) installMacOS(options *InstallOptions) error {
	appDir := options.AppDir
	if appDir == "" {
		appDir = browser.MacOSAppDir
	}

	if err := os.MkdirAll(options.Root, 0o755); err != nil {
		return err
	}
	if err := os.MkdirAll(options.BinDir, 0o755); err != nil {
		return err
	}
	if stat, err := os.Stat(appDir); err != nil {
		return fmt.Errorf("find %s app directory %s: %w", browser.Name, appDir, err)
	} else if !stat.IsDir() {
		return fmt.Errorf("%s app path is not a directory: %s", browser.Name, appDir)
	}

	if err := browser.installExtensions(options); err != nil {
		return err
	}
	if err := browser.applyInstallSettings(options); err != nil {
		return err
	}
	if err := writeWrapper(
		filepath.Join(options.BinDir, browser.ExecutableName),
		filepath.Join(appDir, browser.MacOSLauncherPath),
		options,
	); err != nil {
		return err
	}
	if browser.AliasName == "" {
		return nil
	}
	return replaceSymlink(browser.ExecutableName, filepath.Join(options.BinDir, browser.AliasName))
}
