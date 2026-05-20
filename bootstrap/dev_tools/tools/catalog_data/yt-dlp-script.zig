const bootstrap = @import("bootstrap");

const m = bootstrap.manifest;

pub const tool: m.Tool = .{
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
};
