use dotfiles_common::{fs, http::Client, process, template};
use std::collections::HashMap;
use std::ffi::OsString;
use std::path::Path;
use thiserror::Error;

use crate::catalog::{Action, Catalog, Phase, SourceBuildAction, SourceBuildPlatform, Tool};
use crate::context::{WindowsHomeEnv, create_isolated_home_env};
use crate::packages::PackageInventory;
use crate::platform::Host;
use crate::progress::Spinner;
use crate::{Context, archive, file, links, ownership, runtime, toolchain};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Policy {
    /// Install only tools whose managed binaries are missing or unhealthy.
    InstallMissing,
    /// Re-run every supported non-prerequisite action.
    UpdateAll,
}

#[derive(Debug, Error)]
pub enum InstallError {
    #[error(transparent)]
    Catalog(#[from] crate::catalog::CatalogError),
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Http(#[from] dotfiles_common::http::HttpError),
    #[error(transparent)]
    Template(#[from] template::TemplateError),
    #[error(transparent)]
    Process(#[from] process::ProcessError),
    #[error(transparent)]
    Archive(#[from] archive::ArchiveError),
    #[error(transparent)]
    File(#[from] file::FileError),
    #[error(transparent)]
    Link(#[from] links::LinkError),
    #[error(transparent)]
    Toolchain(#[from] toolchain::ToolchainError),
    #[error("unsupported platform")]
    UnsupportedPlatform,
    #[error("catalog invariant failed: {0}")]
    InvalidCatalog(&'static str),
    #[error(
        "{phase:?} phase failed with {failures} tool failures; stopping before dependent phases"
    )]
    PhaseFailed { phase: Phase, failures: usize },
}

/// Installs or updates tools from the bootstrap catalog according to `policy`.
///
/// # Errors
///
/// Returns an error if loading the catalog, checking tool state, or installing a tool fails.
pub fn install_all(ctx: &Context, policy: Policy) -> Result<(), InstallError> {
    let catalog = Catalog::load(ctx.catalog_path())?;
    for phase in [
        Phase::Prerequisites,
        Phase::Archives,
        Phase::Packages,
        Phase::Builds,
    ] {
        let mut failures = 0;
        for tool in catalog.tools.iter().filter(|tool| tool.phase() == phase) {
            failures += install_one(ctx, policy, tool)?;
        }
        if failures != 0 {
            return Err(InstallError::PhaseFailed { phase, failures });
        }
    }
    Ok(())
}

fn install_one(ctx: &Context, policy: Policy, tool: &Tool) -> Result<usize, InstallError> {
    if !tool.supports_host(crate::platform::Host::current()) {
        println!("{}: unsupported on this host, skipping", tool.name);
        return Ok(0);
    }

    if tool.name == "bootstrap" && runtime::skip_self_install() {
        println!("{}: nix-managed, skipping", tool.name);
        return Ok(0);
    }

    if matches!(tool.action, Action::Required) {
        if process::path_of(&tool.name).is_some() {
            println!("{}: bootstrap prerequisite, skipping", tool.name);
            return Ok(0);
        }
        eprintln!(
            "error: {}: missing bootstrap prerequisite; run bootstrap bootstrap",
            tool.name
        );
        return Ok(1);
    }

    if policy == Policy::InstallMissing && !should_install(ctx, tool)? {
        println!("{}: present, skipping", tool.name);
        return Ok(0);
    }

    println!("{}: {}", tool.name, install_verb(policy, tool));
    match install_action(ctx, tool) {
        Ok(()) => {
            // Installers can succeed while leaving no usable binary on PATH, so
            // every action gets one verification pass before the phase continues.
            if installed_tool_healthy(ctx, tool)? {
                Ok(0)
            } else {
                eprintln!("error: {}: installed tool failed verification", tool.name);
                Ok(1)
            }
        }
        Err(err) => {
            eprintln!("error: {}: {err}", tool.name);
            Ok(1)
        }
    }
}

fn install_action(ctx: &Context, tool: &Tool) -> Result<(), InstallError> {
    match &tool.action {
        Action::Required => Ok(()),
        Action::Archive(action) => {
            archive::install_archive(ctx, &tool.name, action)?;
            Ok(())
        }
        Action::File(action) => {
            file::install_file(ctx, &tool.name, action)?;
            Ok(())
        }
        Action::Package(action) => {
            let mut bindings = HashMap::new();
            bindings.insert("package", action.name.as_str());
            let argv = template::render_slice(&action.install_argv, &bindings)?;
            process::run_with_env(&argv, ctx.command_env())?;
            Ok(())
        }
        Action::Build(action) => {
            let build_dir = ctx.repo_dir.join(&action.path);
            let prefix = ctx.opt_dir.join(&tool.name).join("latest");
            let mut bindings = HashMap::new();
            let repo = ctx.repo_dir.to_string_lossy();
            let build = build_dir.to_string_lossy();
            let prefix_text = prefix.to_string_lossy();
            bindings.insert("repo_dir", repo.as_ref());
            bindings.insert("build_dir", build.as_ref());
            bindings.insert("prefix", prefix_text.as_ref());
            bindings.insert("tool", tool.name.as_str());
            let argv = template::render_slice(&action.argv, &bindings)?;
            process::run_in_with_env(Some(build_dir), &argv, ctx.command_env())?;
            match action.links.as_slice() {
                [] => {
                    for bin in &tool.bins {
                        let target = prefix.join("bin").join(process::executable_name(&bin.name));
                        links::managed_adopt_existing(ctx, &tool.name, &target, &bin.name)?;
                    }
                }
                links => links::link_many_adopt_existing(ctx, &tool.name, &prefix, links)?,
            }
            Ok(())
        }
        Action::SourceBuild(action) => {
            install_source_build(ctx, tool, action)?;
            Ok(())
        }
        Action::Toolchain(action) => {
            toolchain::install_or_update(ctx, action)?;
            Ok(())
        }
    }
}

const fn install_verb(policy: Policy, tool: &Tool) -> &'static str {
    match (policy, &tool.action) {
        (Policy::UpdateAll, _) => "updating",
        (_, Action::Toolchain(_)) => "ensuring",
        _ => "installing",
    }
}

fn should_install(ctx: &Context, tool: &Tool) -> Result<bool, InstallError> {
    match &tool.action {
        Action::Required => Ok(tool
            .bins
            .iter()
            .any(|bin| process::path_of(&bin.name).is_none())),
        Action::Toolchain(_) | Action::Build(_) => Ok(true),
        Action::File(_) => managed_bins_missing_or_unhealthy(ctx, tool),
        Action::Archive(_) | Action::SourceBuild(_) | Action::Package(_) => {
            managed_bins_missing_or_unhealthy(ctx, tool)
        }
    }
}

fn installed_tool_healthy(ctx: &Context, tool: &Tool) -> Result<bool, InstallError> {
    match &tool.action {
        Action::Required => Ok(true),
        Action::Build(_) => managed_bins_missing_or_unhealthy(ctx, tool).map(|missing| !missing),
        Action::File(_) => managed_bins_missing_or_unhealthy(ctx, tool).map(|missing| !missing),
        Action::Toolchain(spec) => {
            let bin_dir = toolchain::bin_dir(ctx, spec);
            Ok(tool.bins.iter().all(|bin| {
                let path = bin_dir.join(process::executable_name(&bin.name));
                path.is_file() && bin_runs_at_path(ctx, &bin.version_argv, &path)
            }))
        }
        Action::Archive(_) | Action::Package(_) | Action::SourceBuild(_) => {
            managed_bins_missing_or_unhealthy(ctx, tool).map(|missing| !missing)
        }
    }
}

fn managed_bins_missing_or_unhealthy(ctx: &Context, tool: &Tool) -> Result<bool, InstallError> {
    let packages = match &tool.action {
        Action::Package(package) => PackageInventory::collect_for_package(ctx, package)?,
        _ => PackageInventory::default(),
    };
    for bin in &tool.bins {
        let path =
            process::path_in_dir(&ctx.bin_dir, &bin.name).or_else(|| process::path_of(&bin.name));
        match ownership::classify_bin(ctx, tool, &bin.name, path.as_deref(), &packages) {
            ownership::Classification::Missing => return Ok(true),
            ownership::Classification::External => {
                // A binary in our bin dir but not recognized by the tool's
                // normal ownership check is still good enough for "missing"
                // mode. This lets locally built shims satisfy tools
                // without forcing a reinstall.
                if path.is_some_and(|p| dotfiles_common::fs::relative_under(&ctx.bin_dir, p)) {
                    continue;
                }
                return Ok(true);
            }
            ownership::Classification::Managed => {
                if !path.is_some_and(|path| bin_runs_at_path(ctx, &bin.version_argv, &path)) {
                    return Ok(true);
                }
            }
        }
    }
    Ok(false)
}

fn bin_runs_at_path(ctx: &Context, argv_template: &[String], path: &std::path::Path) -> bool {
    if argv_template.is_empty() {
        return false;
    }
    let argv = process::argv_with_resolved_program(argv_template, path);
    process::capture_with_env(&argv, ctx.command_env()).is_ok_and(|output| output.succeeded())
}

fn install_source_build(
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
    use crate::catalog::{Bin, BuildAction};

    fn context() -> (tempfile::TempDir, Context) {
        let temp = tempfile::tempdir().expect("tempdir");
        let ctx = Context::new_with_home(temp.path().join("repo"), Some(temp.path().join("home")))
            .expect("context");
        (temp, ctx)
    }

    fn build_tool() -> Tool {
        Tool {
            name: "demo".into(),
            bins: vec![Bin {
                name: "demo".into(),
                version_argv: vec!["demo".into(), "--version".into()],
            }],
            platforms: vec![],
            requires: vec![],
            phase: None,
            action: Action::Build(BuildAction {
                path: "demo".into(),
                argv: vec!["cargo".into(), "build".into()],
                links: vec![],
            }),
        }
    }

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

    #[test]
    fn installed_tool_healthy_handles_required_and_local_build_bins() {
        let (_temp, ctx) = context();
        let required = Tool {
            name: "required".into(),
            bins: vec![Bin {
                name: "required".into(),
                version_argv: vec!["required".into(), "--version".into()],
            }],
            platforms: vec![],
            requires: vec![],
            phase: None,
            action: Action::Required,
        };
        assert!(installed_tool_healthy(&ctx, &required).expect("required health"));

        let tool = build_tool();
        assert!(!installed_tool_healthy(&ctx, &tool).expect("missing build health"));
        let script = ctx
            .bin_dir
            .join(if cfg!(windows) { "demo.cmd" } else { "demo" });
        let script_bytes: &[u8] = if cfg!(windows) {
            b"@echo off\r\necho demo 1.0.0\r\n"
        } else {
            b"#!/bin/sh\nprintf 'demo 1.0.0\\n'\n"
        };
        fs::write_executable(&script, script_bytes).expect("write build bin");
        assert!(installed_tool_healthy(&ctx, &tool).expect("build health"));

        fs_err::write(ctx.bin_dir.join("demo"), "not executable").expect("write junk build bin");
        assert!(!installed_tool_healthy(&ctx, &tool).expect("junk build health"));
    }

    #[test]
    fn installed_tool_healthy_rejects_broken_build_bins() {
        let (_temp, ctx) = context();
        let tool = build_tool();
        fs_err::write(ctx.bin_dir.join("demo"), "").expect("write broken build bin");

        assert!(!installed_tool_healthy(&ctx, &tool).expect("build health"));
    }

    #[test]
    fn managed_bins_missing_or_unhealthy_detects_missing_bins() {
        let (_temp, ctx) = context();
        assert!(managed_bins_missing_or_unhealthy(&ctx, &build_tool()).expect("missing status"));
    }

    #[test]
    fn install_all_skips_unsupported_tools() {
        let temp = tempfile::tempdir().expect("tempdir");
        let repo = temp.path().join("repo");
        let unsupported_os = if cfg!(windows) { "macos" } else { "windows" };
        fs_err::create_dir_all(repo.join("bootstrap")).expect("create catalog dir");
        fs_err::write(
            repo.join("bootstrap/tools.toml"),
            format!(
                r#"
[[tools]]
name = "unsupported-demo"
platforms = ["{unsupported_os}"]

[[tools.bins]]
name = "unsupported-demo"
version_argv = ["unsupported-demo", "--version"]

[tools.action]
type = "required"
"#
            ),
        )
        .expect("write catalog");
        let ctx = Context::new_with_home(&repo, Some(temp.path().join("home"))).expect("context");

        install_all(&ctx, Policy::InstallMissing).expect("install all");
    }
}
