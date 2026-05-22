module completions {

  # Runtime helpers for dotfiles chezmoi hooks
  export extern chezmoi-support [
    --source-dir: path        # Chezmoi source directory
    --home-dir: path          # Home directory used by chezmoi
    --os: string              # Chezmoi OS name
    --help(-h)                # Print help
    --version(-V)             # Print version
  ]

  export extern "chezmoi-support nushell-init" [
    --source-dir: path        # Chezmoi source directory
    --home-dir: path          # Home directory used by chezmoi
    --os: string              # Chezmoi OS name
    --help(-h)                # Print help
  ]

  export extern "chezmoi-support shell-init" [
    --source-dir: path        # Chezmoi source directory
    --home-dir: path          # Home directory used by chezmoi
    --os: string              # Chezmoi OS name
    --help(-h)                # Print help
  ]

  export extern "chezmoi-support install-vs-extensions" [
    --source-dir: path        # Chezmoi source directory
    --home-dir: path          # Home directory used by chezmoi
    --os: string              # Chezmoi OS name
    --help(-h)                # Print help
  ]

  export extern "chezmoi-support zed-install-catppuccin-theme" [
    --source-dir: path        # Chezmoi source directory
    --home-dir: path          # Home directory used by chezmoi
    --os: string              # Chezmoi OS name
    --help(-h)                # Print help
  ]

  export extern "chezmoi-support yazi-init" [
    --source-dir: path        # Chezmoi source directory
    --home-dir: path          # Home directory used by chezmoi
    --os: string              # Chezmoi OS name
    --help(-h)                # Print help
  ]

  export extern "chezmoi-support raycast-window-management" [
    --source-dir: path        # Chezmoi source directory
    --home-dir: path          # Home directory used by chezmoi
    --os: string              # Chezmoi OS name
    --help(-h)                # Print help
  ]

  export extern "chezmoi-support sync-completions" [
    --source-dir: path        # Chezmoi source directory
    --home-dir: path          # Home directory used by chezmoi
    --os: string              # Chezmoi OS name
    --help(-h)                # Print help
  ]

  def "nu-complete chezmoi-support completions shell" [] {
    [ "bash" "elvish" "fish" "nushell" "powershell" "zsh" ]
  }

  export extern "chezmoi-support completions" [
    --source-dir: path        # Chezmoi source directory
    --home-dir: path          # Home directory used by chezmoi
    --os: string              # Chezmoi OS name
    --help(-h)                # Print help
    shell: string@"nu-complete chezmoi-support completions shell"
  ]

  # Print this message or the help of the given subcommand(s)
  export extern "chezmoi-support help" [
  ]

  export extern "chezmoi-support help nushell-init" [
  ]

  export extern "chezmoi-support help shell-init" [
  ]

  export extern "chezmoi-support help install-vs-extensions" [
  ]

  export extern "chezmoi-support help zed-install-catppuccin-theme" [
  ]

  export extern "chezmoi-support help yazi-init" [
  ]

  export extern "chezmoi-support help raycast-window-management" [
  ]

  export extern "chezmoi-support help sync-completions" [
  ]

  export extern "chezmoi-support help completions" [
  ]

  # Print this message or the help of the given subcommand(s)
  export extern "chezmoi-support help help" [
  ]

}

export use completions *
