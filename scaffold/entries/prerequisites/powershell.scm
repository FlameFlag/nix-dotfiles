(library
  (entries prerequisites powershell)
  (export powershell-tool)
  (import (rnrs) (scaffold catalog) (scaffold extensions app winget))

  (doc-next (hidden) (summary "Create the Windows PowerShell prerequisite tool."))

  (define (powershell-tool)
    (tool
      "powershell"
      (package
        (field 'platforms (arr (winget/package-platform "Microsoft.PowerShell"))))
      (field
        'bins
        (arr
          (bin
            "pwsh"
            (field
              'version-argv
              (arr
                "pwsh"
                "-NoProfile"
                "-Command"
                "$PSVersionTable.PSVersion.ToString()")))))))

  (moduledoc
    (summary "PowerShell prerequisite tool definition.")
    (group "Dotfiles tools")))
