use comfy_table::{Cell, Table, presets::UTF8_FULL_CONDENSED};
use dotfiles_common::{fs, process};
use serde::Serialize;
use thiserror::Error;

use crate::catalog::{Action, Catalog, Tool};
use crate::ownership::{self, Classification};
use crate::packages::PackageInventory;
use crate::{Context, runtime, toolchain};

#[derive(Debug, Error)]
pub enum DoctorError {
    #[error(transparent)]
    Catalog(#[from] crate::catalog::CatalogError),
    #[error(transparent)]
    Process(#[from] process::ProcessError),
    #[error("doctor found issues")]
    FoundIssues,
}

#[derive(Debug, Clone, Serialize)]
pub struct Report {
    pub rows: Vec<Row>,
}

impl Report {
    #[must_use]
    pub fn has_issues(&self) -> bool {
        self.rows.iter().any(|row| row.failed)
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct Row {
    pub name: String,
    pub source: String,
    pub version: String,
    pub path: String,
    pub failed: bool,
}

/// Runs the doctor check and prints a report.
///
/// # Errors
///
/// Returns an error if report generation fails or issues are found.
pub fn run(ctx: &Context) -> Result<(), DoctorError> {
    let report = report(ctx)?;
    print_report(&report);
    if report.has_issues() {
        Err(DoctorError::FoundIssues)
    } else {
        Ok(())
    }
}

/// Builds a doctor report for the current catalog and host.
///
/// # Errors
///
/// Returns an error if the catalog cannot be loaded or tool inspection fails.
pub fn report(ctx: &Context) -> Result<Report, DoctorError> {
    let catalog = Catalog::load(ctx.catalog_path())?;
    let package_inventory = PackageInventory::collect_for_catalog(ctx, &catalog)?;
    let mut rows = Vec::new();

    for tool in catalog
        .tools
        .iter()
        .filter(|tool| tool.supports_host(crate::platform::Host::current()))
    {
        for bin in &tool.bins {
            let path = bin_path(ctx, tool, &bin.name);
            let (version, failed) = version_status(ctx, tool, &bin.version_argv, path.as_deref());
            let source = source_label(ctx, tool, &bin.name, path.as_deref(), &package_inventory);
            rows.push(Row {
                name: bin.name.clone(),
                source,
                version,
                path: path.as_ref().map_or_else(
                    || "missing".into(),
                    |path| path.to_string_lossy().into_owned(),
                ),
                failed,
            });
        }
    }

    Ok(Report { rows })
}

pub fn print_report(report: &Report) {
    let mut table = Table::new();
    table.load_preset(UTF8_FULL_CONDENSED);
    table.set_header(["tool", "source", "version", "path"]);
    for row in &report.rows {
        table.add_row([
            Cell::new(&row.name),
            Cell::new(&row.source),
            Cell::new(&row.version),
            Cell::new(&row.path),
        ]);
    }
    println!("{table}");
}

fn bin_path(ctx: &Context, tool: &Tool, bin: &str) -> Option<std::path::PathBuf> {
    match &tool.action {
        Action::Toolchain(spec) => {
            let path = toolchain::bin_dir(ctx, spec).join(process::executable_name(bin));
            path.is_file().then_some(path)
        }
        _ => process::path_in_dir(&ctx.bin_dir, bin).or_else(|| process::path_of(bin)),
    }
}

fn version_status(
    ctx: &Context,
    tool: &Tool,
    argv_template: &[String],
    path: Option<&std::path::Path>,
) -> (String, bool) {
    let Some(path) = path else {
        return ("missing".into(), true);
    };
    let argv = process::argv_with_resolved_program(argv_template, path);
    match process::capture_with_env(&argv, ctx.command_env()) {
        Ok(output) if output.succeeded() && matches!(tool.action, Action::File(_)) => {
            ("installed".into(), false)
        }
        Ok(output) if output.succeeded() => {
            let stdout = fs::trim_ascii_whitespace(&output.stdout);
            let stderr = fs::trim_ascii_whitespace(&output.stderr);
            let raw = if stdout.is_empty() { stderr } else { stdout };
            (sanitize_version(raw), false)
        }
        Ok(output) => (
            format!("error:exit-{}", output.status.code().unwrap_or(1)),
            true,
        ),
        Err(err) => (format!("error:{err}"), true),
    }
}

fn source_label(
    ctx: &Context,
    tool: &Tool,
    bin: &str,
    path: Option<&std::path::Path>,
    package_inventory: &PackageInventory,
) -> String {
    if tool.name == "bootstrap" && runtime::skip_self_install() && path.is_some() {
        return "nix-managed".into();
    }

    match ownership::classify_bin(ctx, tool, bin, path, package_inventory) {
        Classification::Missing => "missing".into(),
        Classification::Managed => tool.source_label(true).into(),
        Classification::External => tool.source_label(false).into(),
    }
}

fn sanitize_version(raw: &str) -> String {
    let collapsed = raw
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>()
        .join(" ");
    let prefix = collapsed
        .split_once(',')
        .map_or(collapsed.as_str(), |(prefix, _)| prefix)
        .trim();
    let mut words = prefix.split_whitespace();
    let Some(first) = words.next() else {
        return String::new();
    };
    let Some(second) = words.next() else {
        return first.to_owned();
    };
    match (
        second.eq_ignore_ascii_case("version"),
        first.eq_ignore_ascii_case("version") || looks_like_version(second),
    ) {
        (true, _) => words
            .next()
            .map_or_else(|| first.to_owned(), |version| version.to_owned()),
        (false, true) => second.to_owned(),
        (false, false) => prefix.to_owned(),
    }
}

fn looks_like_version(value: &str) -> bool {
    value
        .trim_start_matches('v')
        .chars()
        .next()
        .is_some_and(|first| first.is_ascii_digit())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::catalog::{Bin, BuildAction, PackageAction, Tool};

    fn tool(name: &str, action: Action) -> Tool {
        Tool {
            name: name.into(),
            bins: vec![Bin {
                name: name.into(),
                version_argv: vec![name.into(), "--version".into()],
            }],
            platforms: vec![],
            requires: vec![],
            phase: None,
            action,
        }
    }

    #[test]
    fn versions_collapse_multiline_output() {
        assert_eq!(sanitize_version("1.2.3\nabcdef\nx64"), "1.2.3 abcdef x64");
    }

    #[test]
    fn versions_trim_verbose_metadata() {
        assert_eq!(
            sanitize_version("chezmoi version v2.70.4, commit abc, built at later"),
            "v2.70.4"
        );
        assert_eq!(sanitize_version("ruff 0.15.14"), "0.15.14");
        assert_eq!(sanitize_version("git version 2.54.0"), "2.54.0");
    }

    #[test]
    fn source_labels_describe_missing_external_and_managed_bins() {
        let temp = tempfile::tempdir().expect("tempdir");
        let ctx = Context::new_with_home(temp.path().join("repo"), Some(temp.path().join("home")))
            .expect("context");
        let build_tool = tool(
            "demo",
            Action::Build(BuildAction {
                path: "demo".into(),
                argv: vec!["cargo".into(), "build".into()],
                links: vec![],
            }),
        );
        let managed = ctx.bin_dir.join("demo");
        fs_err::write(&managed, "").expect("write managed file");
        let external = temp.path().join("external-demo");
        fs_err::write(&external, "").expect("write external file");

        assert_eq!(
            source_label(
                &ctx,
                &build_tool,
                "demo",
                None,
                &PackageInventory::default()
            ),
            "missing"
        );
        assert_eq!(
            source_label(
                &ctx,
                &build_tool,
                "demo",
                Some(&external),
                &PackageInventory::default()
            ),
            "external"
        );
        assert_eq!(
            source_label(
                &ctx,
                &build_tool,
                "demo",
                Some(&managed),
                &PackageInventory::default()
            ),
            "bootstrap-managed"
        );

        let required_tool = tool("required-demo", Action::Required);
        assert_eq!(
            source_label(
                &ctx,
                &required_tool,
                "required-demo",
                Some(&external),
                &PackageInventory::default()
            ),
            "bootstrap-required"
        );

        let package_tool = tool(
            "package-demo",
            Action::Package(PackageAction {
                name: "package-demo".into(),
                install_argv: vec!["manager".into(), "install".into()],
                inventory: None,
            }),
        );
        assert_eq!(
            source_label(
                &ctx,
                &package_tool,
                "package-demo",
                Some(&managed),
                &PackageInventory::default()
            ),
            "external"
        );
    }

    #[test]
    fn version_status_handles_missing_build_file_and_command_output() {
        let temp = tempfile::tempdir().expect("tempdir");
        let ctx = Context::new_with_home(temp.path().join("repo"), Some(temp.path().join("home")))
            .expect("context");
        let build_tool = tool(
            "demo",
            Action::Build(BuildAction {
                path: "demo".into(),
                argv: vec!["cargo".into(), "build".into()],
                links: vec![],
            }),
        );
        let file_tool = tool(
            "script",
            Action::File(crate::catalog::FileAction {
                source: crate::catalog::Source::Direct {
                    version: "1".into(),
                    url: "https://example.invalid/script".into(),
                },
                file: "script".into(),
                links: vec![],
            }),
        );
        let build_script = temp
            .path()
            .join(if cfg!(windows) { "demo.cmd" } else { "demo" });
        let file_script = temp.path().join(if cfg!(windows) {
            "version-script.cmd"
        } else {
            "version-script"
        });
        let script_bytes: &[u8] = if cfg!(windows) {
            b"@echo off\r\necho demo version 1.2.3, extra metadata\r\n"
        } else {
            b"#!/bin/sh\nprintf 'demo version 1.2.3, extra metadata\\n'\n"
        };
        dotfiles_common::fs::write_executable(&build_script, script_bytes).expect("write script");
        dotfiles_common::fs::write_executable(&file_script, script_bytes).expect("write script");

        assert_eq!(
            version_status(&ctx, &build_tool, &["demo".into()], Some(&build_script)),
            ("1.2.3".into(), false)
        );
        assert_eq!(
            version_status(
                &ctx,
                &file_tool,
                &["version-script".into()],
                Some(&file_script)
            ),
            ("installed".into(), false)
        );
        assert_eq!(
            version_status(&ctx, &build_tool, &["demo".into()], None),
            ("missing".into(), true)
        );

        let required_tool = tool("version-script", Action::Required);
        assert_eq!(
            version_status(
                &ctx,
                &required_tool,
                &["version-script".into()],
                Some(&file_script)
            ),
            ("1.2.3".into(), false)
        );
    }
}
