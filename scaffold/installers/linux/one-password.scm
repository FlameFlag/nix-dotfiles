(library
  (installers linux one-password)
  (export apt-platform rpm-platform)
  (import (rnrs) (scaffold catalog) (scaffold extensions support download))

  (doc-next
    (hidden)
    (summary "Create the 1Password apt repository installer platform."))

  (define (apt-platform)
    (let
      ((root (tool-cache-dir "1password"))
        (key-path
          (string-append (tool-cache-dir "1password") "/1password.asc")))
      (package/platform-argvs
        'linux
        (arr "apt-get" "curl" "dpkg" "gpg" "mkdir" "sh" "sudo" "tee")
        (arr
          (arr "mkdir" "-p" root)
          (arr
            "sudo"
            "install"
            "-d"
            "-m"
            "0755"
            "/usr/share/keyrings"
            "/etc/debsig/policies/AC2D62742012EA22"
            "/usr/share/debsig/keyrings/AC2D62742012EA22")
          (arr
            "curl"
            "-fsSL"
            "--retry"
            "3"
            "-o"
            key-path
            "https://downloads.1password.com/linux/keys/1password.asc")
          (arr
            "sudo"
            "gpg"
            "--dearmor"
            "--yes"
            "--output"
            "/usr/share/keyrings/1password-archive-keyring.gpg"
            key-path)
          (arr
            "sudo"
            "gpg"
            "--dearmor"
            "--yes"
            "--output"
            "/usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg"
            key-path)
          (arr
            "sudo"
            "curl"
            "-fsSL"
            "--retry"
            "3"
            "-o"
            "/etc/debsig/policies/AC2D62742012EA22/1password.pol"
            "https://downloads.1password.com/linux/debian/debsig/1password.pol")
          (arr
            "sh"
            "-c"
            "arch=$(dpkg --print-architecture); printf 'deb [arch=%s signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/%s stable main\\n' \"$arch\" \"$arch\" | sudo tee /etc/apt/sources.list.d/1password.list >/dev/null")
          (arr "sudo" "apt-get" "update")
          (arr "sudo" "apt-get" "install" "-y" "1password" "1password-cli")))))

  (doc-next (hidden) (summary "Create a 1Password RPM repository installer platform."))

  (define (rpm-platform installer-requires installer-argv)
    (package/platform-argvs
      'linux
      (list->vector
        (append
          (vector->list (arr "curl" "install" "sh" "sudo" "tee"))
          (vector->list installer-requires)))
      (arr
        (arr "sudo" "install" "-d" "-m" "0755" "/etc/pki/rpm-gpg" "/etc/yum.repos.d")
        (arr
          "sudo"
          "curl"
          "-fsSL"
          "--retry"
          "3"
          "-o"
          "/etc/pki/rpm-gpg/RPM-GPG-KEY-1password"
          "https://downloads.1password.com/linux/keys/1password.asc")
        (arr
          "sh"
          "-c"
          "printf '%s\\n' '[1password]' 'name=1Password Stable Channel' 'baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch' 'enabled=1' 'gpgcheck=1' 'repo_gpgcheck=1' 'gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-1password' | sudo tee /etc/yum.repos.d/1password.repo >/dev/null")
        installer-argv)))

  (moduledoc
    (summary "Linux 1Password repository setup platform helpers.")
    (group "Dotfiles platforms")))
