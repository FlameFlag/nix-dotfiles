#!/usr/bin/env bash
#
# Author: FlameFlag
#
#/ Usage: SCRIPTNAME [OPTIONS]... URL [TIME_RANGE] [FORMAT] [-- ADDITIONAL_ARGS]
#/
#/ OPTIONS
#/   --compress
#/                Download and then compress the video using ffmpeg.
#/   --crf VALUE
#/                Specify the CRF value for compression (default: 26).
#/   -h, --help
#/                Print this help message.
#/
#/ EXAMPLES
#/   # Download a video as mp4
#/   SCRIPTNAME mp4 "https://youtu.be/1BTd20qIfBI"
#/
#/   # Cut a specific time range from a video
#/   SCRIPTNAME mp4-cut "https://youtu.be/1BTd20qIfBI" 30-60
#/
#/   # Download, compress with a custom CRF, and pass --write-subs to yt-dlp
#/   SCRIPTNAME mp4 --compress --crf 22 "https://youtu.be/1BTd20qIfBI" -- --write-subs

#{{{ Variables

# Split on newlines and tabs, not spaces.
IFS=$'\t\n'

script_name=$(basename "${0}")
readonly script_name


URL=""
TIME_RANGE=""
FORMAT="mp4"
COMPRESS_OPTION=false
CRF=26
JSON_METADATA=""
TEMP_DIR=""
declare -a YTDLP_PASSTHROUGH_ARGS=()
#}}}

main() {
	check_dependencies
	parse_arguments "${@}"
	validate_arguments

	declare -a download_command=()
	build_yt_dlp_command download_command

	log_info "Executing: ${download_command[*]}"
	printf "\n"

	if ! "${download_command[@]}"; then
		log_error "yt-dlp download failed."
		exit 1
	fi
	log_success "Download completed."

	if [[ "${COMPRESS_OPTION}" == true ]]; then
		compress_video
	fi

	change_file_date

	log_success "All operations completed successfully!"
}

#{{{ Helper functions
log_error() {
	printf "\033[0;31m[error] %s\033[0m\n" "${*}" >&2
}
log_info() {
	printf "\033[0;34m[info] %s\033[0m\n" "${*}"
}
log_success() {
	printf "\033[0;32m[success] %s\033[0m\n" "${*}"
}
log_warning() {
	printf "\033[0;33m[warning] %s\033[0m\n" "${*}"
}

show_help() {
	grep '^#/' <"${BASH_SOURCE[0]}" | cut -c4- | sed "s/SCRIPTNAME/${script_name}/g"
}

cleanup() {
	if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
		rm -rf -- "${TEMP_DIR}"
		log_info "Cleaned up temporary directory."
	fi
}

check_dependencies() {
	for dep in "${DEPENDENCIES[@]}"; do
		if ! command -v "${dep}" &>/dev/null; then
			log_error "Required command not found: '${dep}'."
			log_error "Please install it to continue."
			exit 1
		fi
	done
}

parse_arguments() {
	while [[ $# -gt 0 ]]; do
		case "${1}" in
		-h | --help)
			show_help
			exit 0
			;;
		--compress)
			COMPRESS_OPTION=true
			shift
			;;
		--crf)
			# Use ${2-} to avoid unbound variable error in strict mode
			if [[ -z "${2-}" ]]; then
				log_error "--crf requires a numeric value."
				exit 1
			fi
			CRF="${2}"
			shift 2
			;;
		--)
			shift
			YTDLP_PASSTHROUGH_ARGS=("$@")
			break
			;;
		-*)
			log_error "Unknown option: ${1}"
			show_help
			exit 1
			;;
		*)
			# Handle positional arguments by their content, not order.
			local arg="${1}"
			if [[ "${arg}" =~ ^(m4a|mp3|mp4|m4a-cut|mp3-cut|mp4-cut)$ ]]; then
				FORMAT="${arg}"
			elif [[ "${arg}" =~ ^[0-9:.-]+-[0-9:.-]+$ ]]; then
				TIME_RANGE="${arg}"
			elif [[ -z "${URL}" ]]; then
				URL="${arg}"
			else
				log_error "Unrecognized argument: '${arg}'. A URL has already been provided."
				exit 1
			fi
			shift
			;;
		esac
	done
}

validate_arguments() {
	if [[ -z "${URL}" ]]; then
		log_error "Missing URL."
		show_help
		exit 1
	fi

	if [[ "${FORMAT}" == *-cut && -z "${TIME_RANGE}" ]]; then
		log_error "Missing time range for a '-cut' format."
		exit 1
	fi

	log_info "Fetching video metadata..."
	JSON_METADATA=$(yt-dlp --ignore-config --dump-json "${URL}")
	if [[ -z "${JSON_METADATA}" ]]; then
		log_error "Failed to fetch video metadata. The URL may be invalid or private."
		exit 1
	fi

	if [[ -n "${TIME_RANGE}" ]]; then
		local start
		local end
		local duration
		start=$(cut -d- -f1 <<<"${TIME_RANGE}")
		end=$(cut -d- -f2 <<<"${TIME_RANGE}")
		duration=$(jq -r '.duration' <<<"${JSON_METADATA}")

		if [[ "${duration}" == "null" ]]; then
			log_warning "Could not determine video duration. Skipping time range validation."
		elif (( $(awk -v s="${start}" -v e="${end}" -v d="${duration}" 'BEGIN{print(s<0||s>e||e>d)}') )); then
			log_error "Invalid time range '${TIME_RANGE}'. Must be within video duration of ${duration}s."
			exit 1
		fi
	fi
}

build_yt_dlp_command() {
	# Use a nameref to pass the array back to the caller's scope.
	declare -n cmd_ref=$1
	cmd_ref=("yt-dlp" "--ignore-config")
	local time_suffix=""

	case "${FORMAT}" in
	m4a | m4a-cut)
		cmd_ref+=(--extract-audio --audio-format m4a --audio-quality 0 --embed-thumbnail)
		;;
	mp3 | mp3-cut)
		cmd_ref+=(--extract-audio --audio-format mp3 --audio-quality 0 --embed-thumbnail)
		;;
	mp4 | mp4-cut)
		cmd_ref+=(--format "bestvideo[ext=mp4][height<=1080]+bestaudio[ext=m4a]/best[ext=mp4]/best")
		;;
	*)
		log_warning "Unknown format '${FORMAT}'. Using yt-dlp defaults."
		;;
	esac

	cmd_ref+=(--embed-metadata --console-title)

	if [[ -n "${TIME_RANGE}" ]]; then
		cmd_ref+=(--download-sections "*${TIME_RANGE}" --force-keyframes-at-cuts)
		time_suffix="-${TIME_RANGE//:/_}"
	fi

	if [[ "${COMPRESS_OPTION}" == true ]]; then
		TEMP_DIR=$(mktemp -d)
		trap cleanup EXIT
		cmd_ref+=(--output "${TEMP_DIR}/%(display_id)s.%(ext)s")
	else
		cmd_ref+=(--output "%(display_id)s${time_suffix}.%(ext)s")
	fi

	cmd_ref+=("${URL}" "${YTDLP_PASSTHROUGH_ARGS[@]}")
}

change_file_date() {
	local upload_date
	local display_id
	upload_date=$(jq -r '.upload_date' <<<"${JSON_METADATA}")
	display_id=$(jq -r '.display_id' <<<"${JSON_METADATA}")

	if [[ "${upload_date}" == "null" ]]; then
		log_warning "Upload date not found. Skipping file date modification."
		return
	fi

	local file_to_touch
	file_to_touch=$(find . -maxdepth 1 -name "${display_id}*" -print -quit)

	if [[ -n "${file_to_touch}" ]]; then
		log_info "Setting file modification time of '${file_to_touch}' to ${upload_date}..."
		touch --date "${upload_date}" "${file_to_touch}"
	else
		log_warning "Could not find an output file to modify the date for."
	fi
}

compress_video() {
	local input_file
	input_file=$(find "${TEMP_DIR}" -type f -print -quit)
	if [[ ! -f "${input_file}" ]]; then
		log_error "Downloaded file not found for compression."
		return 1
	fi

	local base_name
	local output_file
	base_name=$(basename "${input_file}")
	base_name="${base_name%.*}"
	output_file="./${base_name}.mp4"

	log_info "Compressing video with CRF ${CRF}..."
	log_info "  Input:  ${input_file}"
	log_info "  Output: ${output_file}"

	# Use -nostdin to prevent ffmpeg from consuming stdin, which is good practice for scripts.
	ffmpeg -nostdin -i "${input_file}" \
		-c:v libx264 -preset slow -crf "${CRF}" \
		-c:a copy \
		-y "${output_file}"

	log_success "Compression finished successfully."
}

#}}}

main "${@}"
