const bootstrap = @import("bootstrap");

const m = bootstrap.manifest;

pub const tool: m.Tool = m.tool("yt-dlp", &.{
    m.bin("yt-dlp", &.{ "yt-dlp", "--version" }),
}, m.uvPackage("yt-dlp"));
