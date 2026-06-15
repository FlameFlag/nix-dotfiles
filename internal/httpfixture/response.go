package httpfixture

import (
	"encoding/json"
	"net/http"
)

type bodyWriter struct {
	contentType string
	bytes       func(Body) ([]byte, error)
}

var bodyWriters = map[string]bodyWriter{
	"text": {
		contentType: "text/plain; charset=utf-8",
		bytes:       func(body Body) ([]byte, error) { return []byte(body.Text), nil },
	},
	"html": {
		contentType: "text/html; charset=utf-8",
		bytes:       func(body Body) ([]byte, error) { return []byte(body.Text), nil },
	},
	"json": {
		contentType: "application/json",
		bytes: func(body Body) ([]byte, error) {
			return json.Marshal(body.Value)
		},
	},
}

func (r FixtureResponse) Write(w http.ResponseWriter) {
	for name, value := range r.Headers {
		w.Header().Set(name, value)
	}
	body := []byte(nil)
	contentType := r.ContentType
	if writer, ok := bodyWriters[r.Body.Kind]; ok {
		payload, err := writer.bytes(r.Body)
		if err != nil {
			writeJSON(
				w,
				http.StatusInternalServerError,
				map[string]string{"error": "internal_error"},
			)
			return
		}
		body = payload
		if contentType == "" {
			contentType = writer.contentType
		}
	}
	if contentType != "" {
		w.Header().Set("Content-Type", contentType)
	}
	w.WriteHeader(r.Status)
	_, _ = w.Write(body)
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}
