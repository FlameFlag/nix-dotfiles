const bootstrap = @import("bootstrap");

const m = bootstrap.manifest;

pub const tool: m.Tool = m.tool("ruff", &.{
    m.bin("ruff", &.{ "ruff", "--version" }),
}, m.uvPackage("ruff"));
