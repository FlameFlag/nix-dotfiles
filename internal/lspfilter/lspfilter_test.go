package lspfilter

import (
	"bufio"
	"bytes"
	"errors"
	"io"
	"testing"

	"github.com/sourcegraph/jsonrpc2"
)

func TestClearsTemplateDiagnostics(t *testing.T) {
	output := runFilter(t, diagnosticMessage("file:///repo/config.nu.tmpl"))
	diagnostics := diagnosticsFrom(t, output[0])
	if len(diagnostics) != 0 {
		t.Fatalf("diagnostics length = %d; want 0", len(diagnostics))
	}
}

func TestKeepsRegularDiagnostics(t *testing.T) {
	output := runFilter(t, diagnosticMessage("file:///repo/config.nu"))
	diagnostics := diagnosticsFrom(t, output[0])
	if len(diagnostics) != 1 {
		t.Fatalf("diagnostics length = %d; want 1", len(diagnostics))
	}
	diagnostic, ok := diagnostics[0].(map[string]any)
	if !ok || diagnostic["message"] != "bad" {
		t.Fatalf("diagnostic = %#v; want message %q", diagnostics[0], "bad")
	}
}

func TestHandlesChunkedFrames(t *testing.T) {
	input := framedMessages(t, diagnosticMessage("file:///repo/.chezmoitemplates/x.nu"))
	var output bytes.Buffer
	if err := filterStdout(
		chunkedReader{reader: bytes.NewReader(input), size: 10},
		&output,
	); err != nil {
		t.Fatal(err)
	}
	messages := decodeMessages(t, output.Bytes())
	diagnostics := diagnosticsFrom(t, messages[0])
	if len(diagnostics) != 0 {
		t.Fatalf("diagnostics length = %d; want 0", len(diagnostics))
	}
}

func TestKeepsNonDiagnosticMessages(t *testing.T) {
	input := map[string]any{"jsonrpc": "2.0", "id": 1, "result": map[string]any{"ok": true}}
	output := runFilter(t, input)
	if output[0]["id"].(float64) != 1 {
		t.Fatalf("message id = %#v; want 1", output[0]["id"])
	}
}

func runFilter(t *testing.T, messages ...map[string]any) []map[string]any {
	t.Helper()
	input := framedMessages(t, messages...)
	var output bytes.Buffer
	if err := filterStdout(bytes.NewReader(input), &output); err != nil {
		t.Fatal(err)
	}
	return decodeMessages(t, output.Bytes())
}

func framedMessages(t *testing.T, messages ...map[string]any) []byte {
	t.Helper()
	codec := jsonrpc2.VSCodeObjectCodec{}
	var input bytes.Buffer
	for _, message := range messages {
		if err := codec.WriteObject(&input, message); err != nil {
			t.Fatal(err)
		}
	}
	return input.Bytes()
}

func decodeMessages(t *testing.T, data []byte) []map[string]any {
	t.Helper()
	codec := jsonrpc2.VSCodeObjectCodec{}
	reader := bufio.NewReader(bytes.NewReader(data))
	var messages []map[string]any
	for {
		var message map[string]any
		err := codec.ReadObject(reader, &message)
		if errors.Is(err, io.EOF) {
			return messages
		}
		if err != nil {
			t.Fatal(err)
		}
		messages = append(messages, message)
	}
}

func diagnosticMessage(uri string) map[string]any {
	return map[string]any{
		"jsonrpc": "2.0",
		"method":  "textDocument/publishDiagnostics",
		"params": map[string]any{
			"uri": uri,
			"diagnostics": []any{
				map[string]any{
					"range": map[string]any{
						"start": map[string]any{"line": 0, "character": 0},
						"end":   map[string]any{"line": 0, "character": 1},
					},
					"message": "bad",
				},
			},
		},
	}
}

func diagnosticsFrom(t *testing.T, message map[string]any) []any {
	t.Helper()
	params, ok := message["params"].(map[string]any)
	if !ok {
		t.Fatalf("params = %#v; want object", message["params"])
	}
	diagnostics, ok := params["diagnostics"].([]any)
	if !ok {
		t.Fatalf("diagnostics = %#v; want array", params["diagnostics"])
	}
	return diagnostics
}

type chunkedReader struct {
	reader io.Reader
	size   int
}

func (r chunkedReader) Read(p []byte) (int, error) {
	if len(p) > r.size {
		p = p[:r.size]
	}
	return r.reader.Read(p)
}
