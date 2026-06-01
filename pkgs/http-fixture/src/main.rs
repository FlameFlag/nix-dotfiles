mod app;
mod cli;
mod config;
mod error;
mod response;
mod route;
mod server;

use clap::Parser;

use crate::app::load_app;
use crate::cli::Cli;
use crate::error::Result;
use crate::server::serve;

fn main() {
    if let Err(err) = run(Cli::parse()) {
        eprintln!("error: {err}");
        std::process::exit(1);
    }
}

fn run(cli: Cli) -> Result<()> {
    let app = load_app(&cli)?;
    serve(&cli, &app)
}
