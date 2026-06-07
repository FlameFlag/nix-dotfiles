use std::fs;
use std::net::SocketAddr;

use crate::cli::{Cli, DEFAULT_LISTEN};
use crate::config::FixtureConfig;
use crate::error::{Error, Result};
use crate::route::Route;

#[derive(Debug)]
pub(crate) struct App {
    pub(crate) listen: SocketAddr,
    pub(crate) routes: Vec<Route>,
}

pub(crate) fn load_app(cli: &Cli) -> Result<App> {
    let config_text = fs::read_to_string(&cli.config).map_err(|source| Error::ReadConfig {
        path: cli.config.clone(),
        source,
    })?;
    let config: FixtureConfig =
        toml::from_str(&config_text).map_err(|source| Error::ParseConfig {
            path: cli.config.clone(),
            source,
        })?;
    let listen = match cli.listen {
        Some(listen) => listen,
        None => config.listen.as_deref().unwrap_or(DEFAULT_LISTEN).parse()?,
    };
    let routes = config
        .routes
        .into_iter()
        .enumerate()
        .map(|(index, route)| Route::try_from_config(index, route))
        .collect::<Result<Vec<_>>>()?;

    Ok(App { listen, routes })
}
