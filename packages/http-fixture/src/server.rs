use std::io::Read;
use std::time::{SystemTime, UNIX_EPOCH};

use rouille::{Request, Response, Server};
use url::Url;

use crate::app::App;
use crate::cli::Cli;
use crate::error::{Error, Result};
use crate::response::{internal_error_response, not_found_response};

const REQUEST_URL_BASE: &str = "http://http-fixture.local/";

pub(crate) fn serve(_cli: &Cli, app: &App) -> Result<()> {
    println!("http-fixture listening on http://{}", app.listen);
    for route in &app.routes {
        println!("{}", route.describe());
    }

    make_server(app)?.run();
    Ok(())
}

fn make_server(app: &App) -> Result<Server<impl Send + Sync + 'static + Fn(&Request) -> Response>> {
    let listen = app.listen;
    let routes = app.routes.clone();
    Server::new(listen, move |request| handle_request(request, &routes)).map_err(|source| {
        Error::Bind {
            addr: listen,
            source,
        }
    })
}

fn handle_request(request: &Request, routes: &[crate::route::Route]) -> Response {
    let method = request.method().to_owned();
    let url = request.raw_url().to_owned();
    let path = request_path(&url);
    let body = read_body(request).unwrap_or_else(|err| {
        eprintln!("failed to read request body: {err}");
        String::new()
    });

    log_request(&method, &url, &body);

    match routes
        .iter()
        .find(|route| route.matches(&method, &path))
        .map_or_else(not_found_response, |route| route.to_response())
    {
        Ok(response) => response,
        Err(err) => {
            eprintln!("failed to build response: {err}");
            internal_error_response()
        }
    }
}

fn read_body(request: &Request) -> std::io::Result<String> {
    let Some(mut body_reader) = request.data() else {
        return Ok(String::new());
    };
    let mut body = String::new();
    body_reader.read_to_string(&mut body)?;
    Ok(body)
}

fn request_path(url: &str) -> String {
    if let Ok(parsed) = Url::parse(url) {
        return parsed.path().to_owned();
    }

    if let Ok(base) = Url::parse(REQUEST_URL_BASE)
        && let Ok(parsed) = base.join(url)
    {
        return parsed.path().to_owned();
    }

    url.split_once('?').map_or(url, |(path, _)| path).to_owned()
}

fn log_request(method: &str, url: &str, body: &str) {
    const MAX_LOGGED_BODY_CHARS: usize = 500;

    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| duration.as_secs());
    if body.is_empty() {
        println!("[{timestamp}] {method} {url}");
    } else {
        let mut logged_body: String = body.chars().take(MAX_LOGGED_BODY_CHARS).collect();
        if logged_body.len() < body.len() {
            logged_body.push_str("...");
        }
        println!("[{timestamp}] {method} {url} body={logged_body}");
    }
}

#[cfg(test)]
mod tests {
    use super::request_path;

    #[test]
    fn request_path_handles_origin_form_urls() {
        assert_eq!(
            request_path("/api/v1/example?ignored=true"),
            "/api/v1/example"
        );
    }

    #[test]
    fn request_path_handles_absolute_urls() {
        assert_eq!(
            request_path("https://alt-tab.app/website/public/app.js?cache=false"),
            "/website/public/app.js"
        );
    }
}
