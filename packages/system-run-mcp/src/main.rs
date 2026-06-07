mod command;
mod output;
mod path_probe;
mod process;
mod server;

use rmcp::{ServiceExt, transport::stdio};
use server::SystemRunServer;

#[tokio::main]
async fn main() {
    if handle_static_arg() {
        return;
    }

    if let Err(err) = run().await {
        eprintln!("system-run-mcp: {err}");
        std::process::exit(1);
    }
}

fn handle_static_arg() -> bool {
    match std::env::args().nth(1).as_deref() {
        Some("--version" | "-V") => {
            println!("system-run-mcp {}", env!("CARGO_PKG_VERSION"));
            true
        }
        Some("--help" | "-h") => {
            println!("system-run-mcp {}", env!("CARGO_PKG_VERSION"));
            println!("Run the system-run MCP server over stdio.");
            true
        }
        _ => false,
    }
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let service = SystemRunServer::new().serve(stdio()).await?;
    service.waiting().await?;
    Ok(())
}
