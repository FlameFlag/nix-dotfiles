#!/usr/bin/env nu

# Logging helpers
def log_error [msg: string] { print -e $"(ansi red_bold)[error](ansi reset) ($msg)" }
def log_info [msg: string] { print $"(ansi blue_bold)[info](ansi reset) ($msg)" }
def log_success [msg: string] { print $"(ansi green_bold)[success](ansi reset) ($msg)" }
def log_warning [msg: string] { print $"(ansi yellow_bold)[warning](ansi reset) ($msg)" }

# Compress a downloaded video using ffmpeg
def compress_video [temp_dir: string, crf: int] {
    let input_file = (glob $"($temp_dir)/*" | first)
    if ($input_file | is-empty) {
        log_error "Downloaded file not found for compression."
        error make { msg: "Downloaded file not found for compression." }
    }

    let base_name = ($input_file | path parse | get stem)
    let output_file = $"./($base_name).mp4"

    log_info $"Compressing video with CRF ($crf)..."
    log_info $"  Input:  ($input_file)"
    log_info $"  Output: ($output_file)"

    ^ffmpeg -nostdin -i $input_file -c:v libx264 -preset slow -crf $crf -c:a copy -y $output_file

    log_success "Compression finished successfully."
}

# Set the file modification date to the video's upload date
def change_file_date [metadata: record] {
    let upload_date = ($metadata.upload_date? | default "")
    let display_id = ($metadata.display_id? | default "")

    if ($upload_date | is-empty) {
        log_warning "Upload date not found. Skipping file date modification."
        return
    }

    let matches = (glob $"($display_id)*")
    if ($matches | is-empty) {
        log_warning "Could not find an output file to modify the date for."
        return
    }

    let file_to_touch = ($matches | first)
    log_info $"Setting file modification time of '($file_to_touch)' to ($upload_date)..."
    # touch -t format: YYYYMMDDhhmm (works on both GNU and BSD)
    ^touch -t $"($upload_date)0000" $file_to_touch
}

# Download media with yt-dlp, with optional time-range cutting and compression
def main [
    format: string          # Download format: mp4, mp3, m4a, mp4-cut, mp3-cut, m4a-cut
    url: string             # Video URL
    time_range?: string     # Time range for -cut formats (e.g. 30-60)
    --compress              # Compress the video after downloading
    --crf: int = 26         # CRF value for compression
    ...passthrough: string  # Additional args passed to yt-dlp (after --)
] {
    # Validate format
    let valid_formats = ["mp4" "mp3" "m4a" "mp4-cut" "mp3-cut" "m4a-cut"]
    if $format not-in $valid_formats {
        log_error $"Invalid format '($format)'. Must be one of: ($valid_formats | str join ', ')"
        exit 1
    }

    let is_cut = ($format | str ends-with "-cut")

    if $is_cut and ($time_range == null) {
        log_error "Missing time range for a '-cut' format."
        exit 1
    }

    # Fetch metadata
    log_info "Fetching video metadata..."
    let metadata = (^yt-dlp --ignore-config --no-playlist --dump-json $url ...$passthrough | from json)

    # Validate time range
    if $time_range != null {
        let parts = ($time_range | split row "-")
        let start = ($parts | get 0 | into float)
        let end = ($parts | get 1 | into float)
        let duration = ($metadata.duration? | default null)

        if $duration != null {
            if $start < 0 or $start > $end or $end > ($duration | into float) {
                log_error $"Invalid time range '($time_range)'. Must be within video duration of ($duration)s."
                exit 1
            }
        } else {
            log_warning "Could not determine video duration. Skipping time range validation."
        }
    }

    # Build yt-dlp command args
    mut args: list<string> = ["--ignore-config"]

    let base_format = ($format | str replace "-cut" "")
    match $base_format {
        "m4a" => { $args = ($args | append ["--extract-audio" "--audio-format" "m4a" "--audio-quality" "0" "--embed-thumbnail"]) }
        "mp3" => { $args = ($args | append ["--extract-audio" "--audio-format" "mp3" "--audio-quality" "0" "--embed-thumbnail"]) }
        "mp4" => { $args = ($args | append ["--format" "bestvideo[ext=mp4][height<=1080]+bestaudio[ext=m4a]/best[ext=mp4]/best"]) }
        _ => { log_warning $"Unknown format '($format)'. Using yt-dlp defaults." }
    }

    $args = ($args | append ["--embed-metadata" "--console-title"])

    mut time_suffix = ""
    if $time_range != null {
        $args = ($args | append ["--download-sections" $"*($time_range)" "--force-keyframes-at-cuts"])
        $time_suffix = $"-($time_range | str replace --all ':' '_')"
    }

    if $compress {
        let temp_dir = (mktemp -d | str trim)

        let output_tmpl = $temp_dir + '/%(display_id)s.%(ext)s'
        $args = ($args | append ["--output" $output_tmpl])
        $args = ($args | append [$url ...$passthrough])

        log_info $"Executing: yt-dlp ($args | str join ' ')"
        print ""

        try {
            ^yt-dlp ...$args
            log_success "Download completed."
            compress_video $temp_dir $crf
        } catch { |e|
            log_error $"yt-dlp download failed: ($e.msg)"
            rm -rf $temp_dir
            error make { msg: $e.msg }
        }

        rm -rf $temp_dir
    } else {
        let output_tmpl = '%(display_id)s' + $time_suffix + '.%(ext)s'
        $args = ($args | append ["--output" $output_tmpl])
        $args = ($args | append [$url ...$passthrough])

        log_info $"Executing: yt-dlp ($args | str join ' ')"
        print ""

        try {
            ^yt-dlp ...$args
        } catch { |e|
            log_error "yt-dlp download failed."
            exit 1
        }
        log_success "Download completed."
    }

    change_file_date $metadata

    log_success "All operations completed successfully!"
}
