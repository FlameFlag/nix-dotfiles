use std::collections::HashMap;
use std::ffi::OsString;
use std::path::Path;

use dotfiles_common::{fs, http::Client, process, template};

use crate::catalog::{SourceBuildAction, SourceBuildPlatform, Tool};
use crate::context::{WindowsHomeEnv, create_isolated_home_env};
use crate::install::InstallError;
use crate::platform::Host;
use crate::progress::Spinner;
use crate::{Context, archive, links};

pub(super) fn install_source_build(
    ctx: &Context,
    tool: &Tool,
    action: &SourceBuildAction,
) -> Result<(), InstallError> {
    let platform = select_source_build_platform(action)?;
    let kind = action
        .platform_kind(platform)
        .ok_or(InstallError::InvalidCatalog("missing source archive kind"))?;
    let strip_components = action.platform_strip_components(platform);
    let platform_argv = action.platform_argv(platform);
    let sandbox_home = action.platform_sandbox_home(platform);
    let platform_links = action.platform_links(platform);
    let install_dir = links::install_dir(ctx, &tool.name, &action.version);
    let work_dir = fs::tmp_dir("bootstrap-source-build")?;
    let archive_path = work_dir.path().join(&platform.archive_file);
    let source_dir = work_dir.path().join("source");

    let mut download_bindings = HashMap::new();
    download_bindings.insert("version", action.version.as_str());
    download_bindings.insert("platform", platform.platform.as_str());
    download_bindings.insert("tool", tool.name.as_str());
    let url = template::render(&platform.url, &download_bindings)?;
    let client = Client::new("dotfiles-bootstrap")?;
    let progress = Spinner::new(format!("{}: downloading source", tool.name));
    client.download_file(&url, &archive_path)?;
    progress.set_message(format!("{}: extracting source", tool.name));
    archive::extract_file(&archive_path, &source_dir, kind, strip_components)?;

    let mut bindings = HashMap::new();
    let source_text = source_dir.to_string_lossy();
    let install_dir_text = install_dir.to_string_lossy();
    let repo_dir_text = ctx.repo_dir.to_string_lossy();
    bindings.insert("repo_dir", repo_dir_text.as_ref());
    bindings.insert("source_dir", source_text.as_ref());
    bindings.insert("prefix", install_dir_text.as_ref());
    bindings.insert("install_dir", install_dir_text.as_ref());
    bindings.insert("platform", platform.platform.as_str());
    bindings.insert("tool", tool.name.as_str());
    bindings.insert("version", action.version.as_str());
    let jobs = std::thread::available_parallelism()
        .map(usize::from)
        .unwrap_or(2)
        .to_string();
    bindings.insert("jobs", jobs.as_str());
    let argv = template::render_slice(platform_argv, &bindings)?;
    fs::remove_dir_if_exists(&install_dir)?;
    if let Some(parent) = install_dir.parent() {
        fs_err::create_dir_all(parent)?;
    }
    if argv.is_empty() {
        progress.set_message(format!("{}: installing source tree", tool.name));
        fs::move_dir(&source_dir, &install_dir)?;
    } else {
        progress.finish_and_clear();
        let mut env = ctx.command_env();
        env.extend(source_build_env(work_dir.path(), sandbox_home)?);
        process::run_in_with_env(Some(&source_dir), &argv, env)?;
    }

    let progress = Spinner::new(format!("{}: linking binaries", tool.name));
    let rendered_links = archive::render_links(platform_links, &bindings)?;
    links::link_many(ctx, &tool.name, &install_dir, &rendered_links)?;
    progress.finish_and_clear();
    Ok(())
}

fn source_build_env(
    root: &Path,
    sandbox_home: bool,
) -> Result<Vec<(OsString, OsString)>, InstallError> {
    if !sandbox_home {
        return Ok(Vec::new());
    }

    let home = root.join("home");
    let config = home.join(".config");
    let cache = home.join(".cache");
    let tmp = root.join("tmp");
    let win_home = root.join("profile");
    let appdata = root.join("appdata").join("roaming");
    let local_appdata = root.join("appdata").join("local");
    Ok(create_isolated_home_env(
        &home,
        &config,
        &cache,
        &tmp,
        Some(WindowsHomeEnv {
            profile: &win_home,
            appdata: &appdata,
            local_appdata: &local_appdata,
        }),
        true,
    )?)
}

fn select_source_build_platform(
    action: &SourceBuildAction,
) -> Result<&SourceBuildPlatform, InstallError> {
    action
        .platforms
        .iter()
        .find(|platform| Host::current().matches(platform.when))
        .ok_or(InstallError::UnsupportedPlatform)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn source_build_env_is_empty_unless_sandboxed() {
        let temp = tempfile::tempdir().expect("tempdir");
        assert!(
            source_build_env(temp.path(), false)
                .expect("env")
                .is_empty()
        );
    }

    #[test]
    fn source_build_env_creates_sandbox_paths() {
        let temp = tempfile::tempdir().expect("tempdir");
        let env = source_build_env(temp.path(), true).expect("env");
        let names = env
            .iter()
            .map(|(name, _)| name.to_string_lossy().into_owned())
            .collect::<Vec<_>>();

        assert!(names.iter().any(|name| name == "HOME"));
        assert!(names.iter().any(|name| name == "XDG_CONFIG_HOME"));
        assert!(names.iter().any(|name| name == "GIT_CONFIG_NOSYSTEM"));
        assert!(temp.path().join("home/.config").is_dir());
        assert!(temp.path().join("home/.cache").is_dir());
        assert!(temp.path().join("tmp").is_dir());
    }
}
