module completions {

  def "nu-complete lenovo-con-mode completions" [] {
    [ "bash" "elvish" "fish" "nushell" "powershell" "zsh" ]
  }

  def "nu-complete lenovo-con-mode action" [] {
    [ "status" "on" "enable" "off" "disable" "toggle" ]
  }

  # Toggle or set Lenovo Ideapad conservation mode
  export extern lenovo-con-mode [
    --completions: string@"nu-complete lenovo-con-mode completions"
    --help(-h)                # Print help
    --version(-V)             # Print version
    action?: string@"nu-complete lenovo-con-mode action"
  ]

}

export use completions *
