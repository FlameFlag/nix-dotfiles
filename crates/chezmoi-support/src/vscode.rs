use crate::command::{command_text, run_command};
use crate::context::{Options, context_with_options};
use crate::error::Result;
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
    if which::which("code").is_err() {
        return Ok(());
    }
    let ctx = context_with_options(options)?;
    let extensions_file = ctx
        .source_dir
        .join("dot_config/Code/User/vscode-extensions.toml");
    if !extensions_file.exists() {
        return Ok(());
    }
    let installed = command_text(&duct::cmd("code", ["--list-extensions"]))?;
    for extension in extension_ids(&extensions_file)? {
        if installed
            .lines()
            .any(|line| line.trim().eq_ignore_ascii_case(&extension))
        {
            continue;
        }
        run_command(&duct::cmd(
            "code",
            ["--install-extension", &extension, "--force"],
        ))?;
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
