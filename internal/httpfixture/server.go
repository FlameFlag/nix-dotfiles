package httpfixture

import (
	"errors"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/charmbracelet/log"
)

func Serve(app App) error {
	log.Info("http-fixture listening", "url", "http://"+app.Listen)
	for _, route := range app.Routes {
		log.Info("registered route", "route", route.Describe())
	}
	server := &http.Server{
		Addr:              app.Listen,
		Handler:           http.HandlerFunc(app.handle),
		ReadHeaderTimeout: 10 * time.Second,
	}
	err := server.ListenAndServe()
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}

func (app App) handle(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		log.Warn("failed to read request body", "err", err)
		body = nil
	}
	bodyText := string(body)
	if bodyText == "" {
		log.Info("request", "method", r.Method, "url", r.RequestURI)
	} else {
		runes := []rune(bodyText)
		if len(runes) > 500 {
			bodyText = string(runes[:500]) + "..."
		}
		log.Info("request", "method", r.Method, "url", r.RequestURI, "body", bodyText)
	}
	path := RequestPath(r.RequestURI)
	for _, route := range app.Routes {
		methodMatches := route.Method == "" || strings.EqualFold(route.Method, r.Method)
		pathMatches := route.Matcher.Matches(path)
		if methodMatches && pathMatches {
			route.Response.Write(w)
			return
		}
	}
	writeJSON(w, http.StatusNotFound, map[string]string{"error": "not_found"})
}

func RequestPath(raw string) string {
	if parsed, err := url.ParseRequestURI(raw); err == nil {
		if parsed.Path != "" {
			return parsed.Path
		}
		if parsed.IsAbs() {
			return "/"
		}
	}
	path, _, _ := strings.Cut(raw, "?")
	if strings.HasPrefix(path, "/") {
		return path
	}
	return "/" + path
}
