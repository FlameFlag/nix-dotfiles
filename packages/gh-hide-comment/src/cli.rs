use clap::{Parser, ValueEnum};
use clap_complete_command::Shell;

#[derive(Debug, Parser)]
#[command(
    name = "gh-hide-comment",
    about = "Hide GitHub comments via the GraphQL minimizeComment mutation",
    version
)]
pub struct Cli {
    #[arg(long, value_enum)]
    pub completions: Option<Shell>,

    #[arg(long, value_enum, default_value_t = Reason::Outdated)]
    pub reason: Reason,

    pub urls: Vec<String>,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum Reason {
    Outdated,
    Duplicate,
    OffTopic,
    Resolved,
    Spam,
    Abuse,
}
