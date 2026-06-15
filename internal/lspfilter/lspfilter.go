package lspfilter

import (
	"bufio"
	"errors"
	"io"
	"os"
	"os/exec"
	"strings"

	"github.com/sourcegraph/jsonrpc2"
)

const templateDirectoryPattern = "/.chezmoitemplates/"

func ProxyLSPCommand(program string, args []string) (int, error) {
	cmd := exec.Command(program, args...)
	cmd.Stdin = os.Stdin
	cmd.Stderr = os.Stderr
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return 1, err
	}
	if err := cmd.Start(); err != nil {
		return 1, err
	}

	filterErr := filterStdout(stdout, os.Stdout)
	waitErr := cmd.Wait()
	if filterErr != nil {
		return 1, filterErr
	}
	if waitErr != nil {
		if exitErr, ok := errors.AsType[*exec.ExitError](waitErr); ok {
			return exitErr.ExitCode(), nil
		}
		return 1, waitErr
	}
	return 0, nil
}

func filterStdout(stdout io.Reader, output io.Writer) error {
	codec := jsonrpc2.VSCodeObjectCodec{}
	reader := bufio.NewReader(stdout)
	for {
		var message map[string]any
		err := codec.ReadObject(reader, &message)
		if errors.Is(err, io.EOF) {
			return nil
		}
		if err != nil {
			return err
		}
		if message["method"] == "textDocument/publishDiagnostics" {
			if params, ok := message["params"].(map[string]any); ok {
				if uri, ok := params["uri"].(string); ok && isTemplateURI(uri) {
					params["diagnostics"] = []any{}
				}
			}
		}
		if err := codec.WriteObject(output, message); err != nil {
			return err
		}
	}
}

func isTemplateURI(uri string) bool {
	return strings.HasSuffix(uri, ".tmpl") || strings.Contains(uri, templateDirectoryPattern)
}
