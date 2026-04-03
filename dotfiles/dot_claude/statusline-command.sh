#!/usr/bin/env bash

input=$(cat)

# ── ANSI colors (readonly, no subshell cost) ──
readonly DIM="\033[90m" RST="\033[0m"
readonly C_CYAN="\033[36m" C_YELLOW="\033[33m" C_RED="\033[31m"
readonly C_GREEN="\033[32m" C_MAGENTA="\033[35m" C_BLUE="\033[34m"
readonly SEP=" ${DIM}│${RST} "
readonly GIT_TIMEOUT=(timeout 5s)

# ── parse all JSON fields in a single jq call ──
# humanize + basename done in jq; newline-separated (safe for empty fields)
jq_out=$(jq -r '
  def humanize:
    if . == "" or . == null or . == 0 then ""
    elif . >= 1000000 then
      ((. + 50000) / 100000 | floor) as $tenths |
      "\($tenths / 10 | floor).\($tenths % 10)M"
    elif . >= 1000 then "\(. / 1000 | floor)k"
    else tostring end;
  [
    (.workspace.current_dir // .cwd // "" | split("/") | last // "."),
    (.model.display_name // ""),
    (.context_window.used_percentage // "" | tostring),
    ((.context_window.current_usage // {} |
      ((.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))) | humanize),
    (.context_window.context_window_size // 0 | humanize),
    (.rate_limits.five_hour.used_percentage // "" | tostring),
    (.rate_limits.seven_day.used_percentage // "" | tostring),
    (.workspace.current_dir // .cwd // "")
  ] | .[]
' <<<"$input" 2>/dev/null) || exit 0
[[ -z "$jq_out" ]] && exit 0
mapfile -t _f <<<"$jq_out"
dir_name=${_f[0]} model=${_f[1]} used=${_f[2]} cur_tokens=${_f[3]}
max_tokens=${_f[4]} rate_5h=${_f[5]} rate_7d=${_f[6]} json_dir=${_f[7]}

# Shorten model name: "Opus 4.6 (1M context)" -> "Opus"
# Remove version number and parenthetical (context size shown in token display)
model=$(sed -E 's/ [0-9]+\.[0-9]+//; s/ \([^)]*\)//' <<<"$model")

# ── pure-bash helpers (no subshells, write to shared vars) ──

# Sets REPLY to the ANSI color code for a percentage value
color_for_pct() {
	local pct=$1 low=${2:-50} high=${3:-75}
	if ! [[ "$pct" =~ ^[0-9]+$ ]]; then
		REPLY="$DIM"
	elif ((pct < low)); then
		REPLY="$C_CYAN"
	elif ((pct < high)); then
		REPLY="$C_YELLOW"
	else
		REPLY="$C_RED"
	fi
}

# Appends "${SEP}${1}" to $parts if $1 is non-empty
append() { [[ -n "$1" ]] && parts+="${SEP}$1"; }

# ── workspace dir for VCS commands (no cd, use git -C / jj -R instead) ──
readonly vcs_dir="${json_dir:-.}"

# skip lock acquisition for read-only git commands (avoids contention)
export GIT_OPTIONAL_LOCKS=0

# ── VCS: jujutsu ──
collect_jj() {
	local data bookmark short full conflict is_empty rest
	# jj show: implicitly targets @, --no-patch skips diff output,
	# --ignore-working-copy skips snapshotting (jj docs recommend for prompts),
	# pipe delimiter avoids bash read dropping leading empty tab fields
	data=$(timeout 2s jj show --no-patch -R "$vcs_dir" --quiet --ignore-working-copy --no-pager --color=never \
		-T 'bookmarks.join(",") ++ "|" ++ change_id.shortest() ++ "|" ++ change_id.short(8) ++ "|" ++ if(conflict, "true", "false") ++ "|" ++ if(empty, "true", "false")' \
		2>/dev/null) || return

	IFS='|' read -r bookmark short full conflict is_empty <<<"$data"

	if [[ -n "$bookmark" ]]; then
		vcs_info="${C_MAGENTA}${bookmark}${RST}"
	elif [[ -n "$short" && -n "$full" ]]; then
		rest="${full#"$short"}"
		vcs_info="${C_MAGENTA}${short}${DIM}${rest}${RST}"
	fi

	# dirty indicator (empty=true means clean)
	if [[ "$is_empty" == "true" ]]; then
		vcs_info+=" ${C_GREEN}●${RST}"
	else
		vcs_info+=" ${C_YELLOW}●${RST}"
	fi

	# conflict indicator
	[[ "$conflict" == "true" ]] && vcs_info+=" ${C_RED}✘ conflict${RST}"
}

# ── VCS: git ──
collect_git() {
	# Single git call: branch, oid, ahead/behind, stash, and file status
	# -unormal: skip enumerating individual files inside untracked dirs
	local git_dir git_hash="" git_branch="" ahead=0 behind=0 stash_count=0
	local staged=0 unstaged=0 untracked=false
	local line

	# --absolute-git-dir avoids relative path edge cases
	git_dir=$(git -C "$vcs_dir" rev-parse --absolute-git-dir 2>/dev/null) || true

	while IFS= read -r line; do
		case "$line" in
		'# branch.oid '*)
			git_hash="${line#\# branch.oid }"
			[[ "$git_hash" == "(initial)" ]] && git_hash=""
			git_hash="${git_hash:0:7}" # truncate to short hash
			;;
		'# branch.head '*)
			git_branch="${line#\# branch.head }"
			[[ "$git_branch" == "(detached)" ]] && git_branch=""
			;;
		'# branch.ab '*)
			# format: # branch.ab +N -M
			local ab="${line#\# branch.ab }"
			ahead="${ab%% *}"
			ahead="${ahead#+}"
			behind="${ab##* }"
			behind="${behind#-}"
			;;
		'# stash '*)
			stash_count="${line#\# stash }"
			;;
		'? '*)
			untracked=true
			;;
		'1 '* | '2 '* | 'u '*)
			# v2 uses "." for unchanged (not space like v1)
			local xy="${line:2:2}"
			[[ "${xy:0:1}" != '.' ]] && staged=1
			[[ "${xy:1:1}" != '.' ]] && unstaged=1
			;;
		esac
	done < <("${GIT_TIMEOUT[@]}" git -C "$vcs_dir" status --porcelain=v2 -b --show-stash --no-renames -unormal 2>/dev/null)

	# branch / detached head display
	if [[ -n "$git_branch" && -n "$git_hash" ]]; then
		vcs_info="${C_MAGENTA}${git_branch}${RST} ${DIM}${git_hash}${RST}"
	elif [[ -n "$git_branch" ]]; then
		vcs_info="${C_MAGENTA}${git_branch}${RST} ${DIM}(no commits)${RST}"
	elif [[ -n "$git_hash" ]]; then
		vcs_info="${C_YELLOW}(detached)${RST} ${DIM}${git_hash}${RST}"
	fi

	# ahead/behind upstream
	local arrows=""
	((ahead > 0)) && arrows="↑${ahead}"
	((behind > 0)) && arrows+="↓${behind}"
	[[ -n "$arrows" ]] && vcs_info+=" ${C_CYAN}${arrows}${RST}"

	# merge / rebase / cherry-pick / revert / bisect
	if [[ -n "$git_dir" ]]; then
		if [[ -f "${git_dir}/MERGE_HEAD" ]]; then
			vcs_info+=" ${C_RED}✘ merge${RST}"
		elif [[ -d "${git_dir}/rebase-merge" ]] ||
			[[ -d "${git_dir}/rebase-apply" ]]; then
			vcs_info+=" ${C_RED}↻ rebase${RST}"
		elif [[ -f "${git_dir}/CHERRY_PICK_HEAD" ]]; then
			vcs_info+=" ${C_RED}⊕ cherry-pick${RST}"
		elif [[ -f "${git_dir}/REVERT_HEAD" ]]; then
			vcs_info+=" ${C_RED}↩ revert${RST}"
		elif [[ -f "${git_dir}/BISECT_LOG" ]]; then
			vcs_info+=" ${C_RED}⟐ bisect${RST}"
		fi
	fi

	# status indicators
	((staged == 1)) && vcs_info+=" ${C_GREEN}+${RST}"
	if ((unstaged == 1)); then
		vcs_info+=" ${C_YELLOW}●${RST}"
	elif ((staged == 0)) && [[ "$untracked" == false ]]; then
		vcs_info+=" ${C_GREEN}●${RST}"
	fi
	[[ "$untracked" == true ]] && vcs_info+=" ${DIM}?${RST}"

	# stash count
	((stash_count > 0)) && vcs_info+=" ${DIM}⊟${stash_count}${RST}"
}

# ── detect jj repo by walking parent dirs (no fork, works from subdirs) ──
_has_jj() {
	local d="$1"
	[[ "$d" != /* ]] && { d="$(cd "$d" 2>/dev/null && pwd)" || return 1; }
	while [[ -n "$d" && "$d" != "/" ]]; do
		[[ -d "$d/.jj" ]] && return 0
		d="${d%/*}"
	done
	[[ -d "/.jj" ]]
}

# ── collect VCS info ──
vcs_info=""
if _has_jj "$vcs_dir"; then
	collect_jj
elif "${GIT_TIMEOUT[@]}" git -C "$vcs_dir" rev-parse --is-inside-work-tree &>/dev/null; then
	collect_git
fi

# ── context window ──
ctx_display=""
if [[ -n "$used" ]]; then
	printf -v pct '%.0f' "$used" 2>/dev/null || pct=0
	color_for_pct "$pct" 50 75
	color="$REPLY"

	token_label=""
	if [[ -n "$cur_tokens" && "$cur_tokens" != "0" && -n "$max_tokens" ]]; then
		token_label="${cur_tokens}/${max_tokens}"
	fi

	# Show token fraction if available, otherwise fall back to percentage
	if [[ -n "$token_label" ]]; then
		ctx_display="${color}${token_label}${RST}"
	else
		ctx_display="${color}${pct}%${RST}"
	fi
fi

# ── rate limits ──
rate_info=""
rate_parts=()
labels=(5h 7d)
rates=("$rate_5h" "$rate_7d")
for i in 0 1; do
	r="${rates[$i]}"
	[[ -z "$r" ]] && continue
	printf -v local_pct '%.0f' "$r" 2>/dev/null || continue
	color_for_pct "$local_pct" 50 100
	rate_parts+=("${DIM}${labels[$i]}${RST} ${REPLY}${local_pct}%${RST}")
done
((${#rate_parts[@]} > 0)) && rate_info="⏱ ${rate_parts[*]}"

# ── assemble ──
parts="$dir_name"
append "$vcs_info"
[[ -n "$model" ]] && append "${C_BLUE}${model}${RST}"
append "$ctx_display"
append "$rate_info"

printf '%b' "$parts"
