(library
  (entries apps raycast)
  (export raycast-tool)
  (import (rnrs) (scaffold catalog) (scaffold extensions support download))

  (doc-next (hidden) (summary "Create the Raycast Beta macOS DMG installer."))

  (define (raycast/macos-platform)
    (generated-shell-platform
      (predicate 'macos 'aarch64)
      (arr "curl" "ditto" "hdiutil" "mkdir" "rm" "sed")
      (string-append
        (sh-set "root" (tool-cache-dir "raycast-beta"))
        "dmg=${root}/Raycast_Beta.dmg\n"
        "mount_dir=${root}/mount\n"
        "app_dst='/Applications/Raycast Beta.app'\n"
        "url=$(curl -fsSL --retry 3 'https://www.raycast.com/new' | sed -n 's|.*href=\"\\(https://x-r2\\.raycast-releases\\.com/[^\"]*\\.dmg\\)\".*|\\1|p' | head -n 1)\n"
        "if [ -z \"${url}\" ]; then\n"
        "  printf '%s\\n' 'raycast: failed to discover Raycast Beta download URL' >&2\n"
        "  exit 1\n"
        "fi\n"
        "mkdir -p \"${root}\"\n"
        "curl -fsSL --retry 3 -o \"${dmg}\" \"${url}\"\n"
        "rm -rf \"${mount_dir}\"\n"
        "mkdir -p \"${mount_dir}\"\n"
        "hdiutil attach \"${dmg}\" -nobrowse -readonly -mountpoint \"${mount_dir}\"\n"
        "trap 'hdiutil detach \"${mount_dir}\" >/dev/null 2>&1 || true' EXIT\n"
        "rm -rf \"${app_dst}\"\n"
        "ditto \"${mount_dir}/Raycast Beta.app\" \"${app_dst}\"\n")))

  (doc-next (hidden) (summary "Create the Raycast Beta launcher tool."))

  (define (raycast-tool)
    (tool
      "raycast"
      (package (field 'platforms (arr (raycast/macos-platform))))
      (field 'paths (arr (tool/path 'macos "/Applications/Raycast Beta.app")))
      (field 'verify-after-install #f)
      (meta
        (description "Raycast v2 public beta launcher.")
        (home-page "https://www.raycast.com/new"))))

  (moduledoc (summary "Raycast Beta tool definition.") (group "Dotfiles tools")))
