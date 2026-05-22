use std::path::PathBuf;

use bootstrap_core::install;
use clap::builder::styling::{AnsiColor, Color, Effects, Style, Styles};
use clap::{Args, Parser, Subcommand, ValueEnum, ValueHint};

pub const BIN_NAME: &str = "bootstrap";

const HEADER: Style = Style::new()
    .fg_color(Some(Color::Ansi(AnsiColor::Green)))
    .effects(Effects::BOLD);
const USAGE: Style = Style::new()
    .fg_color(Some(Color::Ansi(AnsiColor::Cyan)))
    .effects(Effects::BOLD);
const LITERAL: Style = Style::new()
    .fg_color(Some(Color::Ansi(AnsiColor::Blue)))
    .effects(Effects::BOLD);
const PLACEHOLDER: Style = Style::new().fg_color(Some(Color::Ansi(AnsiColor::Yellow)));
const ERROR: Style = Style::new()
    .fg_color(Some(Color::Ansi(AnsiColor::Red)))
    .effects(Effects::BOLD);
const VALID: Style = Style::new().fg_color(Some(Color::Ansi(AnsiColor::Green)));
const INVALID: Style = Style::new().fg_color(Some(Color::Ansi(AnsiColor::Yellow)));

pub const CLAP_STYLING: Styles = Styles::styled()
    .header(HEADER)
    .usage(USAGE)
    .literal(LITERAL)
    .placeholder(PLACEHOLDER)
    .error(ERROR)
    .valid(VALID)
    .invalid(INVALID);

#[derive(Debug, Parser)]
#[command(
    name = BIN_NAME,
    about = "Install and inspect dotfiles development tools",
    long_about = "Install, update, inspect, and document the dotfiles bootstrap tool catalog.",
    version,
    styles = CLAP_STYLING,
    max_term_width = 100,
    propagate_version = true,
    arg_required_else_help = true,
    subcommand_required = true,
    subcommand_help_heading = "Commands",
    after_help = "Examples:\n  bootstrap bootstrap\n  bootstrap install --mode all\n  bootstrap doctor --format json\n  bootstrap tools --all\n  bootstrap completions zsh"
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,

    #[command(flatten)]
    pub global: GlobalArgs,
}

#[derive(Debug, Args)]
#[command(next_help_heading = "Global Options")]
pub struct GlobalArgs {
    /// Repository root that contains bootstrap/tools.toml.
    #[arg(
        long,
        global = true,
        env = "BOOTSTRAP_REPO_DIR",
        value_name = "DIR",
        value_hint = ValueHint::DirPath
    )]
    pub repo_dir: Option<PathBuf>,
}

#[derive(Debug, Subcommand)]
pub enum Command {
    #[command(
        about = "Install missing tools from the bootstrap catalog",
        visible_alias = "i",
        long_about = "Install bootstrap catalog entries that are missing or unhealthy. Use --mode all to reinstall or update every supported non-prerequisite tool."
    )]
    Install(InstallArgs),
    #[command(
        about = "Prepare this machine and install missing bootstrap tools",
        long_about = "Prepare this machine for dotfiles setup, install the current bootstrap binary, and ensure missing bootstrap tools are present."
    )]
    Bootstrap,
    #[command(
        name = "self-install",
        about = "Install the running bootstrap binary into the bootstrap bin directory"
    )]
    SelfInstall,
    #[command(about = "Reinstall or update every managed tool", visible_alias = "u")]
    Update,
    #[command(
        about = "Inspect tool availability, source, versions, and paths",
        visible_alias = "check"
    )]
    Doctor(DoctorArgs),
    #[command(
        about = "List tools declared in the bootstrap catalog",
        visible_alias = "ls"
    )]
    Tools(ToolsArgs),
    #[command(about = "Show resolved bootstrap paths and environment roots")]
    Paths(PathsArgs),
    #[command(about = "Print the bootstrap catalog JSON schema")]
    Schema,
    #[command(about = "Generate shell completions")]
    Completions(CompletionsArgs),
    #[command(about = "Generate a roff man page from the clap definition")]
    Man,
    #[command(about = "Generate Markdown reference docs from the clap definition")]
    Markdown,
}

#[derive(Debug, Args)]
#[command(next_help_heading = "Install Options")]
pub struct InstallArgs {
    /// Choose whether to install only unhealthy tools or refresh everything.
    #[arg(long, value_enum, default_value_t = InstallMode::Missing)]
    pub mode: InstallMode,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum InstallMode {
    Missing,
    All,
}

impl From<InstallMode> for install::Policy {
    fn from(value: InstallMode) -> Self {
        match value {
            InstallMode::Missing => Self::InstallMissing,
            InstallMode::All => Self::UpdateAll,
        }
    }
}

#[derive(Debug, Args)]
#[command(next_help_heading = "Doctor Options")]
pub struct DoctorArgs {
    /// Render the doctor report as a table or JSON.
    #[arg(long, value_enum, default_value_t = OutputFormat::Table)]
    pub format: OutputFormat,

    /// Print issues without returning a failing exit code.
    #[arg(long)]
    pub no_fail: bool,
}

#[derive(Debug, Args)]
#[command(next_help_heading = "Catalog Options")]
pub struct ToolsArgs {
    /// Include tools that do not support the current host.
    #[arg(long)]
    pub all: bool,

    /// Render the catalog overview as a table or JSON.
    #[arg(long, value_enum, default_value_t = OutputFormat::Table)]
    pub format: OutputFormat,
}

#[derive(Debug, Args)]
#[command(next_help_heading = "Path Options")]
pub struct PathsArgs {
    /// Render paths as a table or JSON.
    #[arg(long, value_enum, default_value_t = OutputFormat::Table)]
    pub format: OutputFormat,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum OutputFormat {
    Table,
    Json,
}

#[derive(Debug, Args)]
#[command(next_help_heading = "Completion Options")]
pub struct CompletionsArgs {
    #[arg(value_enum)]
    pub shell: CompletionShell,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum CompletionShell {
    Bash,
    Elvish,
    Fish,
    Nushell,
    Powershell,
    Zsh,
}
