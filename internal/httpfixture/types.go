package httpfixture

const (
	DefaultConfigPath = "/etc/http-fixture/config.toml"
	DefaultListen     = "127.0.0.1:8080"
)

type Options struct {
	Config string
	Listen string
}

type App struct {
	Listen string
	Routes []Route
}

type fixtureConfig struct {
	Listen string        `toml:"listen"`
	Routes []routeConfig `toml:"routes"`
}

type routeConfig struct {
	Name        string            `toml:"name"`
	Method      string            `toml:"method"`
	Path        string            `toml:"path"`
	PathPrefix  string            `toml:"path_prefix"`
	PathSuffix  string            `toml:"path_suffix"`
	Status      uint16            `toml:"status"`
	ContentType string            `toml:"content_type"`
	Headers     map[string]string `toml:"headers"`
	Body        *string           `toml:"body"`
	BodyHTML    *string           `toml:"body_html"`
	BodyJSON    any               `toml:"body_json"`
}

type Route struct {
	Name     string
	Method   string
	Matcher  PathMatcher
	Response FixtureResponse
}

type PathMatcher struct {
	Kind  string
	Value string
}

type FixtureResponse struct {
	Status      int
	ContentType string
	Headers     map[string]string
	Body        Body
}

type Body struct {
	Kind  string
	Text  string
	Value any
}
