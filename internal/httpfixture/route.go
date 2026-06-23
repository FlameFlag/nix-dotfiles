package httpfixture

import "strings"

type matcherBehavior struct {
	matches  func(path, value string) bool
	describe func(value string) string
}

var matcherBehaviors = map[string]matcherBehavior{
	"exact": {
		matches:  func(path, value string) bool { return path == value },
		describe: func(value string) string { return value },
	},
	"prefix": {
		matches:  strings.HasPrefix,
		describe: func(value string) string { return value + "*" },
	},
	"suffix": {
		matches:  strings.HasSuffix,
		describe: func(value string) string { return "*" + value },
	},
}

func (r Route) Describe() string {
	method := r.Method
	if method == "" {
		method = "*"
	}
	description := method + " " + r.Matcher.Describe()
	if r.Name != "" {
		description += " (" + r.Name + ")"
	}
	return description
}

func (m PathMatcher) Matches(path string) bool {
	behavior, ok := matcherBehaviors[m.Kind]
	if !ok {
		return false
	}
	return behavior.matches(path, m.Value)
}

func (m PathMatcher) Describe() string {
	behavior, ok := matcherBehaviors[m.Kind]
	if !ok {
		return m.Value
	}
	return behavior.describe(m.Value)
}
