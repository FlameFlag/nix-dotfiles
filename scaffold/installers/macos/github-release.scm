(library
  (installers macos github-release)
  (export github-latest-targz-bin-platform github-latest-zip-bin-platform)
  (import (rnrs) (installers cache) (installers download) (scaffold catalog))

  (doc-next
    (summary "Create a macOS installer for a latest GitHub release zip binary.")
    (param 'repo "GitHub repository in owner/name form.")
    (param 'asset-template "Shell template for the asset name using `${version}`.")
    (param 'source-template "Shell template for the extracted binary path."))

  (define
    (github-latest-zip-bin-platform
      predicate-value
      tool-name
      repo
      asset-template
      source-template
      bin-name)
    (generated-shell-platform
      predicate-value
      (arr "curl" "ditto" "head" "install" "mkdir" "rm" "sed")
      (string-append
        (sh-set "root" (tool-cache-dir tool-name))
        (sh-set "bin_dir" "{{ bin_dir }}")
        (sh-set "repo" repo)
        (sh-set "asset_template" asset-template)
        (sh-set "source_template" source-template)
        (sh-set "bin_name" bin-name)
        "tag=$(curl -fsSL --retry 3 \"https://api.github.com/repos/${repo}/releases/latest\" | sed -n 's/.*\"tag_name\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' | head -n 1)\n"
        "version=${tag#v}\n"
        "asset=$(eval \"printf '%s' \\\"${asset_template}\\\"\")\n"
        "source_path=$(eval \"printf '%s' \\\"${source_template}\\\"\")\n"
        "archive=${root}/${asset}\n"
        "extract_dir=${root}/extract\n"
        "mkdir -p \"${root}\" \"${bin_dir}\"\n"
        "curl -fsSL --retry 3 -o \"${archive}\" \"https://github.com/${repo}/releases/download/${tag}/${asset}\"\n"
        "rm -rf \"${extract_dir}\"\n"
        "mkdir -p \"${extract_dir}\"\n"
        "ditto -x -k \"${archive}\" \"${extract_dir}\"\n"
        "install -m 0755 \"${extract_dir}/${source_path}\" \"${bin_dir}/${bin_name}\"\n")))

  (doc-next
    (summary "Create a macOS installer for a latest GitHub release tar.gz binary.")
    (param 'repo "GitHub repository in owner/name form.")
    (param 'asset-template "Shell template for the asset name using `${version}`.")
    (param 'source-template "Shell template for the extracted binary path."))

  (define
    (github-latest-targz-bin-platform
      predicate-value
      tool-name
      repo
      asset-template
      source-template
      bin-name)
    (generated-shell-platform
      predicate-value
      (arr "curl" "head" "install" "mkdir" "rm" "sed" "tar")
      (string-append
        (sh-set "root" (tool-cache-dir tool-name))
        (sh-set "bin_dir" "{{ bin_dir }}")
        (sh-set "repo" repo)
        (sh-set "asset_template" asset-template)
        (sh-set "source_template" source-template)
        (sh-set "bin_name" bin-name)
        "tag=$(curl -fsSL --retry 3 \"https://api.github.com/repos/${repo}/releases/latest\" | sed -n 's/.*\"tag_name\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' | head -n 1)\n"
        "version=${tag#v}\n"
        "asset=$(eval \"printf '%s' \\\"${asset_template}\\\"\")\n"
        "source_path=$(eval \"printf '%s' \\\"${source_template}\\\"\")\n"
        "archive=${root}/${asset}\n"
        "extract_dir=${root}/extract\n"
        "mkdir -p \"${root}\" \"${bin_dir}\"\n"
        "curl -fsSL --retry 3 -o \"${archive}\" \"https://github.com/${repo}/releases/download/${tag}/${asset}\"\n"
        "rm -rf \"${extract_dir}\"\n"
        "mkdir -p \"${extract_dir}\"\n"
        "tar -xzf \"${archive}\" -C \"${extract_dir}\"\n"
        "install -m 0755 \"${extract_dir}/${source_path}\" \"${bin_dir}/${bin_name}\"\n")))

  (moduledoc
    (summary "macOS installers backed by latest GitHub release assets.")
    (group "Dotfiles platforms")))
