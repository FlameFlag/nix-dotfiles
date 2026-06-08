(library
  (entries apps scaffold-vscode-extension)
  (export scaffold-vscode-extension-tool)
  (import (rnrs) (scaffold catalog))

  (doc-next
    (summary
      "Create the Scaffold Scheme VS Code extension tool installed from the rolling VSIX."))

  (define (scaffold-vscode-extension-tool)
    (tool
      "scaffold-vscode-extension"
      (package
        (field
          'platforms
          (arr
            (package/platform-argvs
              'macos
              (arr "code" "curl" "mkdir")
              (arr
                (arr
                  "mkdir"
                  "-p"
                  "{{ home }}/.local/share/scaffold/tools/scaffold-vscode/latest")
                (arr
                  "curl"
                  "-fsSL"
                  "--retry"
                  "3"
                  "-o"
                  "{{ home }}/.local/share/scaffold/tools/scaffold-vscode/latest/scaffold-vscode-rolling.vsix"
                  "https://github.com/FlameFlag/scaffold/releases/download/rolling/scaffold-vscode-rolling.vsix")
                (arr
                  "code"
                  "--install-extension"
                  "{{ home }}/.local/share/scaffold/tools/scaffold-vscode/latest/scaffold-vscode-rolling.vsix"
                  "--force")))
            (package/platform-argvs
              'linux
              (arr "code" "curl" "mkdir")
              (arr
                (arr
                  "mkdir"
                  "-p"
                  "{{ home }}/.local/share/scaffold/tools/scaffold-vscode/latest")
                (arr
                  "curl"
                  "-fsSL"
                  "--retry"
                  "3"
                  "-o"
                  "{{ home }}/.local/share/scaffold/tools/scaffold-vscode/latest/scaffold-vscode-rolling.vsix"
                  "https://github.com/FlameFlag/scaffold/releases/download/rolling/scaffold-vscode-rolling.vsix")
                (arr
                  "code"
                  "--install-extension"
                  "{{ home }}/.local/share/scaffold/tools/scaffold-vscode/latest/scaffold-vscode-rolling.vsix"
                  "--force"))))))
      (field 'platforms (arr "macos" "linux"))
      (field
        'checks
        (arr
          (host/check
            'macos
            (arr "sh" "-c" "code --list-extensions | grep -Fx scaffold.scaffold-scheme"))
          (host/check
            'linux
            (arr "sh" "-c" "code --list-extensions | grep -Fx scaffold.scaffold-scheme"))))
      (meta
        (home-page "https://github.com/FlameFlag/scaffold")
        (description "Scheme-driven system scaffolding CLI"))))

  (moduledoc
    (summary "Scaffold Scheme VS Code extension tool definition.")
    (group "Dotfiles tools")))
