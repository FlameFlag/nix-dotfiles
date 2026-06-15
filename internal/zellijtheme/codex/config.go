package codex

import (
	"net"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/pelletier/go-toml/v2"
)

const mcpConnectTimeout = 150 * time.Millisecond

var pruneUnreachableMCPEnvNames = []string{
	"ZELLIJ_THEME_RUN_PRUNE_UNREACHABLE_MCP",
	"CODEX_ZELLIJ_THEME_PRUNE_UNREACHABLE_MCP",
}

func trustedConfig(existing, trustTarget, tuiTheme string) (string, error) {
	doc := map[string]any{}
	if strings.TrimSpace(existing) != "" {
		if err := toml.Unmarshal([]byte(existing), &doc); err != nil {
			return "", err
		}
	}
	if shouldPruneUnreachableMCP() {
		pruneUnreachableMCPServers(doc)
	}
	doc["approval_policy"] = "never"
	doc["sandbox_mode"] = "danger-full-access"
	doc["web_search"] = "live"
	doc["trust_level"] = "trusted"
	tui := ensureTable(doc, "tui")
	tui["theme"] = tuiTheme
	projects := ensureTable(doc, "projects")
	project := ensureTable(projects, trustTarget)
	project["trust_level"] = "trusted"
	out, err := toml.Marshal(doc)
	return string(out), err
}

func shouldPruneUnreachableMCP() bool {
	value := ""
	for _, name := range pruneUnreachableMCPEnvNames {
		if value = os.Getenv(name); value != "" {
			break
		}
	}
	normalized := strings.TrimSpace(value)
	return value == "" ||
		(!strings.EqualFold(normalized, "0") && !strings.EqualFold(normalized, "false"))
}

func pruneUnreachableMCPServers(doc map[string]any) {
	servers, ok := doc["mcp_servers"].(map[string]any)
	if !ok {
		return
	}
	for name, item := range servers {
		table, ok := item.(map[string]any)
		if !ok {
			continue
		}
		raw, _ := table["url"].(string)
		host, port, ok := localHTTPAddress(raw)
		if !ok {
			continue
		}
		conn, err := net.DialTimeout("tcp", net.JoinHostPort(host, port), mcpConnectTimeout)
		if err == nil {
			_ = conn.Close()
			continue
		}
		delete(servers, name)
	}
}

func localHTTPAddress(raw string) (string, string, bool) {
	parsed, err := url.Parse(raw)
	if err != nil {
		return "", "", false
	}
	isHTTP := parsed.Scheme == "http" || parsed.Scheme == "https"
	if !isHTTP {
		return "", "", false
	}
	host := parsed.Hostname()
	ip := net.ParseIP(host)
	isLocalhost := strings.EqualFold(host, "localhost")
	isLoopbackIP := ip != nil && ip.IsLoopback()
	if !isLocalhost && !isLoopbackIP {
		return "", "", false
	}
	port := parsed.Port()
	if port == "" {
		port = defaultPort(parsed.Scheme)
	}
	return host, port, true
}

func defaultPort(scheme string) string {
	if scheme == "https" {
		return "443"
	}
	return "80"
}

func ensureTable(doc map[string]any, key string) map[string]any {
	if table, ok := doc[key].(map[string]any); ok {
		return table
	}
	table := map[string]any{}
	doc[key] = table
	return table
}
