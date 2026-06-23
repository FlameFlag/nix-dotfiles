package raycast

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"os"

	"github.com/FlameFlag/nix-dotfiles/internal/common/process"
)

//go:embed scripts/user-defaults-bridge.cjs
var userDefaultsBridgeJS string

func (p betaPatcher) writeUserDefaults(node, key string) error {
	profile := defaultProfile
	profile.CurrentUser.Image = p.avatarURL()
	profile.CurrentUser.Avatar = p.avatarURL()
	currentUser, err := json.Marshal(profile.CurrentUser)
	if err != nil {
		return err
	}
	oauthToken, err := json.Marshal(profile.OAuthToken)
	if err != nil {
		return err
	}

	bridge, err := os.CreateTemp("", "raycast-beta-user-defaults-*.cjs")
	if err != nil {
		return fmt.Errorf("create Raycast bridge script: %w", err)
	}
	bridgePath := bridge.Name()
	defer os.Remove(bridgePath)
	if _, err := bridge.WriteString(userDefaultsBridgeJS); err != nil {
		_ = bridge.Close()
		return fmt.Errorf("write Raycast bridge script: %w", err)
	}
	if err := bridge.Close(); err != nil {
		return fmt.Errorf("close Raycast bridge script: %w", err)
	}
	return process.RunInWithEnvAndStdin(
		"",
		[]string{node, bridgePath, p.appSupport, key, betaDataNode, string(currentUser), string(oauthToken)},
		nil,
		os.Stdin,
	)
}
