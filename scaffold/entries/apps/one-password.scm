(library
  (entries apps one-password)
  (export one-password-tool)
  (import
    (rnrs)
    (scaffold catalog)
    (scaffold extensions app winget)
    (scaffold extensions support download))

  (doc-next
    (hidden)
    (summary "Create the 1Password apt repository installer platform."))

  (define (one-password/apt-platform)
    (let
      ((root (tool-cache-dir "1password"))
        (key-path (string-append (tool-cache-dir "1password") "/1password.asc")))
      (package/platform-argvs
        'linux
        (arr "apt-get" "curl" "dpkg" "gpg" "mkdir" "sh" "sudo" "tee")
        (arr
          (arr "mkdir" "-p" root)
          (arr
            "sudo"
            "install"
            "-d"
            "-m"
            "0755"
            "/usr/share/keyrings"
            "/etc/debsig/policies/AC2D62742012EA22"
            "/usr/share/debsig/keyrings/AC2D62742012EA22")
          (arr
            "curl"
            "-fsSL"
            "--retry"
            "3"
            "-o"
            key-path
            "https://downloads.1password.com/linux/keys/1password.asc")
          (arr
            "sudo"
            "gpg"
            "--dearmor"
            "--yes"
            "--output"
            "/usr/share/keyrings/1password-archive-keyring.gpg"
            key-path)
          (arr
            "sudo"
            "gpg"
            "--dearmor"
            "--yes"
            "--output"
            "/usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg"
            key-path)
          (arr
            "sudo"
            "curl"
            "-fsSL"
            "--retry"
            "3"
            "-o"
            "/etc/debsig/policies/AC2D62742012EA22/1password.pol"
            "https://downloads.1password.com/linux/debian/debsig/1password.pol")
          (arr
            "sh"
            "-c"
            "arch=$(dpkg --print-architecture); printf 'deb [arch=%s signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/%s stable main\\n' \"$arch\" \"$arch\" | sudo tee /etc/apt/sources.list.d/1password.list >/dev/null")
          (arr "sudo" "apt-get" "update")
          (arr "sudo" "apt-get" "install" "-y" "1password" "1password-cli")))))

  (doc-next (hidden) (summary "Create a 1Password RPM repository installer platform."))

  (define (one-password/rpm-platform installer-requires installer-argv)
    (package/platform-argvs
      'linux
      (list->vector
        (append
          (vector->list (arr "curl" "install" "sh" "sudo" "tee"))
          (vector->list installer-requires)))
      (arr
        (arr "sudo" "install" "-d" "-m" "0755" "/etc/pki/rpm-gpg" "/etc/yum.repos.d")
        (arr
          "sudo"
          "curl"
          "-fsSL"
          "--retry"
          "3"
          "-o"
          "/etc/pki/rpm-gpg/RPM-GPG-KEY-1password"
          "https://downloads.1password.com/linux/keys/1password.asc")
        (arr
          "sh"
          "-c"
          "printf '%s\\n' '[1password]' 'name=1Password Stable Channel' 'baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch' 'enabled=1' 'gpgcheck=1' 'repo_gpgcheck=1' 'gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-1password' | sudo tee /etc/yum.repos.d/1password.repo >/dev/null")
        installer-argv)))

  (doc-next
    (hidden)
    (summary "Create a macOS installer for the latest 1Password CLI zip."))

  (define (one-password/macos-platform predicate-value op-arch)
    (generated-shell-platform
      predicate-value
      (arr "curl" "ditto" "head" "install" "mkdir" "rm" "sed")
      (string-append
        (sh-set "root" (tool-cache-dir "1password"))
        (sh-set "bin_dir" "{{ bin_dir }}")
        (sh-set "op_arch" op-arch)
        "version=$(curl -fsSL --retry 3 'https://app-updates.agilebits.com/check/1/0/CLI2/en/2.0.0/N' | sed -n 's/.*\"version\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' | head -n 1)\n"
        "asset=op_darwin_${op_arch}_v${version}.zip\n"
        "archive=${root}/${asset}\n"
        "extract_dir=${root}/extract\n"
        "mkdir -p \"${root}\" \"${bin_dir}\"\n"
        "curl -fsSL --retry 3 -o \"${archive}\" \"https://cache.agilebits.com/dist/1P/op2/pkg/v${version}/${asset}\"\n"
        "rm -rf \"${extract_dir}\"\n"
        "mkdir -p \"${extract_dir}\"\n"
        "ditto -x -k \"${archive}\" \"${extract_dir}\"\n"
        "install -m 0755 \"${extract_dir}/op\" \"${bin_dir}/op\"\n")))

  (doc-next (hidden) (summary "Create the 1Password desktop and CLI application tool."))

  (define (one-password-tool)
    (tool
      "1password"
      (package
        (field
          'platforms
          (arr
            (one-password/apt-platform)
            (one-password/rpm-platform
              (arr "dnf")
              (arr "sudo" "dnf" "install" "-y" "1password" "1password-cli"))
            (one-password/rpm-platform
              (arr "rpm-ostree")
              (arr
                "sudo"
                "rpm-ostree"
                "install"
                "--idempotent"
                "-y"
                "1password"
                "1password-cli"))
            (package/platform-argvs
              'windows
              (arr "winget")
              (arr
                (winget/install-argv "AgileBits.1Password")
                (winget/install-argv "AgileBits.1Password.CLI"))
              (field 'name "1password"))
            (one-password/macos-platform (predicate 'macos 'aarch64) "arm64")
            (one-password/macos-platform (predicate 'macos 'x86_64) "amd64"))))
      (field 'bins (arr (bin/version "op" "--version")))
      (field 'paths (arr (tool/path "macos" "/Applications/1Password.app")))
      (field 'verify-after-install #f)))

  (moduledoc
    (summary "1Password application and CLI tool definition.")
    (group "Dotfiles tools")))
