//! Change-id prefix computation that matches `jj log` exactly.
//!
//! `jj log` colors only the *shortest unique prefix* of each change-id,
//! disambiguated against the user's `revsets.short-prefixes` revset
//! (default: `revsets.log` = `present(@) | ancestors(immutable_heads().., 2) |
//! trunk()`). `jj_lib::Repo::shortest_unique_change_id_prefix_len`
//! disambiguates against *all* visible heads, which is a much larger set, so
//! calling it directly produces prefixes that are 2-3 chars longer than what
//! `jj log` shows.
//!
//! The right answer is to do exactly what `jj-cli` does: load the
//! user's jj config (plus jj-cli's bundled defaults), parse the
//! `revsets.short-prefixes` expression, build an `IdPrefixContext`
//! disambiguated within that revset, and ask it for the prefix length.
//! This module does that - and adds a persistent disk cache so the
//! prompt path doesn't pay the cost on every render.
//!
//! ## Performance model
//!
//! Per the technical trace of jj-cli's flow, the bulk of the work is
//! the *revset evaluation* (parse + symbol resolution + traversal +
//! `commit_change_ids()` collection), which can run from sub-millisecond
//! on a tiny repo up to hundreds of milliseconds on a 50k-commit
//! history. The actual prefix lookup is microseconds.
//!
//! The op-log head changes only when the user runs a `jj` command that
//! mutates state (commit, abandon, rebase, snapshot, …). Between such
//! events the disambiguation set is **identical** across every prompt
//! render, so we can cache the resolved set on disk keyed by op-log
//! head id. The fast path then becomes:
//!
//!  1. Read a small JSON file (~µs).
//!  2. Compute the prefix locally over the cached change-id set (a couple of
//!     `take_while` chars per cached id, microseconds).
//!
//! and the slow path (cache miss) only fires when the op-log head
//! actually changed - i.e. when something interesting happened in the
//! repo, which is also when paying ~10-100ms is fine.

use std::collections::HashMap;
use std::collections::hash_map::DefaultHasher;
use std::fs;
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use jj_lib::backend::ChangeId;
use jj_lib::config::{ConfigLayer, ConfigSource, StackedConfig};
use jj_lib::id_prefix::IdPrefixContext;
use jj_lib::object_id::ObjectId;
use jj_lib::repo::{ReadonlyRepo, Repo};
use jj_lib::repo_path::RepoPathUiConverter;
use jj_lib::revset::{
    self, RevsetAliasesMap, RevsetDiagnostics, RevsetExtensions, RevsetParseContext,
    RevsetWorkspaceContext, SymbolResolver,
};
use jj_lib::settings::UserSettings;
use jj_lib::workspace::Workspace;
use serde::{Deserialize, Serialize};

/// Bundled jj-cli `revsets.toml` defaults. jj-lib's
/// `StackedConfig::with_defaults` only loads jj-lib's own defaults; the alias
/// map (`trunk()`, `immutable_heads()`, `mutable()`,
/// `builtin_immutable_heads()`) and the default `revsets.log` value live in
/// jj-cli's bundled `cli/src/config/revsets.toml`. Without these the
/// `revsets.short-prefixes` fallback chain can't even parse, let alone
/// evaluate.
///
/// Mirrored verbatim from upstream jj at
/// `cli/src/config/revsets.toml`. If jj's defaults shift in a future
/// release, the worst case is that our prefixes drift back to the
/// "all visible heads" baseline - same as before this module existed —
/// not a hard failure.
const JJ_CLI_DEFAULT_REVSETS_TOML: &str = r#"
[revsets]
arrange = "reachable(@, mutable())"
fix = "reachable(@, mutable())"
simplify-parents = "reachable(@, mutable())"
log = "present(@) | ancestors(immutable_heads().., 2) | trunk()"
log-graph-prioritize = "present(@)"
op-diff-changes-in = "mutable() | immutable_heads()"
sign = "reachable(@, mutable())"
bookmark-advance-to = "@"
bookmark-advance-from = "heads(::to & bookmarks())"

[revset-aliases]
'trunk()' = '''
latest(
  remote_bookmarks(exact:"main", exact:"origin") |
  remote_bookmarks(exact:"master", exact:"origin") |
  remote_bookmarks(exact:"trunk", exact:"origin") |
  remote_bookmarks(exact:"main", exact:"upstream") |
  remote_bookmarks(exact:"master", exact:"upstream") |
  remote_bookmarks(exact:"trunk", exact:"upstream") |
  root()
)
'''
'builtin_immutable_heads()' = 'trunk() | tags() | untracked_remote_bookmarks()'
'immutable_heads()' = 'builtin_immutable_heads()'
'immutable()' = '::(immutable_heads() | root())'
'mutable()' = '~immutable()'
'visible()' = '::visible_heads()'
'hidden()' = '~visible()'
"#;

/// Top-level entry point.
///
/// Returns the shortest unique change-id prefix length (in hex
/// characters) for `change_id` against the same disambiguation set
/// `jj log` would use, given the current op-log head of `repo`.
/// Falls back to `1` on any failure so the caller can always render
/// at least one character.
pub fn shortest_prefix_len(
    workspace: &Workspace,
    repo: &Arc<ReadonlyRepo>,
    change_id: &ChangeId,
) -> usize {
    let op_id_hex = repo.op_id().hex();
    let target_hex = change_id.reverse_hex();

    // Fast path: look at the persistent cache first. The cache stores
    // the resolved disambiguation set keyed by op-log head; if it's
    // still valid we never touch jj-lib's revset parser.
    if let Some(cached) = read_cache(workspace.workspace_root(), &op_id_hex)
        && let Some(len) = cached.shortest_prefix_for(&target_hex)
    {
        return len;
    }

    // Slow path: actually evaluate the disambiguation revset via
    // jj-lib, then memoize. Any failure here drops back to the
    // "all visible heads" repo-wide computation so we never block.
    match resolve_via_jj_lib(workspace, repo, change_id) {
        Some((len, set)) => {
            let _ = write_cache(
                workspace.workspace_root(),
                &CachedSet {
                    op_id: op_id_hex,
                    change_ids: set,
                },
            );
            len.max(1)
        }
        None => repo
            .shortest_unique_change_id_prefix_len(change_id)
            .ok()
            .unwrap_or(1)
            .max(1),
    }
}

/// Use jj-lib end-to-end: load merged config, parse the
/// `revsets.short-prefixes` expression, evaluate it, populate an
/// `IdPrefixContext`, and ask for the prefix length. Returns both the
/// prefix length AND the resolved change-id set so the caller can
/// memoize it for next time.
fn resolve_via_jj_lib(
    workspace: &Workspace,
    repo: &Arc<ReadonlyRepo>,
    target: &ChangeId,
) -> Option<(usize, Vec<String>)> {
    let stacked = build_stacked_config(workspace.workspace_root());
    let settings = UserSettings::from_config(stacked.clone()).ok()?;

    let revset_string = settings
        .get_string("revsets.short-prefixes")
        .ok()
        .or_else(|| settings.get_string("revsets.log").ok())?;
    if revset_string.is_empty() {
        return None;
    }

    let aliases_map = load_revset_aliases(&stacked);
    let path_converter = RepoPathUiConverter::Fs {
        cwd: workspace.workspace_root().to_path_buf(),
        base: workspace.workspace_root().to_path_buf(),
    };
    let workspace_name = workspace.workspace_name();
    let workspace_ctx = RevsetWorkspaceContext {
        path_converter: &path_converter,
        workspace_name,
    };
    // The fileset alias map and date pattern context are mandatory
    // fields on `RevsetParseContext` but the short-prefixes revset
    // doesn't use either. Defaults are fine.
    let fileset_aliases = jj_lib::fileset::FilesetAliasesMap::new();
    let extensions = Arc::new(RevsetExtensions::default());
    let date_ctx = chrono::Utc::now().fixed_offset().into();

    let parse_ctx = RevsetParseContext {
        aliases_map: &aliases_map,
        local_variables: HashMap::new(),
        user_email: settings.user_email(),
        date_pattern_context: date_ctx,
        default_ignored_remote: None,
        fileset_aliases_map: &fileset_aliases,
        use_glob_by_default: false,
        extensions: extensions.as_ref(),
        workspace: Some(workspace_ctx),
    };

    let mut diagnostics = RevsetDiagnostics::new();
    let expr = revset::parse(&mut diagnostics, &revset_string, &parse_ctx).ok()?;

    let id_prefix_ctx = IdPrefixContext::new(extensions.clone()).disambiguate_within(expr.clone());
    let index = id_prefix_ctx.populate(repo.as_ref()).ok()?;
    let prefix_len = index
        .shortest_change_prefix_len(repo.as_ref(), target)
        .ok()?;

    // Re-collect the set so we can memoize it on disk. We could try
    // to reach into `IdPrefixContext`'s OnceCell but it's private;
    // re-evaluating the revset is the same cost as the first
    // populate and lets us own a clean `Vec<String>` for the cache.
    let symbol_resolver = SymbolResolver::new(repo.as_ref(), extensions.symbol_resolvers());
    let resolved = expr
        .resolve_user_expression(repo.as_ref(), &symbol_resolver)
        .ok()?;
    let revset = resolved.evaluate(repo.as_ref()).ok()?;
    let mut change_ids: Vec<String> = Vec::new();
    for (_, cid) in revset.commit_change_ids().flatten() {
        change_ids.push(cid.reverse_hex());
    }

    Some((prefix_len, change_ids))
}

/// Build a `StackedConfig` mirroring the layers `jj-cli` would assemble:
/// jj-lib defaults at the bottom, jj-cli's bundled `revsets.toml` on
/// top of that, then the user's `~/.jjconfig.toml` and
/// `$XDG_CONFIG_HOME/jj/config.toml`, then the repo-local
/// `.jj/repo/config.toml`. We deliberately omit env-var overrides and
/// command-arg layers - the statusline doesn't have a CLI to pass
/// those through.
fn build_stacked_config(workspace_root: &Path) -> StackedConfig {
    let mut config = StackedConfig::with_defaults();

    // jj-cli's bundled defaults (alias map + revsets.log default).
    if let Ok(layer) = ConfigLayer::parse(ConfigSource::Default, JJ_CLI_DEFAULT_REVSETS_TOML) {
        config.add_layer(layer);
    }

    // ~/.jjconfig.toml - the original jj user config location.
    if let Some(home) = dirs::home_dir() {
        let p = home.join(".jjconfig.toml");
        if p.exists() {
            let _ = config.load_file(ConfigSource::User, p);
        }
    }
    // $XDG_CONFIG_HOME/jj/config.toml - the modern user config location.
    if let Some(cfg) = dirs::config_dir() {
        let p = cfg.join("jj").join("config.toml");
        if p.exists() {
            let _ = config.load_file(ConfigSource::User, p);
        }
        // conf.d directory of fragments, if any.
        let confd = cfg.join("jj").join("conf.d");
        if confd.is_dir() {
            let _ = config.load_dir(ConfigSource::User, confd);
        }
    }
    // Repo-local config.
    let repo_cfg = workspace_root.join(".jj").join("repo").join("config.toml");
    if repo_cfg.exists() {
        let _ = config.load_file(ConfigSource::Repo, repo_cfg);
    }

    config
}

/// Walk every layer of `config` and merge the `revset-aliases` table
/// into a fresh `RevsetAliasesMap`. Mirrors `jj-cli`'s
/// `load_revset_aliases` (`cli/src/cli_util.rs`) but skipped the
/// warn-on-redefined-builtin step - the statusline never surfaces
/// warnings to the user.
fn load_revset_aliases(config: &StackedConfig) -> RevsetAliasesMap {
    let mut aliases_map = RevsetAliasesMap::new();
    for layer in config.layers() {
        let Ok(Some(table)) = layer.look_up_table("revset-aliases") else {
            continue;
        };
        for (decl, item) in table.iter() {
            let Some(defn) = item.as_str() else { continue };
            let _ = aliases_map.insert(decl, defn);
        }
    }
    aliases_map
}

/// On-disk memoization of the resolved disambiguation set. Keyed by
/// op-log head id so it stays valid across statusline invocations and
/// only invalidates when the user actually does something that would
/// change the set.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct CachedSet {
    /// Hex op-id of the op-log head this set was resolved against.
    op_id: String,
    /// Reverse-hex change-ids in the disambiguation set.
    change_ids: Vec<String>,
}

impl CachedSet {
    /// Compute the shortest unique prefix of `target_hex` against the
    /// cached set without re-evaluating the revset. Returns `None` if
    /// the cache doesn't actually contain `target_hex` (which would
    /// mean it's stale - the caller should re-resolve).
    fn shortest_prefix_for(&self, target_hex: &str) -> Option<usize> {
        let mut found_self = false;
        let mut max_common = 0usize;
        for other in &self.change_ids {
            if other == target_hex {
                found_self = true;
                continue;
            }
            let common = target_hex
                .chars()
                .zip(other.chars())
                .take_while(|(a, b)| a == b)
                .count();
            if common > max_common {
                max_common = common;
            }
        }
        if !found_self {
            // Target isn't in the cached set - most likely the user
            // moved @ to a commit that wasn't part of the previous
            // disambiguation snapshot. Treat as a miss and force a
            // re-resolve.
            return None;
        }
        Some((max_common + 1).max(1))
    }
}

/// Cache file for the given workspace. We hash the workspace root
/// path so different repos get distinct files; sticking the raw path
/// into the filename would be either unwieldy or non-portable.
fn cache_path(workspace_root: &Path) -> Option<PathBuf> {
    let dir = dirs::cache_dir()?
        .join("claude-statusline")
        .join("jj-prefix");
    let mut hasher = DefaultHasher::new();
    workspace_root.hash(&mut hasher);
    let h = hasher.finish();
    Some(dir.join(format!("{h:016x}.json")))
}

fn read_cache(workspace_root: &Path, op_id: &str) -> Option<CachedSet> {
    let path = cache_path(workspace_root)?;
    let bytes = fs::read(&path).ok()?;
    let cached: CachedSet = serde_json::from_slice(&bytes).ok()?;
    if cached.op_id != op_id {
        // Op-log head moved - the cached set may include stale or
        // missing commits. Discard.
        return None;
    }
    Some(cached)
}

fn write_cache(workspace_root: &Path, set: &CachedSet) -> std::io::Result<()> {
    let path = cache_path(workspace_root).ok_or_else(|| std::io::Error::other("no cache dir"))?;
    let parent = path
        .parent()
        .ok_or_else(|| std::io::Error::other("no parent dir"))?;
    fs::create_dir_all(parent)?;
    let bytes =
        serde_json::to_vec(set).map_err(|e| std::io::Error::other(format!("serialize: {e}")))?;
    let tmp = tempfile::NamedTempFile::new_in(parent)?;
    fs::write(tmp.path(), &bytes)?;
    tmp.persist(&path)
        .map_err(|e| std::io::Error::other(format!("persist: {e}")))?;
    Ok(())
}
