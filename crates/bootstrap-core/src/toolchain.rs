use std::collections::HashMap;
use std::path::PathBuf;

use dotfiles_common::{fs, http::Client, process, template};
use thiserror::Error;

use crate::Context;
use crate::catalog::{DownloadCommand, ToolchainAction};
use crate::platform::Host;
use crate::progress::Spinner;

#[derive(Debug, Error)]
pub enum ToolchainError {
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Http(#[from] dotfiles_common::http::HttpError),
    #[error(transparent)]
    Template(#[from] template::TemplateError),
    #[error(transparent)]
    Process(#[from] process::ProcessError),
    #[error("unsupported platform")]
    UnsupportedPlatform,
    #[error("installer file required for selected platform")]
    MissingInstallerFile,
    #[error("installer command required for selected platform")]
    MissingInstallerArgv,
    #[error("toolchain manager install did not produce {0}")]
    MissingManager(PathBuf),
}

/// Installs or updates a toolchain described by `spec`.
///
/// # Errors
///
/// Returns an error if command rendering, command execution, or linking components fails.
pub fn install_or_update(ctx: &Context, spec: &ToolchainAction) -> Result<(), ToolchainError> {
    let configured_name = spec
        .name_env
        .as_ref()
        .and_then(|name| std::env::var(name).ok());
    let toolchain = match configured_name {
        Some(name) => render_toolchain_name(&name)?,
        None => render_toolchain_name(&spec.name)?,
    };

    let manager = local_manager(ctx, spec).or_else(|| {
        install_manager(ctx, spec, &toolchain).ok()?;
        local_manager(ctx, spec)
    });
    let Some(manager) = manager else {
        return Err(ToolchainError::MissingManager(
            bin_dir(ctx, spec).join(&spec.manager_bin),
        ));
    };

    let manager_text = manager.to_string_lossy();
    let bindings = base_bindings(&manager_text, &toolchain, None)?;
    let update = render_toolchain_argv(spec, &spec.update_argv, &bindings)?;
    process::run_with_env(&update, ctx.command_env())?;

    let active = render_toolchain_argv(spec, &spec.active_argv, &bindings)?;
    let active_status = process::capture_with_env(&active, ctx.command_env())?;
    if !active_status.succeeded() || !active_toolchain_matches(&active_status.stdout, &toolchain) {
        let default = render_toolchain_argv(spec, &spec.default_argv, &bindings)?;
        process::run_with_env(&default, ctx.command_env())?;
    }
    Ok(())
}

fn render_toolchain_name(name: &str) -> Result<String, ToolchainError> {
    let bindings = host_bindings()?;
    template::render(name, &bindings).map_err(Into::into)
}

pub fn bin_dir(ctx: &Context, spec: &ToolchainAction) -> PathBuf {
    if !ctx.isolated_home
        && let Some(root) = spec.bin_dir.env_var.as_ref().and_then(std::env::var_os)
    {
        return PathBuf::from(root).join("bin");
    }
    ctx.home.join(&spec.bin_dir.home_relative)
}

fn install_manager(
    ctx: &Context,
    spec: &ToolchainAction,
    toolchain: &str,
) -> Result<(), ToolchainError> {
    let command = selected_install_command(spec)?;
    let temp = fs::tmp_dir("toolchain-install")?;
    let file = spec
        .install
        .platform_file(command)
        .ok_or(ToolchainError::MissingInstallerFile)?;
    let installer = temp.path().join(file);
    let client = Client::new("dotfiles-bootstrap")?;
    let progress = Spinner::new(format!("{toolchain}: downloading toolchain manager"));
    client.download_file(&command.url, &installer)?;
    progress.set_message(format!("{toolchain}: preparing installer"));
    fs::make_executable(&installer)?;
    let installer_text = installer.to_string_lossy();
    let bindings = base_bindings("", toolchain, Some(&installer_text))?;
    let argv_template = spec
        .install
        .platform_argv(command)
        .ok_or(ToolchainError::MissingInstallerArgv)?;
    let argv = render_toolchain_argv(spec, argv_template, &bindings)?;
    progress.finish_and_clear();
    process::run_with_env(&argv, ctx.command_env())?;
    Ok(())
}

fn selected_install_command(spec: &ToolchainAction) -> Result<&DownloadCommand, ToolchainError> {
    let host = Host::current();
    spec.install
        .platforms
        .iter()
        .find(|platform| host.matches(platform.when))
        .ok_or(ToolchainError::UnsupportedPlatform)
}

fn local_manager(ctx: &Context, spec: &ToolchainAction) -> Option<PathBuf> {
    let path = bin_dir(ctx, spec).join(process::executable_name(&spec.manager_bin));
    path.is_file().then_some(path)
}

fn base_bindings<'a>(
    manager_bin: &'a str,
    toolchain: &'a str,
    file: Option<&'a str>,
) -> Result<template::Bindings<'a>, ToolchainError> {
    let mut bindings = host_bindings()?;
    bindings.insert("manager_bin", manager_bin);
    bindings.insert("toolchain", toolchain);
    if let Some(file) = file {
        bindings.insert("file", file);
    }
    Ok(bindings)
}

fn host_bindings<'a>() -> Result<template::Bindings<'a>, ToolchainError> {
    let mut bindings = HashMap::new();
    let host_triple = Host::current()
        .rustup_triple()
        .ok_or(ToolchainError::UnsupportedPlatform)?;
    bindings.insert("host_triple", host_triple);
    Ok(bindings)
}

fn render_toolchain_argv(
    spec: &ToolchainAction,
    templates: &[String],
    bindings: &template::Bindings<'_>,
) -> Result<Vec<String>, ToolchainError> {
    let mut argv = Vec::new();
    for item in templates {
        match item.as_str() {
            "{components}" => {
                for component in &spec.components {
                    let mut component_bindings = bindings.clone();
                    component_bindings.insert("component", component);
                    argv.extend(template::render_slice(
                        &spec.component_argv,
                        &component_bindings,
                    )?);
                }
            }
            _ => argv.push(template::render(item, bindings)?),
        }
    }
    Ok(argv)
}

fn active_toolchain_matches(stdout: &[u8], toolchain: &str) -> bool {
    let text = String::from_utf8_lossy(stdout);
    text.split_whitespace()
        .next()
        .is_some_and(|active| active == toolchain)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::catalog::{ToolchainBinDir, ToolchainInstall};

    #[test]
    fn active_toolchain_must_match_requested_toolchain() {
        assert!(active_toolchain_matches(
            b"stable-x86_64-unknown-linux-gnu (default)\n",
            "stable-x86_64-unknown-linux-gnu"
        ));
        assert!(!active_toolchain_matches(
            b"stable-x86_64-unknown-linux-musl (default)\n",
            "stable-x86_64-unknown-linux-gnu"
        ));
    }

    #[test]
    fn render_toolchain_argv_expands_components_and_bindings() {
        let spec = ToolchainAction {
            manager_bin: "rustup".into(),
            name: "stable-{host_triple}".into(),
            name_env: None,
            bin_dir: ToolchainBinDir {
                env_var: Some("CARGO_HOME".into()),
                home_relative: ".cargo/bin".into(),
            },
            components: vec!["rustfmt".into(), "clippy".into()],
            install: ToolchainInstall {
                file: String::new(),
                argv: vec![],
                platforms: vec![],
            },
            update_argv: vec![],
            active_argv: vec![],
            default_argv: vec![],
            component_argv: vec!["--component".into(), "{component}".into()],
        };
        let mut bindings = HashMap::new();
        bindings.insert("manager_bin", "rustup");
        bindings.insert("toolchain", "stable-aarch64-apple-darwin");

        let argv = render_toolchain_argv(
            &spec,
            &[
                "{manager_bin}".into(),
                "toolchain".into(),
                "install".into(),
                "{toolchain}".into(),
                "{components}".into(),
            ],
            &bindings,
        )
        .expect("render argv");

        assert_eq!(
            argv,
            [
                "rustup",
                "toolchain",
                "install",
                "stable-aarch64-apple-darwin",
                "--component",
                "rustfmt",
                "--component",
                "clippy"
            ]
        );
    }

    #[test]
    fn render_toolchain_name_expands_host_triple() {
        let toolchain = render_toolchain_name("stable-{host_triple}").expect("render toolchain");

        assert_ne!(toolchain, "stable-{host_triple}");
        assert!(toolchain.starts_with("stable-"));
    }
}
