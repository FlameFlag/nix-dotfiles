module completions {

  # Install and inspect dotfiles development tools
  export extern bootstrap [
    --repo-dir: path          # Repository root that contains bootstrap/tools.toml
    --help(-h)                # Print help (see more with '--help')
    --version(-V)             # Print version
  ]

  def "nu-complete bootstrap install mode" [] {
    [ "missing" "all" ]
  }

  # Install missing tools from the bootstrap catalog
  export extern "bootstrap install" [
    --mode: string@"nu-complete bootstrap install mode" # Choose whether to install only unhealthy tools or refresh everything
    --repo-dir: path          # Repository root that contains bootstrap/tools.toml
    --help(-h)                # Print help (see more with '--help')
    --version(-V)             # Print version
  ]

  # Prepare this machine and install missing bootstrap tools
  export extern "bootstrap bootstrap" [
    --repo-dir: path          # Repository root that contains bootstrap/tools.toml
    --help(-h)                # Print help (see more with '--help')
    --version(-V)             # Print version
  ]

  # Install the running bootstrap binary into the bootstrap bin directory
  export extern "bootstrap self-install" [
    --repo-dir: path          # Repository root that contains bootstrap/tools.toml
    --help(-h)                # Print help
    --version(-V)             # Print version
  ]

  # Reinstall or update every managed tool
  export extern "bootstrap update" [
    --repo-dir: path          # Repository root that contains bootstrap/tools.toml
    --help(-h)                # Print help
    --version(-V)             # Print version
  ]

  def "nu-complete bootstrap doctor format" [] {
    [ "table" "json" ]
  }

  # Inspect tool availability, source, versions, and paths
  export extern "bootstrap doctor" [
    --format: string@"nu-complete bootstrap doctor format" # Render the doctor report as a table or JSON
    --no-fail                 # Print issues without returning a failing exit code
    --repo-dir: path          # Repository root that contains bootstrap/tools.toml
    --help(-h)                # Print help
    --version(-V)             # Print version
  ]

  def "nu-complete bootstrap tools format" [] {
    [ "table" "json" ]
  }

  # List tools declared in the bootstrap catalog
  export extern "bootstrap tools" [
    --all                     # Include tools that do not support the current host
    --format: string@"nu-complete bootstrap tools format" # Render the catalog overview as a table or JSON
    --repo-dir: path          # Repository root that contains bootstrap/tools.toml
    --help(-h)                # Print help
    --version(-V)             # Print version
  ]

  def "nu-complete bootstrap paths format" [] {
    [ "table" "json" ]
  }

  # Show resolved bootstrap paths and environment roots
  export extern "bootstrap paths" [
    --format: string@"nu-complete bootstrap paths format" # Render paths as a table or JSON
    --repo-dir: path          # Repository root that contains bootstrap/tools.toml
    --help(-h)                # Print help
    --version(-V)             # Print version
  ]

  # Print the bootstrap catalog JSON schema
  export extern "bootstrap schema" [
    --repo-dir: path          # Repository root that contains bootstrap/tools.toml
    --help(-h)                # Print help
    --version(-V)             # Print version
  ]

  def "nu-complete bootstrap completions shell" [] {
    [ "bash" "elvish" "fish" "nushell" "powershell" "zsh" ]
  }

  # Generate shell completions
  export extern "bootstrap completions" [
    --repo-dir: path          # Repository root that contains bootstrap/tools.toml
    --help(-h)                # Print help
    --version(-V)             # Print version
    shell: string@"nu-complete bootstrap completions shell"
  ]

  # Generate a roff man page from the clap definition
  export extern "bootstrap man" [
    --repo-dir: path          # Repository root that contains bootstrap/tools.toml
    --help(-h)                # Print help
    --version(-V)             # Print version
  ]

  # Generate Markdown reference docs from the clap definition
  export extern "bootstrap markdown" [
    --repo-dir: path          # Repository root that contains bootstrap/tools.toml
    --help(-h)                # Print help
    --version(-V)             # Print version
  ]

  # Print this message or the help of the given subcommand(s)
  export extern "bootstrap help" [
  ]

  # Install missing tools from the bootstrap catalog
  export extern "bootstrap help install" [
  ]

  # Prepare this machine and install missing bootstrap tools
  export extern "bootstrap help bootstrap" [
  ]

  # Install the running bootstrap binary into the bootstrap bin directory
  export extern "bootstrap help self-install" [
  ]

  # Reinstall or update every managed tool
  export extern "bootstrap help update" [
  ]

  # Inspect tool availability, source, versions, and paths
  export extern "bootstrap help doctor" [
  ]

  # List tools declared in the bootstrap catalog
  export extern "bootstrap help tools" [
  ]

  # Show resolved bootstrap paths and environment roots
  export extern "bootstrap help paths" [
  ]

  # Print the bootstrap catalog JSON schema
  export extern "bootstrap help schema" [
  ]

  # Generate shell completions
  export extern "bootstrap help completions" [
  ]

  # Generate a roff man page from the clap definition
  export extern "bootstrap help man" [
  ]

  # Generate Markdown reference docs from the clap definition
  export extern "bootstrap help markdown" [
  ]

  # Print this message or the help of the given subcommand(s)
  export extern "bootstrap help help" [
  ]

}

export use completions *
