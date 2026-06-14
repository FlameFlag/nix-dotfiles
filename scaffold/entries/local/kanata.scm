(library
  (entries local kanata)
  (export kanata-tool)
  (import (rnrs) (scaffold catalog))

  (doc-next
    (hidden)
    (summary "Cargo install argv for the pinned personal Kanata fork."))

  (define kanata/install-argv
    (arr
      "cargo"
      "install"
      "--git"
      "https://github.com/FlameFlag/kanata"
      "kanata"
      "--rev"
      "c8c720ded5a34bbc4bdfbfbe33c97b7bb2e60e77"
      "--features"
      "cmd"
      "--root"
      "{{ home }}/.local"
      "--force"
      "--locked"))

  (doc-next (hidden) (summary "Create the pinned Kanata tool for Linux hosts."))

  (define (kanata-tool)
    (tool
      "kanata"
      (package
        (field
          'platforms
          (arr (package/platform 'linux (arr "cargo" "git") kanata/install-argv))))
      (field 'bins (arr (bin "kanata")))))

  (moduledoc
    (summary "Pinned personal Kanata fork tool definition.")
    (group "Dotfiles tools")))
