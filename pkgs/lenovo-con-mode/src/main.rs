#![cfg_attr(test, allow(clippy::expect_used, clippy::panic, clippy::unwrap_used))]

mod platform;

use clap::{CommandFactory, Parser, ValueEnum};
use clap_complete_command::Shell;
use thiserror::Error;

use crate::platform::{is_supported_lenovo, read_mode, write_mode};

#[cfg(target_os = "linux")]
const CONSERVATION_MODE_PATH: &str = platform::CONSERVATION_MODE_PATH;
#[cfg(windows)]
const WINDOWS_ENERGY_DRV_PATH: &str = platform::WINDOWS_ENERGY_DRV_PATH;

#[derive(Debug, Clone, Copy, Parser)]
#[command(
    name = "lenovo-con-mode",
    about = "Toggle or set Lenovo Ideapad conservation mode",
    version
)]
struct Cli {
    #[arg(long, value_enum)]
    completions: Option<Shell>,

    #[arg(value_enum, default_value_t = Action::Toggle)]
    action: Action,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
enum Action {
    Status,
    On,
    Enable,
    Off,
    Disable,
    Toggle,
}

#[derive(Debug, Error)]
pub enum Error {
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[cfg(target_os = "linux")]
    #[error("conservation mode sysfs node not found: {CONSERVATION_MODE_PATH}")]
    LinuxNodeMissing,
    #[cfg(target_os = "linux")]
    #[error("permission denied reading or writing conservation mode; run as root")]
    LinuxPermissionDenied,
    #[cfg(windows)]
    #[error("Lenovo ACPI Virtual Power Controller device not found: {WINDOWS_ENERGY_DRV_PATH}")]
    WindowsDeviceMissing,
    #[cfg(windows)]
    #[error("permission denied changing Lenovo conservation mode; run as administrator")]
    WindowsPermissionDenied,
    #[cfg(windows)]
    #[error("Lenovo ACPI backend is unavailable on this Windows system")]
    WindowsBackendUnavailable,
    #[cfg(not(any(target_os = "linux", windows)))]
    #[error("unsupported operating system")]
    UnsupportedOs,
    #[cfg(target_os = "linux")]
    #[error("unexpected conservation mode value: {0}")]
    UnexpectedMode(String),
}

pub type Result<T> = std::result::Result<T, Error>;

fn main() {
    if let Err(err) = run_lenovo_con_mode(Cli::parse()) {
        eprintln!("error: {err}");
        std::process::exit(1);
    }
}

fn run_lenovo_con_mode(cli: Cli) -> Result<()> {
    if let Some(shell) = cli.completions {
        generate_lenovo_con_mode_completions(shell);
        return Ok(());
    }

    if !is_supported_lenovo()? {
        eprintln!(
            "info: Lenovo conservation mode is only supported on Lenovo laptops with a known Linux or Windows backend; skipping."
        );
        return Ok(());
    }

    let current = read_mode()?;
    let desired = match cli.action {
        Action::Status => None,
        Action::On | Action::Enable => Some(true),
        Action::Off | Action::Disable => Some(false),
        Action::Toggle => Some(!current),
    };
    let shown = match desired {
        Some(value) => {
            if value != current {
                write_mode(value)?;
            }
            value
        }
        None => current,
    };

    println!("Conservation Mode: {}", state_label(shown));
    Ok(())
}

fn generate_lenovo_con_mode_completions(shell: Shell) {
    generate_lenovo_con_mode_completions_to(shell, &mut std::io::stdout());
}

fn generate_lenovo_con_mode_completions_to(shell: Shell, writer: &mut impl std::io::Write) {
    let mut command = Cli::command();
    shell.generate(&mut command, writer);
}

const fn state_label(enabled: bool) -> &'static str {
    if enabled {
        "ENABLED (60% charge)"
    } else {
        "DISABLED (100% charge)"
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::ValueEnum;

    #[test]
    fn state_labels_match_old_tool() {
        assert_eq!(state_label(true), "ENABLED (60% charge)");
        assert_eq!(state_label(false), "DISABLED (100% charge)");
    }

    #[test]
    fn generates_all_lenovo_con_mode_completion_shells() {
        for &shell in Shell::value_variants() {
            let mut output = Vec::new();
            generate_lenovo_con_mode_completions_to(shell, &mut output);
            assert!(!output.is_empty());
        }
    }
}
