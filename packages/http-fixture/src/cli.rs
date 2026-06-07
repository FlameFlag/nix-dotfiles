use std::net::SocketAddr;
use std::path::PathBuf;

use clap::Parser;

pub(crate) const DEFAULT_CONFIG_PATH: &str = "/etc/http-fixture/config.toml";
pub(crate) const DEFAULT_LISTEN: &str = "127.0.0.1:8080";

#[derive(Debug, Parser)]
#[command(
    name = "http-fixture",
    about = "Small local fixture HTTP server",
    version
)]
pub(crate) struct Cli {
    /// TOML configuration path.
    #[arg(long, env = "HTTP_FIXTURE_CONFIG", default_value = DEFAULT_CONFIG_PATH)]
    pub(crate) config: PathBuf,

    /// Address to listen on. Overrides the TOML listen value when set.
    #[arg(long)]
    pub(crate) listen: Option<SocketAddr>,
}
