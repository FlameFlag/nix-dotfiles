use std::path::Path;

use bootstrap_core::catalog::{Action, Catalog};
use bootstrap_core::platform::Host;
use bootstrap_core::{Context, catalog, doctor, install, setup};
use clap::CommandFactory;
use comfy_table::{Cell, Table, presets::UTF8_FULL_CONDENSED};
use serde_json::json;

use crate::cli::{Cli, Command, GlobalArgs, OutputFormat, PathsArgs, ToolsArgs};
use crate::completions;

pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

pub fn run_bootstrap_cli(cli: Cli) -> Result<()> {
    let Cli { command, global } = cli;
    match command {
        Command::Completions(args) => {
            completions::generate_bootstrap_completions(args.shell);
            Ok(())
        }
        Command::Man => {
            clap_mangen::Man::new(Cli::command()).render(&mut std::io::stdout())?;
            Ok(())
        }
        Command::Markdown => {
            println!("{}", clap_markdown::help_markdown::<Cli>());
            Ok(())
        }
        Command::Install(args) => {
            let ctx = context(&global)?;
            install::install_all(&ctx, args.mode.into())?;
            Ok(())
        }
        Command::Bootstrap => {
            let ctx = context(&global)?;
            setup::bootstrap(&ctx)?;
            Ok(())
        }
        Command::SelfInstall => {
            let ctx = context(&global)?;
            setup::install_current_exe(&ctx)?;
            Ok(())
        }
        Command::Update => {
            let ctx = context(&global)?;
            install::install_all(&ctx, install::Policy::UpdateAll)?;
            Ok(())
        }
        Command::Doctor(args) => {
            let ctx = context(&global)?;
            let report = doctor::report(&ctx)?;
            print_doctor(&report, args.format)?;
            if report.has_issues() && !args.no_fail {
                return Err(doctor::DoctorError::FoundIssues.into());
            }
            Ok(())
        }
        Command::Tools(args) => {
            let ctx = context(&global)?;
            print_tools(&ctx, &args)
        }
        Command::Paths(args) => {
            let ctx = context(&global)?;
            print_paths(&ctx, args)
        }
        Command::Schema => {
            println!("{}", catalog::schema_json()?);
            Ok(())
        }
    }
}

fn context(global: &GlobalArgs) -> Result<Context> {
    let repo_dir = global
        .repo_dir
        .clone()
        .map_or_else(std::env::current_dir, Ok)?;
    Ok(Context::new(repo_dir)?)
}

fn print_doctor(report: &doctor::Report, format: OutputFormat) -> Result<()> {
    match format {
        OutputFormat::Table => {
            doctor::print_report(report);
            print_doctor_summary(report);
        }
        OutputFormat::Json => {
            println!("{}", serde_json::to_string_pretty(report)?);
        }
    }
    Ok(())
}

fn print_doctor_summary(report: &doctor::Report) {
    let issue_count = report.rows.iter().filter(|row| row.failed).count();
    let ok_count = report.rows.len().saturating_sub(issue_count);
    if issue_count == 0 {
        println!("doctor: {ok_count} tools healthy");
    } else {
        println!("doctor: {ok_count} healthy, {issue_count} need attention");
    }
}

fn print_tools(ctx: &Context, args: &ToolsArgs) -> Result<()> {
    let catalog = Catalog::load(ctx.catalog_path())?;
    let host = Host::current();
    let rows = catalog
        .tools
        .iter()
        .filter(|tool| args.all || tool.supports_host(host))
        .map(|tool| {
            let bins = tool
                .bins
                .iter()
                .map(|bin| bin.name.clone())
                .collect::<Vec<_>>();
            let supported = tool.supports_host(host);
            json!({
                "name": tool.name,
                "phase": phase_label(tool.phase()),
                "action": action_label(&tool.action),
                "bins": bins,
                "supported": supported,
            })
        })
        .collect::<Vec<_>>();

    match args.format {
        OutputFormat::Table => {
            let mut table = Table::new();
            table.load_preset(UTF8_FULL_CONDENSED);
            table.set_header(["tool", "phase", "action", "bins", "host"]);
            for row in &rows {
                table.add_row([
                    Cell::new(row["name"].as_str().unwrap_or_default()),
                    Cell::new(row["phase"].as_str().unwrap_or_default()),
                    Cell::new(row["action"].as_str().unwrap_or_default()),
                    Cell::new(display_bins(&row["bins"])),
                    Cell::new(if row["supported"].as_bool().unwrap_or(false) {
                        "yes"
                    } else {
                        "no"
                    }),
                ]);
            }
            println!("{table}");
            println!("tools: {} catalog entries", rows.len());
        }
        OutputFormat::Json => {
            println!("{}", serde_json::to_string_pretty(&rows)?);
        }
    }
    Ok(())
}

fn print_paths(ctx: &Context, args: PathsArgs) -> Result<()> {
    let catalog_path = ctx.catalog_path();
    let rows = [
        ("repo", display_path(&ctx.repo_dir)),
        ("catalog", display_path(&catalog_path)),
        ("home", display_path(&ctx.home)),
        ("bin", display_path(&ctx.bin_dir)),
        ("opt", display_path(&ctx.opt_dir)),
    ];

    match args.format {
        OutputFormat::Table => {
            let mut table = Table::new();
            table.load_preset(UTF8_FULL_CONDENSED);
            table.set_header(["name", "path"]);
            for (name, path) in rows {
                table.add_row([Cell::new(name), Cell::new(path)]);
            }
            println!("{table}");
        }
        OutputFormat::Json => {
            let value = json!({
                "repo": ctx.repo_dir,
                "catalog": ctx.catalog_path(),
                "home": ctx.home,
                "bin": ctx.bin_dir,
                "opt": ctx.opt_dir,
            });
            println!("{}", serde_json::to_string_pretty(&value)?);
        }
    }
    Ok(())
}

fn phase_label(phase: bootstrap_core::catalog::Phase) -> &'static str {
    match phase {
        bootstrap_core::catalog::Phase::Prerequisites => "prerequisites",
        bootstrap_core::catalog::Phase::Archives => "archives",
        bootstrap_core::catalog::Phase::Packages => "packages",
        bootstrap_core::catalog::Phase::Builds => "builds",
    }
}

fn action_label(action: &Action) -> &'static str {
    match action {
        Action::Required => "required",
        Action::Archive(_) => "archive",
        Action::File(_) => "file",
        Action::Package(_) => "package",
        Action::Build(_) => "build",
        Action::SourceBuild(_) => "source-build",
        Action::Toolchain(_) => "toolchain",
    }
}

fn display_path(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn display_bins(value: &serde_json::Value) -> String {
    value
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(serde_json::Value::as_str)
        .collect::<Vec<_>>()
        .join(", ")
}

#[cfg(test)]
mod tests {
    use super::*;
    use bootstrap_core::catalog::{
        ArchiveAction, BuildAction, FileAction, PackageAction, Source, SourceBuildAction,
        ToolchainAction, ToolchainBinDir, ToolchainInstall,
    };

    #[test]
    fn action_labels_cover_catalog_action_variants() {
        assert_eq!(action_label(&Action::Required), "required");
        assert_eq!(
            action_label(&Action::Archive(ArchiveAction {
                source: None,
                kind: None,
                strip_components: None,
                links: vec![],
                app_links: vec![],
                platforms: vec![],
            })),
            "archive"
        );
        assert_eq!(
            action_label(&Action::File(FileAction {
                source: Source::Direct {
                    version: "1".into(),
                    url: "https://example.invalid/tool".into(),
                },
                file: "tool".into(),
                links: vec![],
            })),
            "file"
        );
        assert_eq!(
            action_label(&Action::Package(PackageAction {
                name: "tool".into(),
                install_argv: vec!["manager".into(), "install".into()],
                inventory: None,
            })),
            "package"
        );
        assert_eq!(
            action_label(&Action::Build(BuildAction {
                path: "tool".into(),
                argv: vec!["cargo".into(), "build".into()],
                links: vec![],
            })),
            "build"
        );
        assert_eq!(
            action_label(&Action::SourceBuild(SourceBuildAction {
                version: "1".into(),
                kind: None,
                strip_components: None,
                argv: vec![],
                sandbox_home: false,
                links: vec![],
                platforms: vec![],
            })),
            "source-build"
        );
        assert_eq!(
            action_label(&Action::Toolchain(Box::new(ToolchainAction {
                manager_bin: "rustup".into(),
                name: "stable".into(),
                name_env: None,
                bin_dir: ToolchainBinDir {
                    env_var: None,
                    home_relative: ".cargo/bin".into(),
                },
                components: vec!["rustfmt".into()],
                install: ToolchainInstall {
                    file: String::new(),
                    argv: vec![],
                    platforms: vec![],
                },
                update_argv: vec!["rustup".into(), "update".into()],
                active_argv: vec!["rustup".into(), "show".into()],
                default_argv: vec!["rustup".into(), "default".into()],
                component_argv: vec!["--component".into(), "{component}".into()],
            }))),
            "toolchain"
        );
    }

    #[test]
    fn display_bins_joins_array_strings() {
        assert_eq!(display_bins(&json!(["one", "two"])), "one, two");
        assert_eq!(display_bins(&json!("not an array")), "");
    }

    #[test]
    fn print_tools_reads_catalog_and_formats_json() {
        let temp = tempfile::tempdir().expect("tempdir");
        let repo = temp.path().join("repo");
        let catalog_dir = repo.join("bootstrap");
        fs_err::create_dir_all(&catalog_dir).expect("create catalog dir");
        fs_err::write(
            catalog_dir.join("tools.toml"),
            r#"
[[tools]]
name = "demo"

[[tools.bins]]
name = "demo"
version_argv = ["demo", "--version"]

[tools.action]
type = "required"
"#,
        )
        .expect("write catalog");
        let ctx = Context::new_with_home(&repo, Some(temp.path().join("home"))).expect("context");

        print_tools(
            &ctx,
            &ToolsArgs {
                all: true,
                format: OutputFormat::Json,
            },
        )
        .expect("print tools");
    }
}
