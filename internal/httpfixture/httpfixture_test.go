package httpfixture

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRouteMatching(t *testing.T) {
	route, err := routeFromConfig(0, routeConfig{Method: "get", Path: "/exact"})
	if err != nil {
		t.Fatal(err)
	}
	matchesGetExact := (route.Method == "" || strings.EqualFold(route.Method, "GET")) &&
		route.Matcher.Matches("/exact")
	matchesPostExact := (route.Method == "" || strings.EqualFold(route.Method, "POST")) &&
		route.Matcher.Matches("/exact")
	matchesGetExactly := (route.Method == "" || strings.EqualFold(route.Method, "GET")) &&
		route.Matcher.Matches("/exactly")
	if !matchesGetExact || matchesPostExact || matchesGetExactly {
		t.Fatalf("exact route matching failed")
	}
	prefix, err := routeFromConfig(1, routeConfig{PathPrefix: "/assets/"})
	if err != nil {
		t.Fatal(err)
	}
	if !prefix.Matcher.Matches("/assets/app.js") {
		t.Fatalf("prefix route did not match")
	}
	suffix, err := routeFromConfig(2, routeConfig{PathSuffix: ".html"})
	if err != nil {
		t.Fatal(err)
	}
	if !suffix.Matcher.Matches("/index.html") || suffix.Matcher.Matches("/index.json") {
		t.Fatalf("suffix route matching failed")
	}
}

func TestResponseHeadersAndBodies(t *testing.T) {
	response := FixtureResponse{
		Status:  202,
		Headers: map[string]string{"X-Fixture": "yes"},
		Body:    Body{Kind: "json", Value: map[string]bool{"ok": true}},
	}
	recorder := httptest.NewRecorder()
	response.Write(recorder)
	if recorder.Code != 202 {
		t.Fatalf("status = %d; want 202", recorder.Code)
	}
	if got := recorder.Header().Get("Content-Type"); got != "application/json" {
		t.Fatalf("content-type = %q", got)
	}
	if got := strings.TrimSpace(recorder.Body.String()); got != `{"ok":true}` {
		t.Fatalf("body = %q", got)
	}
}

func TestRequestPath(t *testing.T) {
	tests := map[string]string{
		"/api/v1/example?ignored=true":                     "/api/v1/example",
		"https://alt-tab.app/website/public/app.js?x=true": "/website/public/app.js",
		"https://alt-tab.app?cache=false":                  "/",
		"health":                                           "/health",
	}
	for input, want := range tests {
		if got := RequestPath(input); got != want {
			t.Fatalf("RequestPath(%q) = %q; want %q", input, got, want)
		}
	}
}

func TestHandlerNotFound(t *testing.T) {
	app := App{}
	req := httptest.NewRequest(http.MethodGet, "/missing", nil)
	recorder := httptest.NewRecorder()
	app.handle(recorder, req)
	if recorder.Code != http.StatusNotFound {
		t.Fatalf("status = %d; want 404", recorder.Code)
	}
}
