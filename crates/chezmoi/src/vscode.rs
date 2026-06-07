use crate::command::{command_text, run_command};
use crate::context::{Options, context_with_options};
use crate::error::Result;
use dotfiles_common::process;
use serde::Deserialize;
use std::path::Path;

#[derive(Debug, Deserialize)]
struct ExtensionManifest {
    extensions: Vec<ExtensionSpec>,
}

#[derive(Debug, Deserialize)]
struct ExtensionSpec {
    id: String,
}

pub fn install_vs_extensions(options: &Options) -> Result<()> {
    if process::path_of("code").is_none() {
        return Ok(());
    }
    let ctx = context_with_options(options)?;
    let extensions_file = ctx
        .source_dir
        .join("dot_config/Code/User/vscode-extensions.toml");
    if !extensions_file.exists() {
        return Ok(());
    }
    let installed = command_text(&["code".to_owned(), "--list-extensions".to_owned()])?;
    for extension in extension_ids(&extensions_file)? {
        if installed
            .lines()
            .any(|line| line.trim().eq_ignore_ascii_case(&extension))
        {
            continue;
        }
        run_command(&[
            "code".to_owned(),
            "--install-extension".to_owned(),
            extension,
            "--force".to_owned(),
        ])?;
    }
    Ok(())
}

fn extension_ids(path: &Path) -> Result<Vec<String>> {
    let manifest: ExtensionManifest = toml::from_str(&fs_err::read_to_string(path)?)?;
    Ok(manifest
        .extensions
        .into_iter()
        .map(|extension| extension.id.trim().to_owned())
        .filter(|extension| !extension.is_empty())
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_extensions_from_toml() -> Result<()> {
        let temp = tempfile::NamedTempFile::new()?;
        fs_err::write(
            temp.path(),
            "[[extensions]]\nid = \"one.alpha\"\n\n[[extensions]]\nid = \"\"\n\n[[extensions]]\nid = \" Two.Beta \"\n",
        )?;

        assert_eq!(
            extension_ids(temp.path())?,
            vec!["one.alpha".to_owned(), "Two.Beta".to_owned()]
        );
        Ok(())
    }
}
