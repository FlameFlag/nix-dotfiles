package zellijtheme

import "strings"

func SanitizeSessionName(raw string) string {
	var out strings.Builder
	pendingDash := false
	for _, ch := range raw {
		if isSessionNameChar(ch) {
			if pendingDash && out.Len() > 0 {
				out.WriteByte('-')
			}
			pendingDash = false
			out.WriteRune(ch)
		} else {
			pendingDash = true
		}
	}
	return out.String()
}

func isSessionNameChar(ch rune) bool {
	return (ch >= 'a' && ch <= 'z') ||
		(ch >= 'A' && ch <= 'Z') ||
		(ch >= '0' && ch <= '9') ||
		ch == '_' ||
		ch == '.' ||
		ch == '-'
}
