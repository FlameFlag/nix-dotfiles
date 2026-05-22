module completions {

  def "nu-complete gh-hide-comment completions" [] {
    [ "bash" "elvish" "fish" "nushell" "powershell" "zsh" ]
  }

  def "nu-complete gh-hide-comment reason" [] {
    [ "outdated" "duplicate" "off-topic" "resolved" "spam" "abuse" ]
  }

  # Hide GitHub comments via the GraphQL minimizeComment mutation
  export extern gh-hide-comment [
    --completions: string@"nu-complete gh-hide-comment completions"
    --reason: string@"nu-complete gh-hide-comment reason"
    --help(-h)                # Print help
    --version(-V)             # Print version
    ...urls: string
  ]

}

export use completions *
