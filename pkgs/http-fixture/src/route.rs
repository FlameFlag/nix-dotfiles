use tiny_http::{Method, StatusCode};

use crate::config::RouteConfig;
use crate::error::{Error, Result};
use crate::response::{Body, FixtureHttpResponse, FixtureResponse};

#[derive(Debug)]
pub(crate) struct Route {
    name: Option<String>,
    method: Option<String>,
    matcher: PathMatcher,
    response: FixtureResponse,
}

#[derive(Debug)]
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
                status: StatusCode(status.unwrap_or(200)),
                content_type,
                headers,
                body,
            },
        })
    }

    pub(crate) fn matches(&self, method: &Method, path: &str) -> bool {
        let method_matches = self
            .method
            .as_ref()
            .is_none_or(|configured| configured.eq_ignore_ascii_case(&method.to_string()));
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
