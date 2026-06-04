use toml_edit::DocumentMut;
use url::Url;

const MCP_CONNECT_TIMEOUT: std::time::Duration = std::time::Duration::from_millis(150);

pub(super) fn prune_unreachable_local_mcp_servers(doc: &mut DocumentMut) {
    if !pruning_enabled() {
        return;
    }

    let Some(servers) = doc["mcp_servers"].as_table_mut() else {
        return;
    };
    let unreachable_servers = servers
        .iter()
        .filter_map(|(name, item)| {
            let url = item.get("url")?.as_str()?;
            local_mcp_url_is_unreachable(url).then(|| name.to_owned())
        })
        .collect::<Vec<_>>();

    for name in unreachable_servers {
        servers.remove(&name);
    }
}

fn pruning_enabled() -> bool {
    std::env::var("CODEX_ZELLIJ_THEME_PRUNE_UNREACHABLE_MCP")
        .map(|value| {
            let value = value.trim();
            !value.eq_ignore_ascii_case("0") && !value.eq_ignore_ascii_case("false")
        })
        .unwrap_or(true)
}

fn local_mcp_url_is_unreachable(raw: &str) -> bool {
    let Some((host, port)) = local_http_endpoint(raw) else {
        return false;
    };
    !tcp_endpoint_is_reachable(&host, port)
}

fn local_http_endpoint(raw: &str) -> Option<(String, u16)> {
    let url = Url::parse(raw).ok()?;
    if !matches!(url.scheme(), "http" | "https") {
        return None;
    }
    let host = url.host_str()?;
    if !host_is_loopback(host) {
        return None;
    }
    Some((host.to_owned(), url.port_or_known_default()?))
}

fn host_is_loopback(host: &str) -> bool {
    host.eq_ignore_ascii_case("localhost")
        || host
            .parse::<std::net::IpAddr>()
            .is_ok_and(|addr| addr.is_loopback())
}

fn tcp_endpoint_is_reachable(host: &str, port: u16) -> bool {
    use std::net::{TcpStream, ToSocketAddrs};

    let Ok(addrs) = (host, port).to_socket_addrs() else {
        return false;
    };
    addrs
        .into_iter()
        .any(|addr| TcpStream::connect_timeout(&addr, MCP_CONNECT_TIMEOUT).is_ok())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn local_http_endpoint_accepts_loopback_hosts_only() {
        assert_eq!(
            local_http_endpoint("http://127.0.0.1:8090/mcp"),
            Some(("127.0.0.1".to_owned(), 8090))
        );
        assert_eq!(
            local_http_endpoint("http://localhost:8090/mcp"),
            Some(("localhost".to_owned(), 8090))
        );
        assert_eq!(local_http_endpoint("https://example.com/mcp"), None);
    }
}
