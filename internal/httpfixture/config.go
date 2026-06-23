package httpfixture

import (
	"fmt"
	"net"
	"net/http"
	"os"
	"strings"

	"github.com/pelletier/go-toml/v2"
)

func Load(options Options) (App, error) {
	configPath := options.Config
	if configPath == "" {
		configPath = DefaultConfigPath
	}
	configText, err := os.ReadFile(configPath)
	if err != nil {
		return App{}, fmt.Errorf("failed to read config at %s: %w", configPath, err)
	}
	var config fixtureConfig
	if err := toml.Unmarshal(configText, &config); err != nil {
		return App{}, fmt.Errorf("failed to parse config at %s: %w", configPath, err)
	}
	listen := options.Listen
	if listen == "" {
		listen = config.Listen
	}
	if listen == "" {
		listen = DefaultListen
	}
	if _, err := net.ResolveTCPAddr("tcp", listen); err != nil {
		return App{}, fmt.Errorf("failed to parse socket address: %w", err)
	}
	routes := make([]Route, 0, len(config.Routes))
	for index, route := range config.Routes {
		parsed, err := routeFromConfig(index, route)
		if err != nil {
			return App{}, err
		}
		routes = append(routes, parsed)
	}
	return App{Listen: listen, Routes: routes}, nil
}

func routeFromConfig(index int, config routeConfig) (Route, error) {
	matcher, matchers := firstPresentMatcher(config)
	if matchers != 1 {
		return Route{}, fmt.Errorf(
			"route %d must set exactly one of path, path_prefix, or path_suffix",
			index,
		)
	}
	body, bodies := firstPresentBody(config)
	if bodies > 1 {
		return Route{}, fmt.Errorf(
			"route %d must set at most one of body, body_html, or body_json",
			index,
		)
	}

	status := int(config.Status)
	if status == 0 {
		status = http.StatusOK
	}
	return Route{
		Name:    config.Name,
		Method:  strings.ToUpper(config.Method),
		Matcher: matcher,
		Response: FixtureResponse{
			Status:      status,
			ContentType: config.ContentType,
			Headers:     config.Headers,
			Body:        body,
		},
	}, nil
}

func firstPresentMatcher(config routeConfig) (PathMatcher, int) {
	matcher := PathMatcher{}
	count := 0
	for _, spec := range []struct {
		kind  string
		value string
	}{
		{kind: "exact", value: config.Path},
		{kind: "prefix", value: config.PathPrefix},
		{kind: "suffix", value: config.PathSuffix},
	} {
		if spec.value != "" {
			count++
			matcher = PathMatcher{Kind: spec.kind, Value: spec.value}
		}
	}
	return matcher, count
}

func firstPresentBody(config routeConfig) (Body, int) {
	body := Body{Kind: "empty"}
	count := 0
	for _, spec := range []struct {
		isSet bool
		body  Body
	}{
		{isSet: config.Body != nil, body: derefTextBody("text", config.Body)},
		{isSet: config.BodyHTML != nil, body: derefTextBody("html", config.BodyHTML)},
		{isSet: config.BodyJSON != nil, body: Body{Kind: "json", Value: config.BodyJSON}},
	} {
		if spec.isSet {
			count++
			body = spec.body
		}
	}
	return body, count
}

func derefTextBody(kind string, text *string) Body {
	if text == nil {
		return Body{Kind: kind}
	}
	return Body{Kind: kind, Text: *text}
}
