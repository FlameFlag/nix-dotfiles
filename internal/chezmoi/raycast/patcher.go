package raycast

import (
	"os"
	"time"

	"github.com/FlameFlag/nix-dotfiles/internal/common/process"
	"github.com/charmbracelet/log"
)

const (
	betaApp      = "/Applications/Raycast Beta.app"
	betaBundle   = betaApp + "/Contents/Resources/macos-app_RaycastDesktopApp.bundle/Contents/Resources"
	betaDataNode = betaBundle + "/backend/data.darwin-arm64.node"

	keyCaptureRetries  = 30
	keyCaptureInterval = time.Second
)

func PatchBetaUser(appSupport string) error {
	if !pathExists(betaApp) {
		log.Warn("Raycast Beta not found; skipping Raycast Beta user patch")
		return nil
	}
	if !regularFileExists(betaDataNode) {
		log.Warn("Raycast Beta data addon not found; skipping Raycast Beta user patch", "path", betaDataNode)
		return nil
	}
	patcher := betaPatcher{appSupport: appSupport}
	return patcher.run()
}

type betaPatcher struct {
	appSupport string
}

func (p betaPatcher) run() error {
	key, node, err := p.extractKey()
	if err != nil {
		return err
	}
	if err := p.ensureAvatar(); err != nil {
		return err
	}
	if err := p.writeUserDefaults(node, key); err != nil {
		return err
	}
	log.Info("starting Raycast Beta")
	if err := openBeta(); err != nil {
		return err
	}
	log.Info("Raycast Beta started")
	return nil
}

func openBeta() error {
	return process.RunInWithEnvAndStdin("", []string{"open", betaApp}, nil, nil)
}

func waitForFile(path string, attempts int) bool {
	for range attempts {
		if regularFileExists(path) {
			return true
		}
		time.Sleep(keyCaptureInterval)
	}
	return false
}

func previewSecret(value string, prefix int) string {
	if len(value) <= prefix {
		return value
	}
	return value[:prefix] + "..."
}

func pathExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func regularFileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}
