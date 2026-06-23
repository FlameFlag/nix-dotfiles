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

	"github.com/FlameFlag/nix-dotfiles/internal/common/archiveutil"
	"github.com/FlameFlag/nix-dotfiles/internal/common/envx"
	"github.com/FlameFlag/nix-dotfiles/internal/common/fileutil"
	"github.com/FlameFlag/nix-dotfiles/internal/common/httpx"
	"github.com/FlameFlag/nix-dotfiles/internal/common/userdirs"
	"github.com/FlameFlag/nix-dotfiles/internal/helium/extensions"
	"github.com/buildkite/shellwords"
	"github.com/google/renameio/v2/maybe"
	"github.com/otiai10/copy"
)

const (
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

	extraWrapperFlags  []string
	extensionIDAliases map[string]string
}

type environment struct {
	Home string `env:"HOME"`
}

func Install(options InstallOptions) error {
	switch options.Mode {
	case "macos":
		var heliumArch string
		switch runtime.GOARCH {
		case "arm64":
			heliumArch = "arm64"
		case "amd64":
			heliumArch = "x86_64"
		default:
			return fmt.Errorf("unsupported macOS architecture: %s", runtime.GOARCH)
		}
		version, err := latestVersion("imputnet/helium-macos")
		if err != nil {
			return err
		}
		appDst := "/Applications/Helium.app"
		dmg := filepath.Join(options.Root, fmt.Sprintf("helium_%s_%s-macos.dmg", version, heliumArch))
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
				"https://github.com/imputnet/helium-macos/releases/download/%s/helium_%s_%s-macos.dmg",
				version,
				version,
				heliumArch,
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
		version, err := latestVersion("imputnet/helium-linux")
		if err != nil {
			return err
		}

		archive := filepath.Join(
			options.Root,
			fmt.Sprintf("helium-%s-%s_linux.tar.xz", version, heliumArch),
		)
		extractDir := filepath.Join(options.Root, "extract")
		appDir := filepath.Join(options.Root, "app")
		versionFile := filepath.Join(appDir, ".helium-version")
		home := envx.MustParse[environment]().Home
		dataHome := userdirs.DataHome(home)

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
		currentVersion, _ := os.ReadFile(versionFile)
		if strings.TrimSpace(string(currentVersion)) != version {
			if _, err := os.Stat(archive); errors.Is(err, os.ErrNotExist) {
				fmt.Fprintf(os.Stderr, "helium-browser: downloading %s\n", filepath.Base(archive))
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
			} else if err != nil {
				return err
			} else {
				fmt.Fprintf(os.Stderr, "helium-browser: using cached %s\n", filepath.Base(archive))
			}
			fmt.Fprintln(os.Stderr, "helium-browser: extracting application archive")
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
			fmt.Fprintln(os.Stderr, "helium-browser: installing application payload")
			if err := fileutil.MoveDir(payload, appDir); err != nil {
				return fmt.Errorf("move Helium payload: %w", err)
			}
			if err := os.Remove(
				filepath.Join(appDir, "libqt5_shim.so"),
			); err != nil &&
				!errors.Is(err, os.ErrNotExist) {
				return err
			}
			if err := setWrapperVersionExtra(filepath.Join(appDir, "helium-wrapper")); err != nil {
				return err
			}
			if _, err := fileutil.WriteTextIfChanged(versionFile, version+"\n"); err != nil {
				return err
			}
			if err := os.RemoveAll(extractDir); err != nil {
				return err
			}
		} else {
			fmt.Fprintf(os.Stderr, "helium-browser: application %s is already installed\n", version)
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
		return nil
	default:
		return fmt.Errorf("unsupported installer mode: %s", options.Mode)
	}
}

func setWrapperVersionExtra(path string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	info, err := os.Stat(path)
	if err != nil {
		return err
	}
	lines := strings.Split(string(data), "\n")
	for i, line := range lines {
		if strings.HasPrefix(line, "CHROME_VERSION_EXTRA=") {
			lines[i] = "CHROME_VERSION_EXTRA=ansible"
			return os.WriteFile(path, []byte(strings.Join(lines, "\n")), info.Mode().Perm())
		}
	}
	return nil
}

func latestVersion(repository string) (string, error) {
	client := httpx.RetryableClient(30 * time.Second)
	request, err := http.NewRequest(
		http.MethodHead,
		fmt.Sprintf("https://github.com/%s/releases/latest", repository),
		nil,
	)
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

func resolveDownloadURL(rawURL string) (string, error) {
	client := httpx.RetryableClient(30 * time.Second)
	request, err := http.NewRequest(http.MethodHead, rawURL, nil)
	if err != nil {
		return "", err
	}
	response, err := client.Do(request)
	if err != nil {
		return "", err
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode > 299 {
		return "", fmt.Errorf("HEAD %s: %s", rawURL, response.Status)
	}
	return response.Request.URL.String(), nil
}

func installExtensions(options *InstallOptions) error {
	result, err := extensions.Install(extensions.Options{
		Mode:     options.Mode,
		Root:     options.Root,
		Download: downloadFile,
		Resolve:  resolveDownloadURL,
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
	aliases, err := unpackedExtensionIDAliases(options.Root)
	if err != nil {
		return err
	}
	options.extensionIDAliases = aliases
	return nil
}

func unpackedExtensionIDAliases(root string) (map[string]string, error) {
	catalog, err := extensions.LoadCatalog()
	if err != nil {
		return nil, err
	}
	aliases := map[string]string{}
	for _, extension := range catalog.ZIP {
		if !extension.LoadUnpacked {
			continue
		}
		path := filepath.Join(root, "extensions/unpacked", extension.ID)
		aliases[extension.ID] = extensions.UnpackedExtensionID(path)
	}
	return aliases, nil
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
			envx.MustParse[environment]().Home,
			"Library/Application Support/net.imput.helium/Default",
		)
	case "linux":
		profile = filepath.Join(userdirs.ConfigHome(envx.MustParse[environment]().Home), "net.imput.helium/Default")
	}
	if err := ApplyExtensionSettings(ApplyOptions{
		ProfileDir:         profile,
		Settings:           options.Settings,
		SettingsSource:     settings,
		ExtensionIDAliases: options.extensionIDAliases,
		GitHubToken:        true,
	}); err != nil {
		return err
	}
	return ApplyBrowserProfilePreferences(profile, options.extensionIDAliases, options.Flags)
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
