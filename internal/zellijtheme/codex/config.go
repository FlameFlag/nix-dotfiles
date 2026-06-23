package codex

import (
	"net"
	"net/url"
	"strings"
	"time"

	"github.com/FlameFlag/nix-dotfiles/internal/common/envx"
	"github.com/pelletier/go-toml/v2"
)

const mcpConnectTimeout = 150 * time.Millisecond

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
	environment := envx.MustParse[environment]()
	value := firstNonEmpty(
		environment.PruneUnreachableMCP,
		environment.LegacyPruneUnreachableMCP,
	)
	normalized := strings.TrimSpace(value)
	return value == "" ||
		(!strings.EqualFold(normalized, "0") && !strings.EqualFold(normalized, "false"))
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
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
		if enabled, ok := table["enabled"].(bool); ok && !enabled {
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

func filterUnreachableMCPEnableArgs(existing string, args []string) []string {
	if len(args) == 0 || !shouldPruneUnreachableMCP() {
		return args
	}
	doc := map[string]any{}
	if strings.TrimSpace(existing) == "" {
		return args
	}
	if err := toml.Unmarshal([]byte(existing), &doc); err != nil {
		return args
	}
	unreachable := unreachableLocalMCPServers(doc)
	if len(unreachable) == 0 {
		return args
	}
	out := make([]string, 0, len(args))
	for index := 0; index < len(args); index++ {
		arg := args[index]
		if arg == "-c" || arg == "--config" {
			if index+1 < len(args) && enablesUnreachableMCP(args[index+1], unreachable) {
				index++
				continue
			}
			out = append(out, arg)
			continue
		}
		if value, ok := strings.CutPrefix(arg, "-c="); ok && enablesUnreachableMCP(value, unreachable) {
			continue
		}
		if value, ok := strings.CutPrefix(arg, "--config="); ok && enablesUnreachableMCP(value, unreachable) {
			continue
		}
		out = append(out, arg)
	}
	return out
}

func unreachableLocalMCPServers(doc map[string]any) map[string]struct{} {
	out := map[string]struct{}{}
	servers, ok := doc["mcp_servers"].(map[string]any)
	if !ok {
		return out
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
		out[name] = struct{}{}
	}
	return out
}

func enablesUnreachableMCP(value string, unreachable map[string]struct{}) bool {
	key, raw, ok := strings.Cut(value, "=")
	if !ok {
		return false
	}
	if !strings.EqualFold(strings.TrimSpace(raw), "true") {
		return false
	}
	const prefix = "mcp_servers."
	const suffix = ".enabled"
	if !strings.HasPrefix(key, prefix) || !strings.HasSuffix(key, suffix) {
		return false
	}
	name := strings.TrimSuffix(strings.TrimPrefix(key, prefix), suffix)
	_, ok = unreachable[name]
	return ok
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
