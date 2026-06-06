use crate::config::RouteConfig;
use crate::error::{Error, Result};
use crate::response::{Body, FixtureHttpResponse, FixtureResponse};

#[derive(Debug, Clone)]
pub(crate) struct Route {
    name: Option<String>,
    method: Option<String>,
    matcher: PathMatcher,
    response: FixtureResponse,
}

#[derive(Debug, Clone)]
enum PathMatcher {
    Exact(String),
    Prefix(String),
    Suffix(String),
}

impl Route {
    pub(crate) fn try_from_config(index: usize, route: RouteConfig) -> Result<Self> {
        let RouteConfig {
            name,
            method,
            path,
            path_prefix,
            path_suffix,
            status,
            content_type,
            headers,
            body,
            body_html,
            body_json,
        } = route;

        let matchers = [
            path.map(PathMatcher::Exact),
            path_prefix.map(PathMatcher::Prefix),
            path_suffix.map(PathMatcher::Suffix),
        ];
        let mut present_matchers = matchers.into_iter().flatten();
        let matcher = present_matchers
            .next()
            .ok_or(Error::InvalidRouteMatcher { index })?;
        if present_matchers.next().is_some() {
            return Err(Error::InvalidRouteMatcher { index });
        }

        let body_count = usize::from(body.is_some())
            + usize::from(body_html.is_some())
            + usize::from(body_json.is_some());
        if body_count > 1 {
            return Err(Error::InvalidRouteBody { index });
        }
        let body = match (body, body_html, body_json) {
            (Some(body), None, None) => Body::Text(body),
            (None, Some(body), None) => Body::Html(body),
            (None, None, Some(body)) => Body::Json(body),
            (None, None, None) => Body::Empty,
            _ => return Err(Error::InvalidRouteBody { index }),
        };

        Ok(Self {
            name,
            method: method.map(|method| method.to_ascii_uppercase()),
            matcher,
            response: FixtureResponse {
                status: status.unwrap_or(200),
                content_type,
                headers,
                body,
            },
        })
    }

    pub(crate) fn matches(&self, method: &str, path: &str) -> bool {
        let method_matches = self
            .method
            .as_ref()
            .is_none_or(|configured| configured.eq_ignore_ascii_case(method));
        method_matches && self.matcher.matches(path)
    }

    pub(crate) fn to_response(&self) -> Result<FixtureHttpResponse> {
        self.response.to_response()
    }

    pub(crate) fn describe(&self) -> String {
        let method = self.method.as_deref().unwrap_or("*");
        let matcher = self.matcher.describe();
        match &self.name {
            Some(name) => format!("{method} {matcher} ({name})"),
            None => format!("{method} {matcher}"),
        }
    }
}

impl PathMatcher {
    fn matches(&self, path: &str) -> bool {
        match self {
            Self::Exact(exact) => path == exact,
            Self::Prefix(prefix) => path.starts_with(prefix),
            Self::Suffix(suffix) => path.ends_with(suffix),
        }
    }

    fn describe(&self) -> String {
        match self {
            Self::Exact(path) => path.clone(),
            Self::Prefix(path) => format!("{path}*"),
            Self::Suffix(path) => format!("*{path}"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn matches_exact_prefix_suffix_and_methods() -> Result<()> {
        let exact = Route::try_from_config(
            0,
            RouteConfig {
                name: None,
                method: Some("GET".into()),
                path: Some("/exact".into()),
                path_prefix: None,
                path_suffix: None,
                status: None,
                content_type: None,
                headers: Default::default(),
                body: None,
                body_html: None,
                body_json: None,
            },
        )?;
        assert!(exact.matches("GET", "/exact"));
        assert!(!exact.matches("POST", "/exact"));
        assert!(!exact.matches("GET", "/exactly"));

        let prefix = Route::try_from_config(
            1,
            RouteConfig {
                name: None,
                method: None,
                path: None,
                path_prefix: Some("/assets/".into()),
                path_suffix: None,
                status: None,
                content_type: None,
                headers: Default::default(),
                body: None,
                body_html: None,
                body_json: Some(json!({ "ok": true })),
            },
        )?;
        assert!(prefix.matches("GET", "/assets/app.js"));

        let suffix = Route::try_from_config(
            2,
            RouteConfig {
                name: None,
                method: None,
                path: None,
                path_prefix: None,
                path_suffix: Some(".html".into()),
                status: None,
                content_type: None,
                headers: Default::default(),
                body: None,
                body_html: Some("<h1>ok</h1>".into()),
                body_json: None,
            },
        )?;
        assert!(suffix.matches("GET", "/index.html"));
        assert!(!suffix.matches("GET", "/index.json"));
        Ok(())
    }
}
