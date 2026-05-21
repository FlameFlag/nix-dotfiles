const bootstrap = @import("bootstrap");

const m = bootstrap.manifest;

pub const tool: m.Tool = m.tool("chezmoi", &.{
    m.bin("chezmoi", &.{ "chezmoi", "--version" }),
}, m.script(
    m.scriptCommand("https://get.chezmoi.io", "install.sh", &.{
        "sh",
        "{file}",
        "-b",
        "{bin_dir}",
    }),
    m.scriptCommand("https://get.chezmoi.io/ps1", "install.ps1", &.{
        "pwsh",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        "{file}",
        "-BinDir",
        "{bin_dir}",
        "-NoModifyPath",
    }),
));
