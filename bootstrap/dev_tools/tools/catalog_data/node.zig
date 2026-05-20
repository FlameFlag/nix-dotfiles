const bootstrap = @import("bootstrap");

const m = bootstrap.manifest;

pub const tool: m.Tool = m.tool("node", &.{
    m.bin("node", &.{ "node", "--version" }),
    m.bin("npm", &.{ "npm", "--version" }),
    m.bin("npx", &.{ "npx", "--version" }),
}, m.archive(
    m.versionIndex(
        "https://nodejs.org/dist/index.json",
        "https://nodejs.org/dist/{version}/node-{version}-{platform}.tar.xz",
    ),
    &.{
        m.archivePlatform(m.macosAarch64(), "darwin-arm64", .tar_xz, 1, &.{
            m.link("node", "bin/node"),
            m.link("npm", "bin/npm"),
            m.link("npx", "bin/npx"),
        }, &.{}),
        .{
            .when = m.linuxAarch64(),
            .platform = "linux-arm64-musl",
            .source = m.versionIndex(
                "https://unofficial-builds.nodejs.org/download/release/index.json",
                "https://unofficial-builds.nodejs.org/download/release/{version}/node-{version}-{platform}.tar.xz",
            ),
            .kind = .tar_xz,
            .strip_components = 1,
            .links = &.{
                m.link("node", "bin/node"),
                m.link("npm", "bin/npm"),
                m.link("npx", "bin/npx"),
            },
        },
        .{
            .when = m.linuxX8664(),
            .platform = "linux-x64-musl",
            .source = m.versionIndex(
                "https://unofficial-builds.nodejs.org/download/release/index.json",
                "https://unofficial-builds.nodejs.org/download/release/{version}/node-{version}-{platform}.tar.xz",
            ),
            .kind = .tar_xz,
            .strip_components = 1,
            .links = &.{
                m.link("node", "bin/node"),
                m.link("npm", "bin/npm"),
                m.link("npx", "bin/npx"),
            },
        },
        .{
            .when = m.windowsX8664(),
            .platform = "win-x64",
            .source = m.versionIndex(
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
));
