use std::collections::BTreeMap;

use rouille::Response;
use serde_json::Value;

use crate::error::Result;

pub(crate) type FixtureHttpResponse = Response;

#[derive(Debug, Clone)]
pub(crate) struct FixtureResponse {
    pub(crate) status: u16,
    pub(crate) content_type: Option<String>,
    pub(crate) headers: BTreeMap<String, String>,
    pub(crate) body: Body,
}

#[derive(Debug, Clone)]
pub(crate) enum Body {
    Text(String),
    Html(String),
    Json(Value),
    Empty,
}

impl FixtureResponse {
    pub(crate) fn to_response(&self) -> Result<FixtureHttpResponse> {
        let (body, inferred_content_type) = match &self.body {
            Body::Text(body) => (body.as_bytes().to_vec(), Some("text/plain; charset=utf-8")),
            Body::Html(body) => (body.as_bytes().to_vec(), Some("text/html; charset=utf-8")),
            Body::Json(body) => (serde_json::to_vec(body)?, Some("application/json")),
            Body::Empty => (Vec::new(), None),
        };
        let content_type = self
            .content_type
            .as_deref()
            .or(inferred_content_type)
            .unwrap_or("application/octet-stream");
        let mut response = Response::from_data(content_type.to_owned(), body)
            .with_status_code(self.status)
            .without_header("Content-Type");
        if let Some(content_type) = self.content_type.as_deref().or(inferred_content_type) {
            response = response.with_additional_header("Content-Type", content_type.to_owned());
        }
        for (name, value) in &self.headers {
            response = response.with_additional_header(name.clone(), value.clone());
        }
        Ok(response)
    }
}

pub(crate) fn not_found_response() -> Result<FixtureHttpResponse> {
    let body = serde_json::json!({ "error": "not_found" });
    Ok(Response::from_data("application/json", serde_json::to_vec(&body)?).with_status_code(404))
}

pub(crate) fn internal_error_response() -> FixtureHttpResponse {
    Response::from_data("application/json", r#"{"error":"internal_error"}"#).with_status_code(500)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::io::Read;

    #[test]
    fn builds_json_html_headers_and_not_found_responses()
    -> std::result::Result<(), Box<dyn std::error::Error>> {
        let mut headers = BTreeMap::new();
        headers.insert("X-Fixture".into(), "yes".into());
        let response = FixtureResponse {
            status: 202,
            content_type: None,
            headers,
            body: Body::Json(json!({ "ok": true })),
        }
        .to_response()?;

        assert_eq!(response.status_code, 202);
        assert_header(&response, "Content-Type", "application/json");
        assert_header(&response, "X-Fixture", "yes");
        assert_eq!(body_text(response)?, r#"{"ok":true}"#);

        let response = FixtureResponse {
            status: 200,
            content_type: None,
            headers: BTreeMap::new(),
            body: Body::Html("<h1>ok</h1>".into()),
        }
        .to_response()?;
        assert_header(&response, "Content-Type", "text/html; charset=utf-8");

        let response = not_found_response()?;
        assert_eq!(response.status_code, 404);
        assert_eq!(body_text(response)?, r#"{"error":"not_found"}"#);
        Ok(())
    }

    fn assert_header(response: &Response, name: &str, value: &str) {
        assert!(response.headers.iter().any(|(header_name, header_value)| {
            header_name.eq_ignore_ascii_case(name) && header_value == value
        }));
    }

    fn body_text(response: Response) -> std::io::Result<String> {
        let (mut reader, _) = response.data.into_reader_and_size();
        let mut body = String::new();
        reader.read_to_string(&mut body)?;
        Ok(body)
    }
}
