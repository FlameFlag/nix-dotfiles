package chromiumbrowser

import (
	_ "embed"
	"strings"

	"github.com/buildkite/shellwords"
)

//go:embed scripts/wrapper.sh
var wrapperScriptTemplate string

func renderWrapperScript(args []string) string {
	quoted := make([]string, 0, len(args))
	for _, arg := range args {
		quoted = append(quoted, shellwords.QuotePosix(arg))
	}
	return strings.ReplaceAll(wrapperScriptTemplate, "__COMMAND__", strings.Join(quoted, " "))
}
