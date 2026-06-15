package chezmoi

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/buildkite/shellwords"
	"github.com/charmbracelet/log"
	"github.com/euvlok/nix-dotfiles/internal/common/fileutil"
	"github.com/euvlok/nix-dotfiles/internal/common/httpx"
	"github.com/euvlok/nix-dotfiles/internal/common/process"
)

const (
	raycastBetaApp      = "/Applications/Raycast Beta.app"
	raycastBetaBundle   = raycastBetaApp + "/Contents/Resources/macos-app_RaycastDesktopApp.bundle/Contents/Resources"
	raycastBetaDataNode = raycastBetaBundle + "/backend/data.darwin-arm64.node"

	raycastKeyCaptureRetries  = 30
	raycastKeyCaptureInterval = time.Second
	raycastDefaultAvatarURL   = "https://cdn.donmai.us/original/af/7d/__mori_calliope_hololive_and_1_more_drawn_by_adammaarr__af7da65013b64818bf2fcf573aeb67ea.png"
	raycastAvatarSourceEnv    = "RAYCAST_AVATAR_SRC"
)

var raycastUserDefaultsBridgeJS = strings.TrimPrefix(`
async function main() {
	const [
		appSupport,
		key,
		nativeAddon,
		currentUser,
		oauthToken,
	] = process.argv.slice(2);

	const raycastData = require(nativeAddon);
	const db = new raycastData.DatabaseClient(appSupport, key, () => {});

	if (!db.initReport || !db.initReport.overallSuccess) {
		throw new Error("failed to open Raycast database with extracted key");
	}

	await db.userDefaults.set("CurrentUser", currentUser);
	await db.userDefaults.set("OAuthTokenResponse", oauthToken);

	const stored = JSON.parse(await db.userDefaults.get("CurrentUser"));
	const summary = [
		"OK - " + stored.name,
		"pro:" + stored.has_pro_features,
		"sub:" + stored.subscription?.status,
	].join(" | ");

	console.log(summary);
}

main().catch((error) => {
	console.error(error);
	process.exit(1);
});
`, "\n")

func PatchRaycastBetaUser(options Options) error {
	if OSWithOptions(options) != Darwin {
		return nil
	}
	if !pathExists(raycastBetaApp) {
		log.Warn("Raycast Beta not found; skipping Raycast Beta user patch")
		return nil
	}
	if !regularFileExists(raycastBetaDataNode) {
		log.Warn("Raycast Beta data addon not found; skipping Raycast Beta user patch", "path", raycastBetaDataNode)
		return nil
	}
	ctx, err := ContextWithOptions(options)
	if err != nil {
		return err
	}
	patcher := raycastBetaPatcher{
		appSupport: filepath.Join(ctx.HomeDir, "Library/Application Support/com.raycast-x.macos"),
	}
	return patcher.run()
}

type raycastBetaPatcher struct {
	appSupport string
}

func (p raycastBetaPatcher) run() error {
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
	fmt.Println("Starting Raycast Beta...")
	if err := openRaycastBeta(); err != nil {
		return err
	}
	fmt.Println("Done. Raycast Beta started.")
	return nil
}

func (p raycastBetaPatcher) extractKey() (string, string, error) {
	nodeDir, err := p.raycastNodeDir()
	if err != nil {
		return "", "", err
	}
	paths := raycastNodeHookPaths{
		hookFile: filepath.Join(nodeDir, ".keydump.cjs"),
		keyFile:  filepath.Join(nodeDir, ".raycast-key-cache"),
		nodePath: filepath.Join(nodeDir, "node"),
		nodeReal: filepath.Join(nodeDir, "node.real"),
	}

	if regularFileExists(paths.nodeReal) {
		if err := restoreOriginalRaycastNode(paths); err != nil {
			return "", "", err
		}
	}
	if key, ok, err := readRaycastKey(paths.keyFile); err != nil || ok {
		return key, paths.nodePath, err
	}

	if err := installRaycastKeyCaptureHook(paths); err != nil {
		return "", "", err
	}
	defer func() {
		if err := restoreOriginalRaycastNode(paths); err != nil {
			log.Warn("failed to restore Raycast node", "error", err)
		}
	}()

	fmt.Println("Extracting DB key (launching Raycast briefly)...")
	if err := openRaycastBeta(); err != nil {
		return "", "", err
	}
	captured := waitForFile(paths.keyFile, raycastKeyCaptureRetries)
	_, _ = process.CaptureWithEnvAndStdin([]string{"killall", "Raycast Beta"}, nil, nil)
	time.Sleep(2 * time.Second)
	if !captured {
		return "", "", fmt.Errorf("failed to capture Raycast DB key; Raycast may not have started")
	}
	key, ok, err := readRaycastKey(paths.keyFile)
	if err != nil {
		return "", "", err
	}
	if !ok {
		return "", "", fmt.Errorf("captured Raycast DB key disappeared: %s", paths.keyFile)
	}
	fmt.Printf("Key extracted: %s (%d chars)\n", previewSecret(key, 16), len(key))
	return key, paths.nodePath, nil
}

func (p raycastBetaPatcher) raycastNodeDir() (string, error) {
	runtimeRoot := filepath.Join(p.appSupport, "node/runtime")
	entries, err := os.ReadDir(runtimeRoot)
	if err != nil {
		return "", fmt.Errorf("Raycast node runtime not found: %w", err)
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
		return "", fmt.Errorf("Raycast node runtime not found under %s", runtimeRoot)
	}
	return candidates[len(candidates)-1], nil
}

type raycastNodeHookPaths struct {
	hookFile string
	keyFile  string
	nodePath string
	nodeReal string
}

func installRaycastKeyCaptureHook(paths raycastNodeHookPaths) error {
	if _, err := fileutil.WriteTextIfChanged(paths.hookFile, raycastKeyDumpHookSource(paths.keyFile)); err != nil {
		return fmt.Errorf("write Raycast key hook: %w", err)
	}
	if err := os.Rename(paths.nodePath, paths.nodeReal); err != nil {
		_ = os.Remove(paths.hookFile)
		return fmt.Errorf("move Raycast node aside: %w", err)
	}
	wrapper := fmt.Sprintf(
		"#!/bin/bash\nexec %s --require %s \"$@\"\n",
		shellwords.QuotePosix(paths.nodeReal),
		shellwords.QuotePosix(paths.hookFile),
	)
	if err := fileutil.WriteExecutable(paths.nodePath, []byte(wrapper)); err != nil {
		_ = os.Rename(paths.nodeReal, paths.nodePath)
		_ = os.Remove(paths.hookFile)
		return fmt.Errorf("write Raycast node wrapper: %w", err)
	}
	return nil
}

func restoreOriginalRaycastNode(paths raycastNodeHookPaths) error {
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

func raycastKeyDumpHookSource(keyFile string) string {
	keyFileJSON, _ := json.Marshal(keyFile)
	return fmt.Sprintf(strings.TrimPrefix(`
const Module = require("module");
const originalRequire = Module.prototype.require;

Module.prototype.require = function requireWithKeyDump(id) {
	const result = originalRequire.apply(this, arguments);

	if (id && id.includes("data.darwin-arm64") && result.DatabaseClient) {
		const OriginalDatabaseClient = result.DatabaseClient;

		result.DatabaseClient = class DatabaseClientWithKeyDump extends OriginalDatabaseClient {
			constructor(...args) {
				require("fs").writeFileSync(%s, args[1]);
				super(...args);
			}
		};
	}

	return result;
};
`, "\n"), keyFileJSON)
}

func (p raycastBetaPatcher) writeUserDefaults(node, key string) error {
	currentUser, err := json.Marshal(raycastCurrentUser{
		ID:                   "e0vi",
		Name:                 "Evie",
		Username:             "e0vi",
		Handle:               "e0vi",
		Email:                "raycast@ps1.sh",
		Image:                p.avatarURL(),
		Avatar:               p.avatarURL(),
		Organizations:        []string{},
		HasProFeatures:       true,
		CanApplyForFreeTrial: false,
		Subscription:         raycastSubscription{ID: "eu0vi", Status: "active", PlanName: "Pro", BillingCycle: "yearly", RenewalDate: "2099-12-31T23:59:59Z"},
	})
	if err != nil {
		return err
	}
	oauthToken, err := json.Marshal(raycastOAuthToken{
		AccessToken:  "dHJhbnMgcmlnaHRzIGFyZSBodW1hbiByaWdodHM",
		RefreshToken: "dHJhbnMgd29tZW4gYXJlIHdvbWVu",
		TokenType:    "Bearer",
		ExpiresIn:    999999999,
		Scope:        "read write",
	})
	if err != nil {
		return err
	}

	bridge, err := os.CreateTemp("", "raycast-beta-user-defaults-*.cjs")
	if err != nil {
		return fmt.Errorf("create Raycast bridge script: %w", err)
	}
	bridgePath := bridge.Name()
	defer os.Remove(bridgePath)
	if _, err := bridge.WriteString(raycastUserDefaultsBridgeJS); err != nil {
		_ = bridge.Close()
		return fmt.Errorf("write Raycast bridge script: %w", err)
	}
	if err := bridge.Close(); err != nil {
		return fmt.Errorf("close Raycast bridge script: %w", err)
	}
	return process.RunInWithEnvAndStdin(
		"",
		[]string{node, bridgePath, p.appSupport, key, raycastBetaDataNode, string(currentUser), string(oauthToken)},
		nil,
		os.Stdin,
	)
}

type raycastCurrentUser struct {
	ID                   string              `json:"id"`
	Name                 string              `json:"name"`
	Username             string              `json:"username"`
	Handle               string              `json:"handle"`
	Email                string              `json:"email"`
	Image                string              `json:"image"`
	Avatar               string              `json:"avatar"`
	Organizations        []string            `json:"organizations"`
	HasProFeatures       bool                `json:"has_pro_features"`
	CanApplyForFreeTrial bool                `json:"can_apply_for_free_trial"`
	Subscription         raycastSubscription `json:"subscription"`
}

type raycastSubscription struct {
	ID           string `json:"id"`
	Status       string `json:"status"`
	PlanName     string `json:"plan_name"`
	BillingCycle string `json:"billing_cycle"`
	RenewalDate  string `json:"renewal_date"`
}

type raycastOAuthToken struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	TokenType    string `json:"token_type"`
	ExpiresIn    int    `json:"expires_in"`
	Scope        string `json:"scope"`
}

func (p raycastBetaPatcher) ensureAvatar() error {
	avatarPath := p.avatarPath()
	if info, err := os.Stat(avatarPath); err == nil && !info.IsDir() {
		fmt.Printf("Avatar exists (%d bytes)\n", info.Size())
		return nil
	}
	if err := os.MkdirAll(p.appSupport, 0o755); err != nil {
		return fmt.Errorf("create Raycast app support directory: %w", err)
	}
	if source := os.Getenv(raycastAvatarSourceEnv); source != "" && regularFileExists(source) {
		if ok := resizeRaycastAvatar(source, avatarPath); ok {
			fmt.Println("Avatar resized from:", source)
			return nil
		}
	}
	temp, err := os.CreateTemp("", "raycast-beta-avatar-source-*.png")
	if err != nil {
		return fmt.Errorf("create temporary Raycast avatar path: %w", err)
	}
	tempPath := temp.Name()
	defer os.Remove(tempPath)
	if err := temp.Close(); err != nil {
		return fmt.Errorf("close temporary Raycast avatar: %w", err)
	}
	if err := (&httpx.Client{UserAgent: "nix-dotfiles-chezmoi-support"}).DownloadFile(raycastDefaultAvatarURL, tempPath); err != nil {
		log.Warn("failed to download Raycast avatar; continuing without avatar refresh", "error", err)
		return nil
	}
	if ok := resizeRaycastAvatar(tempPath, avatarPath); ok {
		fmt.Println("Avatar downloaded and resized from:", raycastDefaultAvatarURL)
	}
	return nil
}

func (p raycastBetaPatcher) avatarPath() string {
	return filepath.Join(p.appSupport, "avatar.png")
}

func (p raycastBetaPatcher) avatarURL() string {
	return (&url.URL{Scheme: "file", Path: p.avatarPath()}).String()
}

func resizeRaycastAvatar(source, destination string) bool {
	cmd := exec.Command("sips", "-Z", "256", source, "--out", destination)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run() == nil
}

func readRaycastKey(path string) (string, bool, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return "", false, nil
	}
	if err != nil {
		return "", false, fmt.Errorf("read Raycast DB key cache: %w", err)
	}
	key := strings.TrimSpace(string(data))
	if key == "" {
		return "", false, fmt.Errorf("Raycast DB key cache is empty: %s", path)
	}
	return key, true, nil
}

func openRaycastBeta() error {
	return process.RunInWithEnvAndStdin("", []string{"open", raycastBetaApp}, nil, nil)
}

func waitForFile(path string, attempts int) bool {
	for range attempts {
		if regularFileExists(path) {
			return true
		}
		time.Sleep(raycastKeyCaptureInterval)
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
