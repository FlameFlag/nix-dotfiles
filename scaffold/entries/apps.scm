(library
  (entries apps)
  (export apps/tools)
  (import
    (rnrs)
    (scaffold catalog)
    (entries apps one-password)
    (entries apps scaffold-vscode-extension)
    (entries apps vscode))

  (moduledoc
    (summary "Application-level tools in the personal Scaffold catalog.")
    (group "Dotfiles tools"))

  (doc-next
    (summary
      "Return desktop and application tools managed outside the NixOS system closure.")
    (returns "List of Scaffold tool objects."))

  (define (apps/tools)
    (list (vscode-tool) (scaffold-vscode-extension-tool) (one-password-tool))))
