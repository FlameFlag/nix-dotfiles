package systemrun

import (
	"context"
	"encoding/json"
	"errors"
	"io"

	"github.com/modelcontextprotocol/go-sdk/jsonrpc"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

const Instructions = "system-run executes shell commands through sudo -n system-runner. Command exit failures are returned as structured output with success=false, exit_status, stdout, and stderr; only invalid input or runner setup failures are JSON-RPC errors."

type nopWriteCloser struct {
	io.Writer
}

func (nopWriteCloser) Close() error { return nil }

func ServeMCP(ctx context.Context, input io.Reader, output io.Writer) error {
	server := newMCPServer()
	return server.Run(ctx, &mcp.IOTransport{
		Reader: io.NopCloser(input),
		Writer: nopWriteCloser{Writer: output},
	})
}

func newMCPServer() *mcp.Server {
	server := mcp.NewServer(
		&mcp.Implementation{Name: "system-run-mcp", Version: "0.0.1"},
		&mcp.ServerOptions{
			Instructions: Instructions,
			Capabilities: &mcp.ServerCapabilities{
				Tools: &mcp.ToolCapabilities{},
			},
		},
	)

	truthy := true
	server.AddTool(&mcp.Tool{
		Name:         "system-run",
		Title:        "System Run",
		Description:  "Run an arbitrary shell command through the local system command runner.",
		InputSchema:  systemRunInputSchema(),
		OutputSchema: systemRunOutputSchema(),
		Annotations: &mcp.ToolAnnotations{
			Title:           "System Run",
			ReadOnlyHint:    false,
			DestructiveHint: &truthy,
			IdempotentHint:  false,
			OpenWorldHint:   &truthy,
		},
	}, systemRunTool)

	return server
}

func systemRunTool(ctx context.Context, req *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	if req.Params == nil {
		return nil, rpcError(jsonrpc.CodeInvalidParams, errors.New("missing params"))
	}
	params, err := DecodeParams(req.Params.Arguments)
	if err != nil {
		return nil, rpcError(jsonrpc.CodeInvalidParams, err)
	}
	output, err := RunSystemCommand(ctx, params)
	if err != nil {
		if _, ok := errors.AsType[invalidParams](err); ok {
			return nil, rpcError(jsonrpc.CodeInvalidParams, err)
		}
		return nil, rpcError(jsonrpc.CodeInternalError, err)
	}
	text, err := json.Marshal(output)
	if err != nil {
		return nil, rpcError(jsonrpc.CodeInternalError, err)
	}
	return &mcp.CallToolResult{
		Content: []mcp.Content{
			&mcp.TextContent{Text: string(text)},
		},
		StructuredContent: output,
	}, nil
}

func rpcError(code int64, err error) error {
	return &jsonrpc.Error{Code: code, Message: err.Error()}
}

func systemRunInputSchema() map[string]any {
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"command": map[string]any{
				"type":        "string",
				"description": "Shell command to execute through the system runner.",
			},
			"cwd": map[string]any{
				"type":        "string",
				"description": "Optional working directory for the command.",
			},
			"timeout_sec": map[string]any{
				"type":        "integer",
				"description": "Optional timeout in seconds. Defaults to 300; maximum is 1800.",
			},
		},
		"required":             []string{"command"},
		"additionalProperties": false,
	}
}

func systemRunOutputSchema() map[string]any {
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"exit_status":      map[string]any{"type": "string"},
			"success":          map[string]any{"type": "boolean"},
			"timed_out":        map[string]any{"type": "boolean"},
			"stdout":           map[string]any{"type": "string"},
			"stderr":           map[string]any{"type": "string"},
			"stdout_truncated": map[string]any{"type": "boolean"},
			"stderr_truncated": map[string]any{"type": "boolean"},
		},
		"required": []string{
			"exit_status",
			"success",
			"timed_out",
			"stdout",
			"stderr",
			"stdout_truncated",
			"stderr_truncated",
		},
	}
}
