#!/usr/bin/env nu
# Hide GitHub comments (issue, PR conversation, or PR review) by minimizing
# them with a classifier reason. Wraps the `gh` CLI's GraphQL `minimizeComment`
# mutation, which is exposed via the API even when the web UI hides the option.

use std log

const VALID_REASONS = [OUTDATED DUPLICATE OFF_TOPIC RESOLVED SPAM ABUSE]

# Absolute path to the sibling .gql file, resolved at parse time so it works
# both from the dev checkout and from the wrapped nix store path.
const GQL_PATH = path self "hide-comment.gql"

def "nu-complete reasons" []: nothing -> list<string> { $VALID_REASONS }

# Parse a GitHub comment URL into structured fields. Uses `url parse` for the
# scheme/host/path/fragment split, then a tiny regex on the fragment to pull
# out the comment kind and id. Supports:
#   https://github.com/OWNER/REPO/pull/123#issuecomment-456
#   https://github.com/OWNER/REPO/issues/123#issuecomment-456
#   https://github.com/OWNER/REPO/pull/123#discussion_r456    (PR review)
export def parse-comment-url []: string -> record<owner: string, repo: string, kind: string, id: int> {
    let url = $in
    let parsed = ($url | url parse)

    if $parsed.host != "github.com" {
        error make --unspanned { msg: $"(ansi red_bold)Not a github.com URL:(ansi reset) ($url)" }
    }

    let segments = ($parsed.path | split row '/' | where { |s| $s != "" })
    if ($segments | length) < 4 {
        error make --unspanned { msg: $"(ansi red_bold)Unexpected URL path:(ansi reset) ($url)" }
    }
    let owner = ($segments | get 0)
    let repo = ($segments | get 1)
    let issue_kind = ($segments | get 2)
    if $issue_kind not-in ["pull" "issues"] {
        error make --unspanned { msg: $"(ansi red_bold)URL is not a pull/issues link:(ansi reset) ($url)" }
    }

    let fragment = ($parsed.fragment | default "")
    let m = ($fragment | parse --regex '^(?P<kind>issuecomment|discussion_r)-?(?P<id>\d+)$')
    if ($m | is-empty) {
        error make --unspanned { msg: $"(ansi red_bold)URL fragment is not a comment anchor:(ansi reset) ($url)" }
    }
    let row = ($m | first)
    {
        owner: $owner
        repo: $repo
        kind: $row.kind
        id: ($row.id | into int)
    }
}

# Look up the GraphQL node id for a comment via the REST API.
export def fetch-node-id []: record<owner: string, repo: string, kind: string, id: int> -> string {
    let p = $in
    let endpoint = if $p.kind == "issuecomment" {
        $"repos/($p.owner)/($p.repo)/issues/comments/($p.id)"
    } else {
        $"repos/($p.owner)/($p.repo)/pulls/comments/($p.id)"
    }
    ^gh api $endpoint --jq '.node_id' | str trim
}

# Append a notice ({type, msg}) to a record's `notices` column. Used to thread
# success/failure through the pipeline as data instead of via try/catch + bools.
def add-notice [type: string, msg: string]: record -> record {
    let r = $in
    let existing = ($r | get -o notices | default [])
    $r | upsert notices ($existing | append { type: $type, msg: $msg })
}

# Minimize a single comment URL with the given classifier. Always returns a
# record carrying any notices, never throws — callers tally results from data.
# Sends the mutation as `gh api graphql -F query=@<file> -F id=... -F reason=...`,
# which makes `gh` build the GraphQL `variables` object for us.
export def minimize-comment [classifier: string]: string -> record {
    let url = $in
    log info $"Processing ($url)"

    let result = try {
        let parsed = ($url | parse-comment-url)
        let node_id = ($parsed | fetch-node-id)
        if ($node_id | is-empty) {
            return ({ url: $url } | add-notice error "missing node id")
        }

        ^gh api graphql -F $"query=@($GQL_PATH)" -F $"id=($node_id)" -F $"reason=($classifier)" | from json
    } catch { |e|
        return ({ url: $url } | add-notice error $e.msg)
    }

    let minimized = ($result | get -o data.minimizeComment.minimizedComment.isMinimized | default false)
    if $minimized {
        let reason = ($result | get data.minimizeComment.minimizedComment.minimizedReason)
        { url: $url, reason: $reason } | add-notice info $"hidden as ($reason)"
    } else {
        { url: $url } | add-notice error $"unexpected response: ($result | to json -r)"
    }
}

# Print collected notices via std log, routing to the right stream by type.
def format-notices []: list -> nothing {
    let results = $in
    for r in $results {
        for n in ($r | get -o notices | default []) {
            match $n.type {
                "info" => { log info $"($r.url): ($n.msg)" }
                "warning" => { log warning $"($r.url): ($n.msg)" }
                "error" => { log error $"($r.url): ($n.msg)" }
                _ => { log info $"($r.url): ($n.msg)" }
            }
        }
    }
}

# Read URLs interactively from stdin, blank line ends input.
def read-urls-interactive []: nothing -> list<string> {
    log info "Interactive mode. Paste comment URLs, blank line to quit."
    mut acc = []
    loop {
        let line = (input $"(ansi cyan)url> (ansi reset)" | str trim)
        if ($line | is-empty) { break }
        $acc = ($acc | append $line)
    }
    $acc
}

# Hide one or more GitHub comments. Pass URLs as arguments, or run with no
# args to enter interactive mode (paste a URL per line, blank line to exit).
@example "Hide a single PR comment as outdated" "gh-hide-comment https://github.com/owner/repo/pull/1#issuecomment-123"
@example "Hide several with a different reason" "gh-hide-comment --reason DUPLICATE $url1 $url2"
@example "Interactive mode" "gh-hide-comment"
export def main [
    --reason: string@"nu-complete reasons" = "OUTDATED"   # Classifier for why the comment is being hidden
    ...urls: string                                       # Comment URLs (omit for interactive mode)
] {
    let classifier = ($reason | str upcase)
    if $classifier not-in $VALID_REASONS {
        error make --unspanned {
            msg: $"(ansi red_bold)Invalid --reason '($reason)'.(ansi reset) Must be one of: ($VALID_REASONS | str join ', ')"
        }
    }

    let inputs = if ($urls | is-not-empty) { $urls } else { read-urls-interactive }

    let results = ($inputs | each { |u| $u | minimize-comment $classifier })
    $results | format-notices

    let failed = ($results | where { |r| "error" in (($r.notices? | default []) | get type) } | length)
    let total = ($results | length)
    log info $"Done. (($total - $failed))/($total) hidden."

    if $failed > 0 {
        error make --unspanned { msg: $"($failed) of ($total) failed" }
    }
}
