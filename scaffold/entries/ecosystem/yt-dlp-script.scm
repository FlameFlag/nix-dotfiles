(library
  (entries ecosystem yt-dlp-script)
  (export yt-dlp-script-tool)
  (import (rnrs) (installers download) (scaffold catalog))

  (doc-next (hidden) (summary "Create the yt-dlp-script wrapper tool."))

  (define (yt-dlp-script-tool)
    (tool
      "yt-dlp-script"
      (package
        (field
          'platforms
          (arr
            (download-bin/platform
              'macos
              "https://raw.githubusercontent.com/euvlok/pkgs/HEAD/pkgs/by-name/yt/yt-dlp-script/yt-dlp-script.nu"
              "yt-dlp-script")
            (download-bin/platform
              'linux
              "https://raw.githubusercontent.com/euvlok/pkgs/HEAD/pkgs/by-name/yt/yt-dlp-script/yt-dlp-script.nu"
              "yt-dlp-script"))))
      (field 'platforms (arr "macos" "linux"))
      (field 'bins (arr (bin/version "yt-dlp-script" "--help")))
      (depends "nushell")))

  (moduledoc
    (summary "yt-dlp-script wrapper tool definition.")
    (group "Dotfiles tools")))
