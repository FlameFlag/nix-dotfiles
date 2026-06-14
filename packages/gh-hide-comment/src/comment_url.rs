use crate::error::{Error, Result};

#[derive(Debug, Clone, Copy)]
pub enum CommentKind {
    IssueComment,
    Discussion,
}

#[derive(Debug)]
pub struct Comment {
    pub id: String,
    pub kind: CommentKind,
    pub owner: String,
    pub repo: String,
}

pub fn parse(input: &str) -> Result<Comment> {
    let Some((raw_url, fragment)) = input.split_once('#') else {
        let (host, _) = split_url(input)?;
        return if host.eq_ignore_ascii_case("github.com") {
            Err(Error::MissingCommentAnchor)
        } else {
            Err(Error::NotGithubUrl)
        };
    };
    let (host, path) = split_url(raw_url)?;
    if !host.eq_ignore_ascii_case("github.com") {
        return Err(Error::NotGithubUrl);
    }

    let mut segments = path.split('?').next().unwrap_or(path).split('/');
    let owner = segments.next().ok_or(Error::InvalidRepoPath)?;
    let repo = segments.next().ok_or(Error::InvalidRepoPath)?;
    let route = segments.next().ok_or(Error::InvalidRepoPath)?;
    let _number = segments.next().ok_or(Error::InvalidRepoPath)?;
    if owner.is_empty() || repo.is_empty() || !matches!(route, "pull" | "issues") {
        return Err(Error::InvalidRepoPath);
    }

    let (kind, id) = parse_anchor(fragment)?;
    Ok(Comment {
        id: id.to_owned(),
        kind,
        owner: owner.to_owned(),
        repo: repo.to_owned(),
    })
}

fn split_url(input: &str) -> Result<(&str, &str)> {
    let (_, rest) = input.split_once("://").ok_or(Error::NotGithubUrl)?;
    let (authority, path) = rest.split_once('/').unwrap_or((rest, ""));
    Ok((host_without_port(authority), path))
}

fn host_without_port(authority: &str) -> &str {
    let host = authority.rsplit('@').next().unwrap_or(authority);
    if host.starts_with('[') {
        return host
            .split_once(']')
            .map_or(host, |(host, _)| host.trim_start_matches('['));
    }
    host.split_once(':').map_or(host, |(host, _)| host)
}

fn parse_anchor(anchor: &str) -> Result<(CommentKind, &str)> {
    let (kind, id) = match (
        anchor.strip_prefix("issuecomment"),
        anchor.strip_prefix("discussion_r"),
    ) {
        (Some(id), _) => (CommentKind::IssueComment, id),
        (None, Some(id)) => (CommentKind::Discussion, id),
        (None, None) => return Err(Error::InvalidCommentAnchor),
    };
    let id = id.strip_prefix('-').unwrap_or(id);
    if id.is_empty() || !id.bytes().all(|byte| byte.is_ascii_digit()) {
        return Err(Error::InvalidCommentAnchor);
    }
    Ok((kind, id))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_comment_urls() -> Result<()> {
        let issue = parse("https://github.com/rust-lang/rust/issues/26#issuecomment-164134155")?;
        assert_eq!(issue.owner, "rust-lang");
        assert_eq!(issue.repo, "rust");
        assert_eq!(issue.id, "164134155");
        assert!(matches!(issue.kind, CommentKind::IssueComment));

        let review = parse("https://github.com/rust-lang/rust/pull/96#discussion_r51070516")?;
        assert_eq!(review.id, "51070516");
        assert!(matches!(review.kind, CommentKind::Discussion));
        Ok(())
    }

    #[test]
    fn rejects_invalid_comment_urls() {
        assert!(matches!(
            parse("https://example.com/rust-lang/rust/issues/26#issuecomment-164134155"),
            Err(Error::NotGithubUrl)
        ));
        assert!(matches!(
            parse("https://github.com/rust-lang/rust/issues/26"),
            Err(Error::MissingCommentAnchor)
        ));
        assert!(matches!(
            parse("https://github.com/rust-lang/rust/issues/26#commitcomment-123"),
            Err(Error::InvalidCommentAnchor)
        ));
    }

    #[test]
    fn accepts_github_urls_with_ports() -> Result<()> {
        let issue =
            parse("https://github.com:443/rust-lang/rust/issues/26#issuecomment-164134155")?;
        assert_eq!(issue.owner, "rust-lang");
        assert_eq!(issue.repo, "rust");
        Ok(())
    }
}
