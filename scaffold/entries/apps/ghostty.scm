(library
  (entries apps ghostty)
  (export ghostty-tool)
  (import
    (rnrs)
    (scaffold catalog)
    (scaffold extensions distro pacman)
    (scaffold extensions support download))

  (doc-next (hidden) (summary "Create the official Ghostty macOS DMG installer."))

  (define (ghostty/macos-platform)
    (generated-shell-platform
      'macos
      (arr "curl" "ditto" "hdiutil" "mkdir" "rm" "sed")
      (string-append
        (sh-set "root" (tool-cache-dir "ghostty"))
        "dmg=${root}/Ghostty.dmg\n"
        "mount_dir=${root}/mount\n"
        "app_dst=/Applications/Ghostty.app\n"
        "url=$(curl -fsSL --retry 3 'https://ghostty.org/download' | sed -n 's/.*href=\"\\([^\"]*Ghostty\\.dmg\\)\".*/\\1/p' | head -n 1)\n"
        "if [ -z \"${url}\" ]; then\n"
        "  printf '%s\\n' 'ghostty: failed to discover macOS download URL' >&2\n"
        "  exit 1\n"
        "fi\n"
        "mkdir -p \"${root}\"\n"
        "curl -fsSL --retry 3 -o \"${dmg}\" \"${url}\"\n"
        "rm -rf \"${mount_dir}\"\n"
        "mkdir -p \"${mount_dir}\"\n"
        "hdiutil attach \"${dmg}\" -nobrowse -readonly -mountpoint \"${mount_dir}\"\n"
        "trap 'hdiutil detach \"${mount_dir}\" >/dev/null 2>&1 || true' EXIT\n"
        "rm -rf \"${app_dst}\"\n"
        "ditto \"${mount_dir}/Ghostty.app\" \"${app_dst}\"\n")))

  (doc-next (hidden) (summary "Create the Ghostty Fedora COPR installer platform."))

  (define (ghostty/dnf-platform)
    (package/platform-argvs
      'linux
      (arr "dnf" "sudo")
      (arr
        (arr "sudo" "dnf" "-y" "copr" "enable" "scottames/ghostty")
        (arr "sudo" "dnf" "install" "-y" "ghostty"))
      (field 'name "ghostty-dnf")))

  (doc-next
    (hidden)
    (summary "Create the Ghostty Fedora Atomic rpm-ostree installer platform."))

  (define (ghostty/rpm-ostree-platform)
    (package/platform-argvs
      'linux
      (arr "curl" "rpm-ostree" "sh" "sudo" "tee")
      (arr
        (arr
          "sh"
          "-c"
          ". /etc/os-release; curl -fsSL --retry 3 \"https://copr.fedorainfracloud.org/coprs/scottames/ghostty/repo/fedora-${VERSION_ID}/scottames-ghostty-fedora-${VERSION_ID}.repo\" | sudo tee /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:scottames:ghostty.repo >/dev/null")
        (arr "sudo" "rpm-ostree" "refresh-md")
        (arr "sudo" "rpm-ostree" "install" "--idempotent" "-y" "ghostty"))
      (field 'name "ghostty-rpm-ostree")))

  (doc-next (hidden) (summary "Create the Ghostty Alpine apk installer platform."))

  (define (ghostty/apk-platform)
    (package/platform-argvs
      'linux
      (arr "apk" "sudo")
      (arr (arr "sudo" "apk" "add" "ghostty"))
      (field 'name "ghostty-apk")))

  (doc-next (hidden) (summary "Create the Ghostty Snap installer platform."))

  (define (ghostty/snap-platform)
    (package/platform-argvs
      'linux
      (arr "snap" "sudo")
      (arr (arr "sudo" "snap" "install" "ghostty" "--classic"))
      (field 'name "ghostty-snap")))

  (doc-next (hidden) (summary "Create the Ghostty terminal tool."))

  (define (ghostty-tool)
    (tool
      "ghostty"
      (package
        (field
          'platforms
          (arr
            (pacman/package-platform "ghostty")
            (ghostty/dnf-platform)
            (ghostty/rpm-ostree-platform)
            (ghostty/apk-platform)
            (ghostty/snap-platform)
            (ghostty/macos-platform))))
      (field 'bins (arr (bin/version "ghostty" "--version")))))

  (moduledoc (summary "Ghostty terminal tool definition.") (group "Dotfiles tools")))
