const bootstrap = @import("bootstrap");

const m = bootstrap.manifest;

pub const tools = [_]m.Tool{
    m.tool("chezmoi", &.{
        m.bin("chezmoi", &.{ "chezmoi", "--version" }),
    }, m.script(
        m.scriptCommand("https://get.chezmoi.io", "install.sh", &.{ "sh", "{file}", "-b", "{bin_dir}" }),
        m.scriptCommand("https://get.chezmoi.io/ps1", "install.ps1", &.{
            "pwsh",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            "{file}",
            "-BinDir",
            "{bin_dir}",
        }),
    )),

    m.tool("uv", &.{
        m.bin("uv", &.{ "uv", "--version" }),
        m.bin("uvx", &.{ "uvx", "--version" }),
    }, m.archive(m.githubLatest("astral-sh/uv", "v", "uv-{platform}.tar.gz"), &.{
        m.archivePlatform(m.macosAarch64(), "aarch64-apple-darwin", .tar_gz, 1, &.{
            m.link("uv", "uv"),
            m.link("uvx", "uvx"),
        }, &.{}),
        m.archivePlatform(m.linuxAarch64(), "aarch64-unknown-linux-gnu", .tar_gz, 1, &.{
            m.link("uv", "uv"),
            m.link("uvx", "uvx"),
        }, &.{}),
        m.archivePlatform(m.linuxX8664(), "x86_64-unknown-linux-gnu", .tar_gz, 1, &.{
            m.link("uv", "uv"),
            m.link("uvx", "uvx"),
        }, &.{}),
        .{
            .when = m.windowsX8664(),
            .platform = "x86_64-pc-windows-msvc",
            .source = m.githubLatest("astral-sh/uv", "v", "uv-{platform}.zip"),
            .kind = .zip,
            .strip_components = 1,
            .links = &.{
                m.link("uv", "uv.exe"),
                m.link("uvx", "uvx.exe"),
            },
        },
    })),

    m.tool("zig", &.{
        m.bin("zig", &.{ "zig", "version" }),
    }, m.required()),

    m.tool("rustup", &.{
        m.bin("rustup", &.{ "rustup", "--version" }),
        m.bin("cargo", &.{ "cargo", "--version" }),
        m.bin("rustc", &.{ "rustc", "--version" }),
        m.bin("rustfmt", &.{ "rustfmt", "--version" }),
        m.bin("cargo-clippy", &.{ "cargo", "clippy", "--version" }),
        m.bin("rust-analyzer", &.{ "rust-analyzer", "--version" }),
    }, m.rustupToolchain(.{
        .manager_bin = "rustup",
        .name = "stable",
        .name_env = "BOOTSTRAP_RUST_TOOLCHAIN",
        .bin_dir = .{ .env_var = "CARGO_HOME", .home_relative = ".cargo/bin" },
        .components = &.{ "rustfmt", "clippy", "rust-analyzer", "rust-src" },
        .install = .{
            .unix = .{
                .url = "https://sh.rustup.rs",
                .file = "install.sh",
                .argv = &.{
                    "sh",
                    "{file}",
                    "-y",
                    "--no-modify-path",
                    "--profile",
                    "minimal",
                    "--default-toolchain",
                    "{toolchain}",
                    "{components}",
                },
            },
            .windows = .{
                .url = "https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe",
                .file = "rustup-init.exe",
                .argv = &.{
                    "{file}",
                    "-y",
                    "--no-modify-path",
                    "--profile",
                    "minimal",
                    "--default-toolchain",
                    "{toolchain}",
                    "{components}",
                },
            },
        },
        .update_argv = &.{
            "{manager_bin}",
            "toolchain",
            "install",
            "{toolchain}",
            "--profile",
            "minimal",
            "{components}",
        },
        .active_argv = &.{ "{manager_bin}", "show", "active-toolchain" },
        .default_argv = &.{ "{manager_bin}", "default", "{toolchain}" },
        .component_argv = &.{ "--component", "{component}" },
    })),

    m.tool("zls", &.{
        m.bin("zls", &.{ "zls", "--version" }),
    }, m.archive(m.githubLatest("zigtools/zls", "", "zls-{platform}.tar.xz"), &.{
        m.archivePlatform(m.macosAarch64(), "aarch64-macos", .tar_xz, 0, &.{m.link("zls", "zls")}, &.{}),
        m.archivePlatform(m.linuxAarch64(), "aarch64-linux", .tar_xz, 0, &.{m.link("zls", "zls")}, &.{}),
        m.archivePlatform(m.linuxX8664(), "x86_64-linux", .tar_xz, 0, &.{m.link("zls", "zls")}, &.{}),
        .{
            .when = m.windowsX8664(),
            .platform = "x86_64-windows",
            .source = m.githubLatest("zigtools/zls", "", "zls-{platform}.zip"),
            .kind = .zip,
            .strip_components = 0,
            .links = &.{m.link("zls", "zls.exe")},
        },
    })),

    m.tool("ziglint", &.{
        m.bin("ziglint", &.{ "sh", "-c", "ziglint --version 2>&1" }),
    }, m.archive(m.githubLatest("rockorager/ziglint", "v", "ziglint-{platform}.tar.gz"), &.{
        m.archivePlatform(m.macosAarch64(), "aarch64-macos", .tar_gz, 0, &.{m.link("ziglint", "ziglint")}, &.{}),
        m.archivePlatform(m.linuxAarch64(), "aarch64-linux", .tar_gz, 0, &.{m.link("ziglint", "ziglint")}, &.{}),
        m.archivePlatform(m.linuxX8664(), "x86_64-linux", .tar_gz, 0, &.{m.link("ziglint", "ziglint")}, &.{}),
        .{
            .when = m.windowsX8664(),
            .platform = "x86_64-windows",
            .source = m.githubLatest("rockorager/ziglint", "v", "ziglint-{platform}.zip"),
            .kind = .zip,
            .strip_components = 0,
            .links = &.{m.link("ziglint", "ziglint.exe")},
        },
    })),

    m.tool("node", &.{
        m.bin("node", &.{ "node", "--version" }),
        m.bin("npm", &.{ "npm", "--version" }),
        m.bin("npx", &.{ "npx", "--version" }),
    }, m.archive(
        m.nodeLatest(
            "https://nodejs.org/dist/index.json",
            "https://nodejs.org/dist/{version}/node-{version}-{platform}.tar.xz",
        ),
        &.{
            m.archivePlatform(m.macosAarch64(), "darwin-arm64", .tar_xz, 1, &.{
                m.link("node", "bin/node"),
                m.link("npm", "bin/npm"),
                m.link("npx", "bin/npx"),
            }, &.{}),
            m.archivePlatform(m.linuxAarch64(), "linux-arm64-musl", .tar_xz, 1, &.{
                m.link("node", "bin/node"),
                m.link("npm", "bin/npm"),
                m.link("npx", "bin/npx"),
            }, &.{}),
            m.archivePlatform(m.linuxX8664(), "linux-x64-musl", .tar_xz, 1, &.{
                m.link("node", "bin/node"),
                m.link("npm", "bin/npm"),
                m.link("npx", "bin/npx"),
            }, &.{}),
            .{
                .when = m.windowsX8664(),
                .platform = "win-x64",
                .source = m.nodeLatest(
                    "https://nodejs.org/dist/index.json",
                    "https://nodejs.org/dist/{version}/node-{version}-{platform}.zip",
                ),
                .kind = .zip,
                .strip_components = 1,
                .links = &.{
                    m.link("node", "node-{version}-{platform}/node.exe"),
                    m.link("npm", "node-{version}-{platform}/npm.cmd"),
                    m.link("npx", "node-{version}-{platform}/npx.cmd"),
                },
            },
        },
    )),

    m.tool("bun", &.{
        m.bin("bun", &.{ "bun", "--version" }),
        m.bin("bunx", &.{ "bunx", "--version" }),
    }, m.archive(m.githubLatest("oven-sh/bun", "bun-v", "bun-{platform}.zip"), &.{
        m.archivePlatform(m.macosAarch64(), "darwin-aarch64", .zip, 0, &.{
            m.link("bun", "bun-{platform}/bun"),
            m.link("bunx", "bun-{platform}/bun"),
        }, &.{}),
        m.archivePlatform(m.linuxAarch64(), "linux-aarch64", .zip, 0, &.{
            m.link("bun", "bun-{platform}/bun"),
            m.link("bunx", "bun-{platform}/bun"),
        }, &.{}),
        m.archivePlatform(m.linuxX8664(), "linux-x64", .zip, 0, &.{
            m.link("bun", "bun-{platform}/bun"),
            m.link("bunx", "bun-{platform}/bun"),
        }, &.{}),
        m.archivePlatform(m.windowsX8664(), "windows-x64", .zip, 0, &.{
            m.link("bun", "bun-{platform}/bun.exe"),
            m.link("bunx", "bun-{platform}/bun.exe"),
        }, &.{}),
    })),

    m.tool("vscode", &.{
        m.bin("code", &.{ "code", "--version" }),
    }, m.archive(m.direct("latest", "https://update.code.visualstudio.com/latest/{platform}/stable"), &.{
        m.archivePlatform(m.macosAarch64(), "darwin-arm64", .zip, 0, &.{
            m.link("code", "Visual Studio Code.app/Contents/Resources/app/bin/code"),
        }, &.{
            m.link("Visual Studio Code.app", "Visual Studio Code.app"),
        }),
        m.archivePlatform(m.linuxAarch64(), "linux-arm64", .tar_gz, 1, &.{
            m.link("code", "bin/code"),
        }, &.{}),
        m.archivePlatform(m.linuxX8664(), "linux-x64", .tar_gz, 1, &.{
            m.link("code", "bin/code"),
        }, &.{}),
    })),

    m.tool("yt-dlp", &.{
        m.bin("yt-dlp", &.{ "yt-dlp", "--version" }),
    }, m.uvPackage("yt-dlp")),

    .{
        .name = "yt-dlp-script",
        .platforms = &.{ .macos, .linux },
        .bins = &.{
            m.bin("yt-dlp-script", &.{
                "sh",
                "-c",
                "command -v yt-dlp-script >/dev/null && printf installed",
            }),
        },
        .action = m.script(m.scriptCommand(
            "https://raw.githubusercontent.com/euvlok/pkgs/HEAD/pkgs/by-name/yt/yt-dlp-script/yt-dlp-script.nu",
            "yt-dlp-script",
            &.{
                "sh",
                "-c",
                \\set -eu
                \\script_dir='{opt_dir}/yt-dlp-script/latest'
                \\script_path="$script_dir/yt-dlp-script.nu"
                \\wrapper='{bin_dir}/yt-dlp-script'
                \\mkdir -p "$script_dir"
                \\install -m 0644 '{file}' "$script_path"
                \\cat > "$wrapper" <<EOF
                \\#!/bin/sh
                \\unset PROMPT_MULTILINE_INDICATOR
                \\exec nu '$script_path' "\$@"
                \\EOF
                \\chmod 0755 "$wrapper"
            },
        ), null),
    },

    m.tool("ruff", &.{
        m.bin("ruff", &.{ "ruff", "--version" }),
    }, m.uvPackage("ruff")),

    m.tool("ty", &.{
        m.bin("ty", &.{ "ty", "--version" }),
    }, m.uvPackage("ty")),

    .{
        .name = "gh-hide-comment",
        .platforms = &.{ .macos, .linux, .windows },
        .bins = &.{
            m.bin("gh-hide-comment", &.{
                "sh",
                "-c",
                "command -v gh-hide-comment >/dev/null && printf installed",
            }),
        },
        .action = m.zigBuild("pkgs/gh-hide-comment"),
    },

    .{
        .name = "zellij-theme-tools",
        .platforms = &.{ .macos, .linux },
        .bins = &.{
            m.bin("codex-zellij-theme", &.{
                "sh",
                "-c",
                "command -v codex-zellij-theme >/dev/null && printf installed",
            }),
            m.bin("zellij-auto-theme", &.{
                "sh",
                "-c",
                "command -v zellij-auto-theme >/dev/null && printf installed",
            }),
        },
        .action = m.zigBuild("pkgs/zellij-theme-tools"),
    },

    .{
        .name = "lenovo-con-mode",
        .platforms = &.{ .linux, .windows },
        .requires = &.{.lenovo_laptop},
        .bins = &.{
            m.bin("lenovo-con-mode", &.{
                "sh",
                "-c",
                "command -v lenovo-con-mode >/dev/null && printf installed",
            }),
        },
        .action = m.zigBuild("pkgs/lenovo-con-mode"),
    },
};
