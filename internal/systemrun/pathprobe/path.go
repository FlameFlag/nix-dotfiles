package pathprobe

import (
	"bytes"
	"context"
	_ "embed"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/pelletier/go-toml/v2"
)

const (
	pathProbeTimeout = 5 * time.Second
	pathMarkerStart  = "__SYSTEM_RUN_MCP_PATH_START__"
	pathMarkerEnd    = "__SYSTEM_RUN_MCP_PATH_END__"
	pathProbeScript  = "printf '%s\n' __SYSTEM_RUN_MCP_PATH_START__; printf '%s\n' \"$PATH\"; printf '%s\n' __SYSTEM_RUN_MCP_PATH_END__"
)

//go:embed defaults.toml
var defaultPolicyData []byte

var defaultPolicy = mustLoadPolicy(defaultPolicyData)

type policy struct {
	ShellProbeCandidates []string          `toml:"shell_probe_candidates"`
	ShellProbeFlags      map[string]string `toml:"shell_probe_flags"`
	UserToolPathPrefixes []string          `toml:"user_tool_path_prefixes"`
}

func mustLoadPolicy(data []byte) policy {
	policy, err := loadPolicy(data)
	if err != nil {
		panic(err)
	}
	return policy
}

func loadPolicy(data []byte) (policy, error) {
	var policy policy
	if err := toml.Unmarshal(data, &policy); err != nil {
		return policy, fmt.Errorf("parse embedded path probe defaults: %w", err)
	}
	if len(policy.ShellProbeCandidates) == 0 {
		return policy, fmt.Errorf("embedded path probe defaults are missing shell_probe_candidates")
	}
	if len(policy.UserToolPathPrefixes) == 0 {
		return policy, fmt.Errorf(
			"embedded path probe defaults are missing user_tool_path_prefixes",
		)
	}
	if policy.ShellProbeFlags == nil {
		policy.ShellProbeFlags = map[string]string{}
	}
	return policy, nil
}

func UserShellPath() string {
	home := os.Getenv("HOME")
	for _, shell := range candidateShells(os.Getenv("SHELL")) {
		flag := "-c"
		if configuredFlag, ok := defaultPolicy.ShellProbeFlags[filepath.Base(shell)]; ok {
			flag = configuredFlag
		}
		ctx, cancel := context.WithTimeout(context.Background(), pathProbeTimeout)
		cmd := exec.CommandContext(ctx, shell, flag, pathProbeScript)
		if home != "" {
			cmd.Env = append(os.Environ(), "HOME="+home)
		}
		output, err := cmd.Output()
		cancel()
		if err != nil {
			continue
		}
		path := ParseMarkedPath(output)
		if path != "" {
			return NormalizeUserShellPath(path, home)
		}
	}
	return ""
}

func candidateShells(primary string) []string {
	seen := map[string]bool{}
	var shells []string
	for _, shell := range slices.Concat([]string{primary}, defaultPolicy.ShellProbeCandidates) {
		if shell != "" && !seen[shell] {
			seen[shell] = true
			shells = append(shells, shell)
		}
	}
	return shells
}

func NormalizeUserShellPath(path, home string) string {
	if home == "" {
		return path
	}
	seen := map[string]bool{}
	var entries []string
	for _, entry := range filepath.SplitList(path) {
		seen[entry] = true
	}
	for _, prefix := range defaultPolicy.UserToolPathPrefixes {
		entry := filepath.Join(home, prefix)
		if !seen[entry] {
			seen[entry] = true
			entries = append(entries, entry)
		}
	}
	for _, entry := range filepath.SplitList(path) {
		if entry != "" {
			entries = append(entries, entry)
		}
	}
	return strings.Join(entries, string(os.PathListSeparator))
}

func ParseMarkedPath(output []byte) string {
	_, rest, ok := bytes.Cut(output, []byte(pathMarkerStart))
	if !ok {
		return ""
	}
	rest = bytes.TrimPrefix(rest, []byte("\n"))
	path, _, ok := bytes.Cut(rest, []byte(pathMarkerEnd))
	if !ok {
		return ""
	}
	path = bytes.TrimRight(path, "\r\n")
	return string(path)
}
