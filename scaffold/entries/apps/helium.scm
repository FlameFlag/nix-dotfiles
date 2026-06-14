(library
  (entries apps helium)
  (export helium-tool)
  (import
    (rnrs)
    (scaffold catalog)
    (scaffold extensions support download)
    (scaffold workspace))

  (doc-next (hidden) (summary "Common Helium command-line flags."))

  (define helium/common-flags
    "--extension-mime-request-handling=always-prompt-for-install")

  (doc-next (hidden) (summary "Linux Helium command-line flags."))

  (define helium/linux-flags
    (string-append
      "--enable-logging=stderr "
      "--enable-features=ForceEnableWebGpuInterop,ReduceOpsTaskSplitting,TouchpadOverscrollHistoryNavigation,VaapiVideoDecoder,VaapiVideoEncoder,BrowsingTopics,InterestGroupStorage "
      "--disable-features=ExtensionManifestV2Unsupported,ExtensionManifestV2Disabled "
      "--ignore-gpu-blocklist "
      "--enable-wayland-ime "
      "--wayland-text-input-version=3 "
      helium/common-flags))

  (doc-next (hidden) (summary "Absolute path to the Helium installer script."))

  (define helium/install-script
    (workspace/path "scaffold" "scripts" "install-helium-browser.sh"))

  (doc-next (hidden) (summary "Create a Helium installer platform."))

  (define (helium/platform predicate-value mode flags requires)
    (package/platform
      predicate-value
      requires
      (arr
        "bash"
        helium/install-script
        mode
        (tool-cache-dir "helium-browser")
        "{{ bin_dir }}"
        flags)))

  (doc-next (hidden) (summary "Create the Helium macOS DMG installer platform."))

  (define (helium/macos-platform)
    (helium/platform
      (predicate 'macos 'aarch64)
      "macos"
      helium/common-flags
      (arr
        "bash"
        "chmod"
        "cp"
        "curl"
        "ditto"
        "hdiutil"
        "ln"
        "mkdir"
        "bun"
        "rm"
        "sed"
        "sops"
        "unzip")))

  (doc-next (hidden) (summary "Create the Helium non-NixOS Linux tarball installer."))

  (define (helium/linux-platform)
    (helium/platform
      'linux
      "linux"
      helium/linux-flags
      (arr
        "bash"
        "chmod"
        "cp"
        "curl"
        "ln"
        "mkdir"
        "bun"
        "rm"
        "sed"
        "sops"
        "tar"
        "uname"
        "unzip")))

  (doc-next (hidden) (summary "Create the Helium browser tool."))

  (define (helium-tool)
    (tool
      "helium-browser"
      (package (field 'platforms (arr (helium/linux-platform) (helium/macos-platform))))
      (field 'bins (arr (bin/version "helium-browser" "--version")))
      (field 'paths (arr (tool/path 'macos "/Applications/Helium.app")))
      (field 'verify-after-install #f)
      (meta
        (description "Private web browser based on ungoogled-chromium.")
        (home-page "https://github.com/imputnet/helium-macos")
        (license "GPL-3.0-only")
        (main-program "helium-browser")
        (source "https://github.com/imputnet/helium-macos"))))

  (moduledoc (summary "Helium browser tool definition.") (group "Dotfiles tools")))
