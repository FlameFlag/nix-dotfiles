(library
  (entries apps vscode)
  (export vscode-tool)
  (import
    (rnrs)
    (installers macos app-bundle)
    (scaffold catalog)
    (scaffold extensions app winget)
    (scaffold extensions distro apt)
    (scaffold extensions distro dnf)
    (scaffold extensions distro pacman))

  (doc-next (hidden) (summary "Create the Visual Studio Code application tool."))

  (define (vscode-tool)
    (tool
      "vscode"
      (package
        (field
          'platforms
          (arr
            (apt/package-platform "code")
            (dnf/package-platform "code")
            (pacman/package-platform "code")
            (zip-app-bin-platform
              (predicate 'macos 'aarch64)
              "vscode"
              "https://update.code.visualstudio.com/latest/darwin-arm64/stable"
              "VSCode-darwin-arm64.zip"
              "Visual Studio Code.app"
              "Contents/Resources/app/bin/code"
              "code")
            (zip-app-bin-platform
              (predicate 'macos 'x86_64)
              "vscode"
              "https://update.code.visualstudio.com/latest/darwin/stable"
              "VSCode-darwin.zip"
              "Visual Studio Code.app"
              "Contents/Resources/app/bin/code"
              "code")
            (winget/package-platform "Microsoft.VisualStudioCode"))))
      (field 'platforms (arr "macos" "linux" "windows"))
      (field 'bins (arr (bin/version "code" "--version")))))

  (moduledoc
    (summary "Visual Studio Code application tool definition.")
    (group "Dotfiles tools")))
