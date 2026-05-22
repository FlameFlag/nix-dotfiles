use std::path::{Path, PathBuf};

use crate::command::{warn_if_failed, write_command_text_if_available};
use crate::error::{Error, Result};
use crate::fs::write_text_if_changed;

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
        &duct::cmd("starship", ["init", "nu"]),
    )?;
    write_command_text_if_available(
        "zoxide",
        &home_dir.join(".cache/zoxide/init.nu"),
        &duct::cmd("zoxide", ["init", "nushell", "--cmd", "cd"]),
    )?;
    let atuin = home_dir.join(".local/share/atuin/init.nu");
    write_command_text_if_available(
        "atuin",
        &atuin,
        &duct::cmd("atuin", ["init", "nu", "--disable-up-arrow"]),
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
        if which::which(bin).is_err() {
            continue;
        }
        let path = home.join(".cache").join(dir).join(format!("init.{shell}"));
        let args = ["init", shell].into_iter().chain(suffix.iter().copied());
        let command = duct::cmd(bin, args);
        write_command_text_if_available(bin, &path, &command)?;
    }
    Ok(())
}

fn write_completion_files(home: &Path, shell: &str) -> Result<()> {
    let outdir = home.join(".cache").join(shell).join("completions");
    let prefix = if shell == "zsh" { "_" } else { "" };
    if which::which("atuin").is_ok() {
        let args = [
            "gen-completions".into(),
            "--shell".into(),
            shell.into(),
            "--out-dir".into(),
        ]
        .into_iter()
        .chain([outdir.as_os_str().to_os_string()]);
        warn_if_failed(
            "atuin completions",
            &duct::cmd("atuin", args).unchecked().run()?,
        );
    }

    for spec in COMPLETION_SPECS {
        if which::which(spec.bin).is_err() {
            continue;
        }
        let args = spec
            .before
            .iter()
            .copied()
            .chain([shell])
            .chain(spec.after.iter().copied());
        let output = duct::cmd(spec.argv0, args)
            .stdout_capture()
            .stderr_capture()
            .unchecked()
            .run()?;
        if !output.status.success() {
            warn_if_failed(spec.name, &output);
            continue;
        }
        write_text_if_changed(
            &outdir.join(format!("{prefix}{}", spec.name)),
            &String::from_utf8_lossy(&output.stdout),
        )?;
    }
    Ok(())
}
