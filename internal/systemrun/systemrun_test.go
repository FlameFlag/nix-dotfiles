package systemrun

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func TestCommandTimeoutDefaultsAndBounds(t *testing.T) {
	tests := []struct {
		name    string
		seconds uint64
		want    time.Duration
		wantErr bool
	}{
		{name: "default", seconds: 0, want: defaultTimeout},
		{name: "one second", seconds: 1, want: time.Second},
		{name: "above max", seconds: uint64(maxTimeout.Seconds()) + 1, wantErr: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := CommandTimeout(tt.seconds)
			if tt.wantErr {
				if err == nil {
					t.Fatal("expected error")
				}
				return
			}
			if err != nil || got != tt.want {
				t.Fatalf("timeout = %v, %v; want %v, nil", got, err, tt.want)
			}
		})
	}
}

func TestReadLimitedTruncatesAfterOutputLimit(t *testing.T) {
	got := readLimited(strings.NewReader(strings.Repeat("x", outputLimit+1)))
	if got.err != nil {
		t.Fatal(got.err)
	}
	if !got.truncated {
		t.Fatal("expected output to be truncated")
	}
	if len(got.bytes) != outputLimit {
		t.Fatalf("len(bytes) = %d, want %d", len(got.bytes), outputLimit)
	}
}

func TestMCPServerListsSystemRunTool(t *testing.T) {
	ctx := context.Background()
	serverTransport, clientTransport := mcp.NewInMemoryTransports()
	serverSession, err := newMCPServer().Connect(ctx, serverTransport, nil)
	if err != nil {
		t.Fatalf("server connect: %v", err)
	}
	defer serverSession.Close()

	client := mcp.NewClient(&mcp.Implementation{Name: "system-run-mcp-test", Version: "0.0.1"}, nil)
	clientSession, err := client.Connect(ctx, clientTransport, nil)
	if err != nil {
		t.Fatalf("client connect: %v", err)
	}
	defer clientSession.Close()

	if got := clientSession.InitializeResult().Instructions; got != Instructions {
		t.Fatalf("instructions = %q; want %q", got, Instructions)
	}
	tools, err := clientSession.ListTools(ctx, nil)
	if err != nil {
		t.Fatalf("list tools: %v", err)
	}
	if len(tools.Tools) != 1 {
		t.Fatalf("tool count = %d; want 1", len(tools.Tools))
	}
	tool := tools.Tools[0]
	if tool.Name != "system-run" {
		t.Fatalf("tool name = %q; want system-run", tool.Name)
	}
	if tool.InputSchema == nil || tool.OutputSchema == nil {
		t.Fatalf("tool schemas must be present")
	}
	if tool.Annotations == nil || tool.Annotations.DestructiveHint == nil ||
		!*tool.Annotations.DestructiveHint {
		t.Fatalf("tool destructive annotation missing")
	}
}
