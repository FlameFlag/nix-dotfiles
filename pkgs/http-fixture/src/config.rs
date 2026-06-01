use std::collections::BTreeMap;

use serde::Deserialize;
use serde_json::Value;

#[derive(Debug, Deserialize)]
pub(crate) struct FixtureConfig {
    pub(crate) listen: Option<String>,
    #[serde(default)]
    pub(crate) routes: Vec<RouteConfig>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct RouteConfig {
    pub(crate) name: Option<String>,
    pub(crate) method: Option<String>,
    pub(crate) path: Option<String>,
    pub(crate) path_prefix: Option<String>,
    pub(crate) path_suffix: Option<String>,
    pub(crate) status: Option<u16>,
    pub(crate) content_type: Option<String>,
    #[serde(default)]
    pub(crate) headers: BTreeMap<String, String>,
    pub(crate) body: Option<String>,
    pub(crate) body_html: Option<String>,
    pub(crate) body_json: Option<Value>,
}
