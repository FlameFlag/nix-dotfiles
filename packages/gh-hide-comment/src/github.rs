use dotfiles_common::http::{Client, StatusCode};
use secrecy::{ExposeSecret, SecretString};
use serde::Deserialize;

use crate::cli::Reason;
use crate::comment_url::{self, Comment, CommentKind};
use crate::error::{Error, Result};

#[derive(Debug, Deserialize)]
struct CommentResponse {
    node_id: String,
}

#[derive(Debug, Deserialize)]
struct GraphqlResponse {
    data: Option<MinimizeData>,
    errors: Option<serde_json::Value>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct MinimizeData {
    minimize_comment: MinimizeCommentPayload,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct MinimizeCommentPayload {
    minimized_comment: MinimizedComment,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct MinimizedComment {
    is_minimized: bool,
    minimized_reason: String,
}

pub fn hide(
    client: &Client,
    token: &SecretString,
    comment_url: &str,
    reason: Reason,
) -> Result<String> {
    let comment = comment_url::parse(comment_url)?;
    let node_id = node_id(client, token, &comment)?;
    minimize(client, token, &node_id, reason)
}

fn node_id(client: &Client, token: &SecretString, comment: &Comment) -> Result<String> {
    let response = client.get_bearer_text(&node_id_url(comment), token.expose_secret())?;
    parse_node_id_response(response.status, &response.body)
}

fn node_id_url(comment: &Comment) -> String {
    match comment.kind {
        CommentKind::IssueComment => format!(
            "https://api.github.com/repos/{}/{}/issues/comments/{}",
            comment.owner, comment.repo, comment.id
        ),
        CommentKind::Discussion => format!(
            "https://api.github.com/repos/{}/{}/pulls/comments/{}",
            comment.owner, comment.repo, comment.id
        ),
    }
}

fn parse_node_id_response(status: StatusCode, body: &str) -> Result<String> {
    if !status.is_success() {
        return Err(Error::GithubApi {
            status: status.as_u16(),
            body: body.to_owned(),
        });
    }
    Ok(serde_json::from_str::<CommentResponse>(body)
        .map_err(|err| Error::GithubApi {
            status: 200,
            body: err.to_string(),
        })?
        .node_id)
}

fn minimize(client: &Client, token: &SecretString, id: &str, reason: Reason) -> Result<String> {
    let response = client.post_json_bearer_text(
        "https://api.github.com/graphql",
        token.expose_secret(),
        &serde_json::json!({
            "query": "mutation HideComment($id: ID!, $reason: ReportedContentClassifiers!) { minimizeComment(input: { subjectId: $id, classifier: $reason }) { minimizedComment { isMinimized minimizedReason } } }",
            "variables": {
                "id": id,
                "reason": classifier(reason),
            },
        }),
    )?;
    parse_minimize_response(response.status, &response.body)
}

fn parse_minimize_response(status: StatusCode, body: &str) -> Result<String> {
    if !status.is_success() {
        return Err(Error::GithubApi {
            status: status.as_u16(),
            body: body.to_owned(),
        });
    }
    let response =
        serde_json::from_str::<GraphqlResponse>(body).map_err(|err| Error::GithubApi {
            status: 200,
            body: err.to_string(),
        })?;
    let Some(data) = response.data else {
        return Err(Error::GithubApi {
            status: 200,
            body: response.errors.map_or_else(
                || "missing GraphQL response data".to_owned(),
                |errors| errors.to_string(),
            ),
        });
    };
    let minimized = data.minimize_comment.minimized_comment;
    if minimized.is_minimized {
        Ok(minimized.minimized_reason)
    } else {
        Err(Error::UnexpectedMinimizeResponse)
    }
}

const fn classifier(reason: Reason) -> &'static str {
    match reason {
        Reason::Outdated => "OUTDATED",
        Reason::Duplicate => "DUPLICATE",
        Reason::OffTopic => "OFF_TOPIC",
        Reason::Resolved => "RESOLVED",
        Reason::Spam => "SPAM",
        Reason::Abuse => "ABUSE",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classifiers_match_github_graphql_values() {
        assert_eq!(classifier(Reason::Outdated), "OUTDATED");
        assert_eq!(classifier(Reason::Duplicate), "DUPLICATE");
        assert_eq!(classifier(Reason::OffTopic), "OFF_TOPIC");
        assert_eq!(classifier(Reason::Resolved), "RESOLVED");
        assert_eq!(classifier(Reason::Spam), "SPAM");
        assert_eq!(classifier(Reason::Abuse), "ABUSE");
    }

    #[test]
    fn parse_minimize_response_returns_reason_when_minimized() {
        let body = r#"{
            "data": {
                "minimizeComment": {
                    "minimizedComment": {
                        "isMinimized": true,
                        "minimizedReason": "OUTDATED"
                    }
                }
            }
        }"#;

        let reason = parse_minimize_response(StatusCode::OK, body).expect("reason");

        assert_eq!(reason, "OUTDATED");
    }

    #[test]
    fn parse_minimize_response_reports_graphql_errors_without_data() {
        let body = r#"{"errors":[{"message":"nope"}]}"#;

        let err = parse_minimize_response(StatusCode::OK, body).expect_err("error");

        assert!(err.to_string().contains("nope"));
    }

    #[test]
    fn node_id_urls_match_github_comment_kinds() {
        let issue = Comment {
            kind: CommentKind::IssueComment,
            owner: "owner".to_owned(),
            repo: "repo".to_owned(),
            id: "42".to_owned(),
        };
        let discussion = Comment {
            kind: CommentKind::Discussion,
            owner: "owner".to_owned(),
            repo: "repo".to_owned(),
            id: "43".to_owned(),
        };

        assert_eq!(
            node_id_url(&issue),
            "https://api.github.com/repos/owner/repo/issues/comments/42"
        );
        assert_eq!(
            node_id_url(&discussion),
            "https://api.github.com/repos/owner/repo/pulls/comments/43"
        );
    }

    #[test]
    fn parse_node_id_response_reads_rest_payload() {
        let node_id =
            parse_node_id_response(StatusCode::OK, r#"{"node_id":"IC_kw"}"#).expect("node id");

        assert_eq!(node_id, "IC_kw");
    }
}
