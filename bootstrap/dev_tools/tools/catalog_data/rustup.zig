const bootstrap = @import("bootstrap");

const m = bootstrap.manifest;

pub const tool: m.Tool = m.tool("rustup", &.{
    m.bin("rustup", &.{ "rustup", "--version" }),
    m.bin("cargo", &.{ "cargo", "--version" }),
    m.bin("rustc", &.{ "rustc", "--version" }),
    m.bin("rustfmt", &.{ "rustfmt", "--version" }),
    m.bin("cargo-clippy", &.{ "cargo-clippy", "--version" }),
    m.bin("rust-analyzer", &.{ "rust-analyzer", "--version" }),
}, m.toolchainAction(.{
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
}));
