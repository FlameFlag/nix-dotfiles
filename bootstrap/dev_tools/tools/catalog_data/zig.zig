const bootstrap = @import("bootstrap");

const m = bootstrap.manifest;

pub const tool: m.Tool = m.tool("zig", &.{
    m.bin("zig", &.{ "zig", "version" }),
}, m.required());
