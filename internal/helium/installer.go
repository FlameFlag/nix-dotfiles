package helium

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"time"

	"github.com/buildkite/shellwords"
	"github.com/euvlok/nix-dotfiles/internal/common/archiveutil"
	"github.com/euvlok/nix-dotfiles/internal/common/fileutil"
	"github.com/euvlok/nix-dotfiles/internal/common/httpx"
	"github.com/euvlok/nix-dotfiles/internal/common/userdirs"
	"github.com/euvlok/nix-dotfiles/internal/helium/extensions"
	"github.com/google/renameio/v2/maybe"
	"github.com/otiai10/copy"
)

const (
	gitHubLatestReleaseURL   = "https://github.com/imputnet/helium-macos/releases/latest"
	releasesPathSegment      = "releases"
	latestPathSegment        = "latest"
	privateCookieSettingsKey = `["helium-cookie-autodelete-settings"]`
)

type InstallOptions struct {
	Mode          string
	Root          string
	BinDir        string
	Flags         string
	Settings      []string
	SecretsPath   string
	ApplySettings bool

	extraWrapperFlags []string
}

func Install(options InstallOptions) error {
	switch options.Mode {
	case "macos":
		version, err := latestVersion()
		if err != nil {
			return err
		}
		appDst := "/Applications/Helium.app"
		dmg := filepath.Join(options.Root, fmt.Sprintf("helium_%s_arm64-macos.dmg", version))
		mountDir := filepath.Join(options.Root, "mount")

		if err := os.MkdirAll(options.Root, 0o755); err != nil {
			return err
		}
		if err := os.MkdirAll(options.BinDir, 0o755); err != nil {
			return err
		}
		if err := downloadFile(
			dmg,
			fmt.Sprintf(
				"https://github.com/imputnet/helium-macos/releases/download/%s/helium_%s_arm64-macos.dmg",
				version,
				version,
			),
		); err != nil {
			return err
		}
		if err := os.RemoveAll(mountDir); err != nil {
			return err
		}
		if err := os.MkdirAll(mountDir, 0o755); err != nil {
			return err
		}
		if err := run(
			"hdiutil",
			"attach",
			dmg,
			"-nobrowse",
			"-readonly",
			"-mountpoint",
			mountDir,
		); err != nil {
			return err
		}
		defer func() {
			_ = run("hdiutil", "detach", mountDir)
		}()

		if err := os.RemoveAll(appDst); err != nil {
			return err
		}
		if err := run("ditto", filepath.Join(mountDir, "Helium.app"), appDst); err != nil {
			return err
		}

		if err := installExtensions(&options); err != nil {
			return err
		}
		if err := applyInstallSettings(&options); err != nil {
			return err
		}
		if err := writeWrapper(
			filepath.Join(options.BinDir, "helium-browser"),
			filepath.Join(appDst, "Contents/MacOS/Helium"),
			&options,
		); err != nil {
			return err
		}
		return replaceSymlink("helium-browser", filepath.Join(options.BinDir, "helium"))
	case "linux":
		nixos, err := isNixOS()
		if err != nil {
			return err
		}
		if nixos {
			fmt.Fprintln(
				os.Stderr,
				"helium-browser: NixOS host detected; install is managed by the NixOS system closure",
			)
			return nil
		}

		var heliumArch string
		switch runtime.GOARCH {
		case "arm64":
			heliumArch = "arm64"
		case "amd64":
			heliumArch = "x86_64"
		default:
			return fmt.Errorf("unsupported Linux architecture: %s", runtime.GOARCH)
		}
		version, err := latestVersion()
		if err != nil {
			return err
		}

		archive := filepath.Join(
			options.Root,
			fmt.Sprintf("helium-%s-%s_linux.tar.xz", version, heliumArch),
		)
		extractDir := filepath.Join(options.Root, "extract")
		appDir := filepath.Join(options.Root, "app")
		dataHome := userdirs.DataHome(os.Getenv("HOME"))

		for _, dir := range []string{
			options.Root,
			options.BinDir,
			filepath.Join(dataHome, "applications"),
			filepath.Join(dataHome, "icons/hicolor/256x256/apps"),
		} {
			if err := os.MkdirAll(dir, 0o755); err != nil {
				return err
			}
		}
		if err := downloadFile(
			archive,
			fmt.Sprintf(
				"https://github.com/imputnet/helium-linux/releases/download/%s/helium-%s-%s_linux.tar.xz",
				version,
				version,
				heliumArch,
			),
		); err != nil {
			return err
		}
		if err := os.RemoveAll(extractDir); err != nil {
			return err
		}
		if err := os.RemoveAll(appDir); err != nil {
			return err
		}
		if err := os.MkdirAll(extractDir, 0o755); err != nil {
			return err
		}
		file, err := os.Open(archive)
		if err != nil {
			return err
		}
		if err := archiveutil.ExtractTarXz(context.Background(), file, extractDir); err != nil {
			_ = file.Close()
			return err
		}
		if err := file.Close(); err != nil {
			return err
		}

		entries, err := os.ReadDir(extractDir)
		if err != nil {
			return err
		}
		payload := ""
		for _, entry := range entries {
			if entry.IsDir() {
				payload = filepath.Join(extractDir, entry.Name())
				break
			}
		}
		if payload == "" {
			return errors.New("extracted archive did not contain an application directory")
		}
		if err := copy.Copy(payload, appDir); err != nil {
			return fmt.Errorf("copy Helium payload: %w", err)
		}
		if err := os.Remove(
			filepath.Join(appDir, "libqt5_shim.so"),
		); err != nil &&
			!errors.Is(err, os.ErrNotExist) {
			return err
		}

		if err := installExtensions(&options); err != nil {
			return err
		}
		if err := applyInstallSettings(&options); err != nil {
			return err
		}
		if err := writeWrapper(
			filepath.Join(options.BinDir, "helium-browser"),
			filepath.Join(appDir, "helium-wrapper"),
			&options,
		); err != nil {
			return err
		}
		if err := replaceSymlink(
			"helium-browser",
			filepath.Join(options.BinDir, "helium"),
		); err != nil {
			return err
		}

		desktopData, err := os.ReadFile(filepath.Join(appDir, "helium.desktop"))
		if err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
		if err == nil {
			executable := filepath.Join(options.BinDir, "helium-browser")
			text := string(desktopData)
			text = strings.ReplaceAll(text, "Exec=helium %U", "Exec="+executable+" %U")
			text = strings.ReplaceAll(
				text,
				"Exec=helium --incognito",
				"Exec="+executable+" --incognito",
			)
			text = strings.ReplaceAll(text, "Exec=helium\n", "Exec="+executable+"\n")
			if _, err := fileutil.WriteTextIfChanged(
				filepath.Join(dataHome, "applications/helium-browser.desktop"),
				text,
			); err != nil {
				return err
			}
		}

		iconSource := filepath.Join(appDir, "product_logo_256.png")
		if _, err := os.Stat(iconSource); err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		} else if err == nil {
			if err := copy.Copy(
				iconSource,
				filepath.Join(dataHome, "icons/hicolor/256x256/apps/helium.png"),
			); err != nil {
				return err
			}
		}
		return os.RemoveAll(extractDir)
	default:
		return fmt.Errorf("unsupported installer mode: %s", options.Mode)
	}
}

func latestVersion() (string, error) {
	client := httpx.RetryableClient(30 * time.Second)
	request, err := http.NewRequest(http.MethodHead, gitHubLatestReleaseURL, nil)
	if err != nil {
		return "", err
	}
	response, err := client.Do(request)
	if err != nil {
		return "", err
	}
	defer response.Body.Close()
	version := filepath.Base(response.Request.URL.Path)
	missingVersion := version == ""
	releaseIndexPath := version == releasesPathSegment
	latestAliasPath := version == latestPathSegment
	if missingVersion || releaseIndexPath || latestAliasPath {
		return "", errors.New("failed to discover latest Helium version")
	}
	return version, nil
}

func downloadFile(path, url string) error {
	return (&httpx.Client{HTTP: httpx.RetryableClient(30 * time.Second)}).DownloadFile(url, path)
}

func installExtensions(options *InstallOptions) error {
	result, err := extensions.Install(extensions.Options{
		Mode:     options.Mode,
		Root:     options.Root,
		Download: downloadFile,
		Unzip: func(zipPath, dst string) error {
			return archiveutil.ExtractZipFile(context.Background(), zipPath, dst)
		},
	})
	if err != nil {
		return err
	}
	for _, path := range result.LoadExtensionPaths {
		options.extraWrapperFlags = append(options.extraWrapperFlags, "--load-extension="+path)
	}
	return nil
}

func applyInstallSettings(options *InstallOptions) error {
	if !options.ApplySettings {
		return nil
	}
	settings, err := DefaultSettingsSources()
	if err != nil {
		return err
	}
	if options.SecretsPath != "" {
		var privateSettings []byte
		if _, err = os.Stat(options.SecretsPath); err == nil {
			privateSettings, err = exec.Command("sops", "-d", "--extract", privateCookieSettingsKey, options.SecretsPath).
				Output()
		}
		if err == nil {
			settings = append(
				settings,
				SettingsSource{Name: options.SecretsPath, Data: privateSettings},
			)
		} else if !errors.Is(err, os.ErrNotExist) && !errors.Is(err, exec.ErrNotFound) {
			fmt.Fprintf(
				os.Stderr,
				"helium-browser: failed to decrypt private Cookie AutoDelete settings; continuing with public settings: %v\n",
				err,
			)
		}
	}
	profile := ""
	switch options.Mode {
	case "macos":
		profile = filepath.Join(
			os.Getenv("HOME"),
			"Library/Application Support/net.imput.helium/Default",
		)
	case "linux":
		profile = filepath.Join(userdirs.ConfigHome(os.Getenv("HOME")), "net.imput.helium/Default")
	}
	return ApplyExtensionSettings(ApplyOptions{
		ProfileDir:     profile,
		Settings:       options.Settings,
		SettingsSource: settings,
		GitHubToken:    true,
	})
}

func writeWrapper(target, launcher string, options *InstallOptions) error {
	var flags []string
	if options.Flags != "" {
		var err error
		flags, err = shellwords.SplitPosix(options.Flags)
		if err != nil {
			return err
		}
	}
	args := slices.Concat([]string{launcher}, flags, options.extraWrapperFlags)
	var content strings.Builder
	content.WriteString("#!/usr/bin/env bash\nset -Eeuo pipefail\nexec")
	for _, arg := range args {
		content.WriteByte(' ')
		content.WriteString(shellwords.QuotePosix(arg))
	}
	content.WriteString(" \"$@\"\n")
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		return err
	}
	return maybe.WriteFile(target, []byte(content.String()), 0o755)
}

func replaceSymlink(oldname, newname string) error {
	if err := os.Remove(newname); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return os.Symlink(oldname, newname)
}

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
