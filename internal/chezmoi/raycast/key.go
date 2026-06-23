package raycast

import (
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/FlameFlag/nix-dotfiles/internal/common/fileutil"
	"github.com/FlameFlag/nix-dotfiles/internal/common/process"
	"github.com/buildkite/shellwords"
	"github.com/charmbracelet/log"
)

//go:embed scripts/keydump-hook.cjs
var keyDumpHookTemplate string

//go:embed scripts/node-wrapper.sh
var nodeWrapperTemplate string

func (p betaPatcher) extractKey() (string, string, error) {
	nodeDir, err := p.raycastNodeDir()
	if err != nil {
		return "", "", err
	}
	paths := nodeHookPaths{
		hookFile: filepath.Join(nodeDir, ".keydump.cjs"),
		keyFile:  filepath.Join(nodeDir, ".raycast-key-cache"),
		nodePath: filepath.Join(nodeDir, "node"),
		nodeReal: filepath.Join(nodeDir, "node.real"),
	}

	if regularFileExists(paths.nodeReal) {
		if err := restoreOriginalNode(paths); err != nil {
			return "", "", err
		}
	}
	if key, ok, err := readKey(paths.keyFile); err != nil || ok {
		return key, paths.nodePath, err
	}

	if err := installKeyCaptureHook(paths); err != nil {
		return "", "", err
	}
	defer func() {
		if err := restoreOriginalNode(paths); err != nil {
			log.Warn("failed to restore Raycast node", "error", err)
		}
	}()

	log.Info("extracting Raycast DB key")
	if err := openBeta(); err != nil {
		return "", "", err
	}
	captured := waitForFile(paths.keyFile, keyCaptureRetries)
	_, _ = process.CaptureWithEnvAndStdin([]string{"killall", "Raycast Beta"}, nil, nil)
	time.Sleep(2 * time.Second)
	if !captured {
		return "", "", fmt.Errorf("failed to capture Raycast DB key; Raycast may not have started")
	}
	key, ok, err := readKey(paths.keyFile)
	if err != nil {
		return "", "", err
	}
	if !ok {
		return "", "", fmt.Errorf("captured Raycast DB key disappeared: %s", paths.keyFile)
	}
	log.Info("Raycast DB key extracted", "key", previewSecret(key, 16), "length", len(key))
	return key, paths.nodePath, nil
}

func (p betaPatcher) raycastNodeDir() (string, error) {
	runtimeRoot := filepath.Join(p.appSupport, "node/runtime")
	entries, err := os.ReadDir(runtimeRoot)
	if err != nil {
		return "", fmt.Errorf("raycast node runtime not found: %w", err)
	}
	var candidates []string
	for _, entry := range entries {
		if !entry.IsDir() || !strings.HasPrefix(entry.Name(), "node-v") {
			continue
		}
		nodeDir := filepath.Join(runtimeRoot, entry.Name(), "bin")
		if regularFileExists(filepath.Join(nodeDir, "node")) || regularFileExists(filepath.Join(nodeDir, "node.real")) {
			candidates = append(candidates, nodeDir)
		}
	}
	slices.Sort(candidates)
	if len(candidates) == 0 {
		return "", fmt.Errorf("raycast node runtime not found under %s", runtimeRoot)
	}
	return candidates[len(candidates)-1], nil
}

type nodeHookPaths struct {
	hookFile string
	keyFile  string
	nodePath string
	nodeReal string
}

func installKeyCaptureHook(paths nodeHookPaths) error {
	if _, err := fileutil.WriteTextIfChanged(paths.hookFile, keyDumpHookSource(paths.keyFile)); err != nil {
		return fmt.Errorf("write Raycast key hook: %w", err)
	}
	if err := os.Rename(paths.nodePath, paths.nodeReal); err != nil {
		_ = os.Remove(paths.hookFile)
		return fmt.Errorf("move Raycast node aside: %w", err)
	}
	wrapper := renderNodeWrapper(paths)
	if err := fileutil.WriteExecutable(paths.nodePath, []byte(wrapper)); err != nil {
		_ = os.Rename(paths.nodeReal, paths.nodePath)
		_ = os.Remove(paths.hookFile)
		return fmt.Errorf("write Raycast node wrapper: %w", err)
	}
	return nil
}

func restoreOriginalNode(paths nodeHookPaths) error {
	if !regularFileExists(paths.nodeReal) {
		return nil
	}
	if err := os.Remove(paths.nodePath); err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("remove Raycast node wrapper: %w", err)
	}
	if err := os.Rename(paths.nodeReal, paths.nodePath); err != nil {
		return fmt.Errorf("restore Raycast node: %w", err)
	}
	if err := os.Remove(paths.hookFile); err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("remove Raycast key hook: %w", err)
	}
	return nil
}

func keyDumpHookSource(keyFile string) string {
	keyFileJSON, _ := json.Marshal(keyFile)
	return strings.ReplaceAll(keyDumpHookTemplate, "__KEY_FILE_JSON__", string(keyFileJSON))
}

func renderNodeWrapper(paths nodeHookPaths) string {
	wrapper := strings.ReplaceAll(
		nodeWrapperTemplate,
		"__NODE_REAL__",
		shellwords.QuotePosix(paths.nodeReal),
	)
	return strings.ReplaceAll(wrapper, "__HOOK_FILE__", shellwords.QuotePosix(paths.hookFile))
}

func readKey(path string) (string, bool, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return "", false, nil
	}
	if err != nil {
		return "", false, fmt.Errorf("read Raycast DB key cache: %w", err)
	}
	key := strings.TrimSpace(string(data))
	if key == "" {
		return "", false, fmt.Errorf("raycast DB key cache is empty: %s", path)
	}
	return key, true, nil
}
