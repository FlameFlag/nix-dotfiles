use std::collections::HashMap;

use dotfiles_common::{http::Client, process, template};
use serde::Deserialize;

use crate::archive::ArchiveError;
use crate::catalog::{Link, Source};
use crate::release;

#[derive(Debug)]
pub(crate) struct ResolvedSource {
    pub(crate) version: String,
    pub(crate) url: String,
}

#[derive(Deserialize)]
struct IndexedRelease {
    version: String,
}

pub(crate) fn resolve_source(
    source: &Source,
    platform: &str,
) -> Result<ResolvedSource, ArchiveError> {
    match source {
        Source::GithubLatest {
            repo,
            tag_prefix,
            asset,
        } => resolve_github_latest(repo, tag_prefix, asset, platform),
        Source::GithubLatestMatching {
            repo,
            tag_prefix,
            asset_prefix,
            asset_suffix,
        } => resolve_github_latest_matching(repo, tag_prefix, asset_prefix, asset_suffix, platform),
        Source::Direct { version, url } => resolve_direct(version, url, platform),
        Source::Command { argv, url } => resolve_command(argv, url, platform),
        Source::VersionIndex { index_url, url } => resolve_version_index(index_url, url, platform),
    }
}

fn resolve_github_latest(
    repo: &str,
    tag_prefix: &str,
    asset: &str,
    platform: &str,
) -> Result<ResolvedSource, ArchiveError> {
    let release = release::GithubRelease::latest(repo)?;
    let version = release.version(tag_prefix);
    let bindings = source_bindings(&version, platform);
    let asset = template::render(asset, &bindings)?;
    Ok(ResolvedSource {
        version,
        url: release.asset_url(&asset)?,
    })
}

fn resolve_github_latest_matching(
    repo: &str,
    tag_prefix: &str,
    asset_prefix: &str,
    asset_suffix: &str,
    platform: &str,
) -> Result<ResolvedSource, ArchiveError> {
    let release = release::GithubRelease::latest(repo)?;
    let version = release.version(tag_prefix);
    let bindings = source_bindings(&version, platform);
    let prefix = template::render(asset_prefix, &bindings)?;
    let suffix = template::render(asset_suffix, &bindings)?;
    Ok(ResolvedSource {
        version,
        url: release.matching_asset_url(&prefix, &suffix)?,
    })
}

fn resolve_direct(
    version: &str,
    url: &str,
    platform: &str,
) -> Result<ResolvedSource, ArchiveError> {
    let bindings = source_bindings(version, platform);
    Ok(ResolvedSource {
        version: version.to_owned(),
        url: template::render(url, &bindings)?,
    })
}

fn resolve_command(
    argv: &[String],
    url: &str,
    platform: &str,
) -> Result<ResolvedSource, ArchiveError> {
    let version = process::trimmed_text(argv)?;
    let bindings = source_bindings(&version, platform);
    let url = template::render(url, &bindings)?;
    Ok(ResolvedSource { version, url })
}

fn resolve_version_index(
    index_url: &str,
    url: &str,
    platform: &str,
) -> Result<ResolvedSource, ArchiveError> {
    let client = Client::new("dotfiles-bootstrap")?;
    let releases: Vec<IndexedRelease> = client.json(index_url)?;
    let version = releases
        .into_iter()
        .next()
        .ok_or(ArchiveError::EmptyVersionIndex)?
        .version;
    let bindings = source_bindings(&version, platform);
    let url = template::render(url, &bindings)?;
    Ok(ResolvedSource { version, url })
}

fn source_bindings<'a>(version: &'a str, platform: &'a str) -> template::Bindings<'a> {
    let mut bindings = HashMap::new();
    bindings.insert("version", version);
    bindings.insert("platform", platform);
    bindings
}

pub(crate) fn render_links(
    links: &[Link],
    bindings: &template::Bindings<'_>,
) -> Result<Vec<Link>, ArchiveError> {
    links
        .iter()
        .map(|link| {
            Ok(Link {
                name: template::render(&link.name, bindings)?,
                path: template::render(&link.path, bindings)?,
                env: link
                    .env
                    .iter()
                    .map(|env| {
                        Ok(crate::catalog::EnvVar {
                            name: template::render(&env.name, bindings)?,
                            value: template::render(&env.value, bindings)?,
                        })
                    })
                    .collect::<Result<Vec<_>, ArchiveError>>()?,
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_direct_sources_and_renders_links() -> Result<(), ArchiveError> {
        let source = Source::Direct {
            version: "1.2.3".into(),
            url: "https://example.invalid/{{ version }}/{{ platform }}/tool.tar.gz".into(),
        };
        let resolved = resolve_source(&source, "aarch64-test")?;
        assert_eq!(resolved.version, "1.2.3");
        assert_eq!(
            resolved.url,
            "https://example.invalid/1.2.3/aarch64-test/tool.tar.gz"
        );

        let mut bindings = HashMap::new();
        bindings.insert("version", "1.2.3");
        bindings.insert("platform", "aarch64-test");
        let links = render_links(
            &[Link {
                name: "tool-{{ version }}".into(),
                path: "bin/{{ platform }}/tool".into(),
                env: vec![crate::catalog::EnvVar {
                    name: "TOOL_VERSION".into(),
                    value: "{{ version }}".into(),
                }],
            }],
            &bindings,
        )?;

        assert_eq!(links[0].name, "tool-1.2.3");
        assert_eq!(links[0].path, "bin/aarch64-test/tool");
        assert_eq!(links[0].env[0].name, "TOOL_VERSION");
        assert_eq!(links[0].env[0].value, "1.2.3");
        Ok(())
    }
}
