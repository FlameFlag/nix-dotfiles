const bootstrap = @import("bootstrap");

const m = bootstrap.manifest;

pub const tool: m.Tool = m.tool("bun", &.{
    m.bin("bun", &.{ "bun", "--version" }),
    m.bin("bunx", &.{ "bunx", "--version" }),
}, m.archive(m.githubLatest("oven-sh/bun", "bun-v", "bun-{platform}.zip"), &.{
    m.archivePlatform(m.macosAarch64(), "darwin-aarch64", .zip, 0, &.{
        m.link("bun", "bun-{platform}/bun"),
        m.link("bunx", "bun-{platform}/bun"),
    }, &.{}),
    m.archivePlatform(m.linuxAarch64(), "linux-aarch64-musl", .zip, 0, &.{
        m.link("bun", "bun-{platform}/bun"),
        m.link("bunx", "bun-{platform}/bun"),
    }, &.{}),
    m.archivePlatform(m.linuxX8664(), "linux-x64-musl", .zip, 0, &.{
        m.link("bun", "bun-{platform}/bun"),
        m.link("bunx", "bun-{platform}/bun"),
    }, &.{}),
    m.archivePlatform(m.windowsX8664(), "windows-x64", .zip, 0, &.{
        m.link("bun", "bun-{platform}/bun.exe"),
        m.link("bunx", "bun-{platform}/bun.exe"),
    }, &.{}),
}));
