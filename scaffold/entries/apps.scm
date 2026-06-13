(library
  (entries apps)
  (export apps/tools)
  (import
    (rnrs)
    (scaffold catalog)
    (scaffold host)
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

  (define (one-password-supported?)
    (or
      (eq? host/os 'macos)
      (eq? host/os 'windows)
      (command/available? "apt-get")
      (command/available? "dnf")
      (command/available? "rpm-ostree")))

  (define (apps/tools)
    (append
      (list (vscode-tool) (scaffold-vscode-extension-tool))
      (if (one-password-supported?) (list (one-password-tool)) '()))))
