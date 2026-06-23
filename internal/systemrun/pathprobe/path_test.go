package pathprobe

import (
	"strings"
	"testing"
)

func TestDefaultPolicyLoads(t *testing.T) {
	policy, err := loadPolicy(defaultPolicyData)
	if err != nil {
		t.Fatal(err)
	}
	if len(policy.ShellProbeCandidates) == 0 {
		t.Fatal("shell probe candidates were not loaded")
	}
	if got := policy.ShellProbeFlags["zsh"]; got != "-lic" {
		t.Fatalf("zsh probe flag = %q; want -lic", got)
	}
	if len(policy.UserToolPathPrefixes) == 0 {
		t.Fatal("user tool path prefixes were not loaded")
	}
}

func TestParseMarkedPath(t *testing.T) {
	output := []byte(
		"noise\n__SYSTEM_RUN_MCP_PATH_START__\n/one:/two\n__SYSTEM_RUN_MCP_PATH_END__\n",
	)
	if got := ParseMarkedPath(output); got != "/one:/two" {
		t.Fatalf("ParseMarkedPath = %q", got)
	}
}

func TestNormalizeUserShellPathPrependsToolDirs(t *testing.T) {
	got := NormalizeUserShellPath("/Users/me/.nix-profile/bin:/Users/me/.cargo/bin", "/Users/me")
	if !strings.HasPrefix(got, "/Users/me/.pi/agent/bin:") {
		t.Fatalf("normalized path did not prepend tool dirs: %s", got)
	}
	if strings.Count(got, "/Users/me/.cargo/bin") != 1 {
		t.Fatalf("normalized path duplicated cargo dir: %s", got)
	}
}
