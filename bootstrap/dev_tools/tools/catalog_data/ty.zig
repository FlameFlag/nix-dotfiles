const bootstrap = @import("bootstrap");

const m = bootstrap.manifest;

pub const tool: m.Tool = m.tool("ty", &.{
    m.bin("ty", &.{ "ty", "--version" }),
}, m.uvPackage("ty"));
