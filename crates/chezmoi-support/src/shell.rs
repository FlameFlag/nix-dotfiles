use std::path::{Path, PathBuf};

use crate::command::{command_output, warn_if_failed, write_command_text_if_available};
use crate::error::{Error, Result};
use dotfiles_common::fs::write_text_if_changed;
use dotfiles_common::process;

struct CompletionSpec {
    bin: &'static str,
    name: &'static str,
    argv0: &'static str,
    before: &'static [&'static str],
    after: &'static [&'static str],
}

const COMPLETION_SPECS: &[CompletionSpec] = &[
    CompletionSpec {
        bin: "bootstrap",
        name: "bootstrap",
        argv0: "bootstrap",
        before: &["completions"],
        after: &[],
    },
    CompletionSpec {
        bin: "chezmoi-support",
        name: "chezmoi-support",
        argv0: "chezmoi-support",
        before: &["completions"],
        after: &[],
    },
    CompletionSpec {
        bin: "gh-hide-comment",
        name: "gh-hide-comment",
        argv0: "gh-hide-comment",
        before: &["--completions"],
        after: &[],
    },
    CompletionSpec {
        bin: "lenovo-con-mode",
        name: "lenovo-con-mode",
        argv0: "lenovo-con-mode",
        before: &["--completions"],
        after: &[],
    },
    CompletionSpec {
        bin: "chezmoi",
        name: "chezmoi",
        argv0: "chezmoi",
        before: &["completion"],
        after: &[],
    },
    CompletionSpec {
        bin: "jj",
        name: "jj",
        argv0: "jj",
        before: &["util", "completion"],
        after: &[],
    },
    CompletionSpec {
        bin: "zellij",
        name: "zellij",
        argv0: "zellij",
        before: &["setup", "--generate-completion"],
        after: &[],
    },
    CompletionSpec {
        bin: "starship",
        name: "starship",
        argv0: "starship",
        before: &["completions"],
        after: &[],
    },
    CompletionSpec {
        bin: "deno",
        name: "deno",
        argv0: "deno",
        before: &["completions"],
        after: &[],
    },
    CompletionSpec {
        bin: "delta",
        name: "delta",
        argv0: "delta",
        before: &["--generate-completion"],
        after: &[],
    },
    CompletionSpec {
        bin: "tv",
        name: "tv",
        argv0: "tv",
        before: &["completions"],
        after: &[],
    },
    CompletionSpec {
        bin: "rustup",
        name: "rustup",
        argv0: "rustup",
        before: &["completions"],
        after: &[],
    },
    CompletionSpec {
        bin: "rustup",
        name: "cargo",
        argv0: "rustup",
        before: &["completions"],
        after: &["cargo"],
    },
];

pub fn nushell_init() -> Result<()> {
    let home_dir = shell_home_dir()?;
    for dir in [".cache/starship", ".cache/zoxide", ".local/share/atuin"] {
        fs_err::create_dir_all(home_dir.join(dir))?;
    }
    write_command_text_if_available(
        "starship",
        &home_dir.join(".cache/starship/init.nu"),
        &process::argv(["starship", "init", "nu"]),
    )?;
    write_command_text_if_available(
        "zoxide",
        &home_dir.join(".cache/zoxide/init.nu"),
        &process::argv(["zoxide", "init", "nushell", "--cmd", "cd"]),
    )?;
    let atuin = home_dir.join(".local/share/atuin/init.nu");
    write_command_text_if_available(
        "atuin",
        &atuin,
        &process::argv(["atuin", "init", "nu", "--disable-up-arrow"]),
    )?;
    if let Ok(current) = fs_err::read_to_string(&atuin) {
        write_text_if_changed(
            &atuin,
            &current.replace("$cmd e>| complete", "$cmd | complete"),
        )?;
    }
    Ok(())
}

pub fn shell_init() -> Result<()> {
    let home_dir = shell_home_dir()?;
    for dir in [
        ".cache/starship",
        ".cache/zoxide",
        ".cache/atuin",
        ".cache/television",
        ".cache/zsh/completions",
        ".cache/bash/completions",
    ] {
        fs_err::create_dir_all(home_dir.join(dir))?;
    }
    for shell in ["zsh", "bash"] {
        write_init_files(&home_dir, shell)?;
        write_completion_files(&home_dir, shell)?;
    }
    Ok(())
}

fn shell_home_dir() -> Result<PathBuf> {
    let base_dirs = directories::BaseDirs::new().ok_or(Error::MissingEnv("HOME"))?;
    Ok(std::env::var_os("CHEZMOI_HOME_DIR")
        .map(PathBuf::from)
        .filter(|path| !path.as_os_str().is_empty())
        .unwrap_or_else(|| base_dirs.home_dir().to_path_buf()))
}

fn write_init_files(home: &Path, shell: &str) -> Result<()> {
    let commands: [(&str, &str, &[&str]); 4] = [
        ("starship", "starship", &[]),
        ("zoxide", "zoxide", &[]),
        ("atuin", "atuin", &["--disable-up-arrow"]),
        ("tv", "television", &[]),
    ];
    for (bin, dir, suffix) in commands {
        if process::path_of(bin).is_none() {
            continue;
        }
        let path = home.join(".cache").join(dir).join(format!("init.{shell}"));
        let args = ["init", shell].into_iter().chain(suffix.iter().copied());
        let command = process::argv(std::iter::once(bin).chain(args));
        write_command_text_if_available(bin, &path, &command)?;
    }
    Ok(())
}

fn write_completion_files(home: &Path, shell: &str) -> Result<()> {
    let outdir = home.join(".cache").join(shell).join("completions");
    let prefix = if shell == "zsh" { "_" } else { "" };
    if process::path_of("atuin").is_some() {
        let args = [
            "atuin".to_owned(),
            "gen-completions".to_owned(),
            "--shell".to_owned(),
            shell.to_owned(),
            "--out-dir".to_owned(),
            outdir.to_string_lossy().into_owned(),
        ]
        .into_iter()
        .collect::<Vec<_>>();
        warn_if_failed("atuin completions", &command_output(&args)?);
    }

    for spec in COMPLETION_SPECS {
        if process::path_of(spec.bin).is_none() {
            continue;
        }
        let command = process::argv(
            std::iter::once(spec.argv0)
                .chain(spec.before.iter().copied())
                .chain([shell])
                .chain(spec.after.iter().copied()),
        );
        let output = command_output(&command)?;
        if !output.status.success() {
            warn_if_failed(spec.name, &output);
            continue;
        }
        write_text_if_changed(
            outdir.join(format!("{prefix}{}", spec.name)),
            &String::from_utf8_lossy(&output.stdout),
        )?;
    }
    Ok(())
}
