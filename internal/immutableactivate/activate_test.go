package immutableactivate

import (
	"bytes"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/FlameFlag/nix-dotfiles/internal/common/process"
	activationcontainer "github.com/FlameFlag/nix-dotfiles/internal/immutableactivate/container"
	activationflake "github.com/FlameFlag/nix-dotfiles/internal/immutableactivate/flake"
	"github.com/FlameFlag/nix-dotfiles/internal/immutableactivate/updater"
	"github.com/buildkite/shellwords"
)

func TestHostActivationWritesManagedWrappers(t *testing.T) {
	root := t.TempDir()
	flake := filepath.Join(root, "flake")
	home := filepath.Join(root, "home")
	dataHome := filepath.Join(root, "data")
	binHome := filepath.Join(root, "bin")
	pathBin := filepath.Join(root, "path-bin")
	mustMkdir(t, flake)
	mustWrite(t, filepath.Join(flake, "flake.nix"), "", 0o644)
	mustWrite(t, filepath.Join(flake, "ansible/playbooks/userland.yml"), "", 0o644)
	mustMkdir(t, home)
	mustMkdir(t, binHome)
	mustWrite(t, filepath.Join(pathBin, "nix"), "#!/bin/sh\n", 0o755)
	t.Setenv("PATH", pathBin)
	mustWrite(t, filepath.Join(binHome, "stale"), "#!/bin/sh\n"+Marker+"\n", 0o755)
	mustWrite(t, filepath.Join(binHome, "keep"), "#!/bin/sh\nexit 0\n", 0o755)
	normalizedFlake, err := activationflake.Normalize(flake)
	if err != nil {
		t.Fatal(err)
	}

	executor := &fakeExecutor{onRun: func(command Command) error {
		if len(command.Argv) >= 2 && slices.Equal(command.Argv[:2], []string{"nix", "build"}) {
			profile := command.Argv[slices.Index(command.Argv, "--profile")+1]
			mustWrite(t, filepath.Join(profile, "bin", "hello"), "#!/bin/sh\n", 0o755)
			mustWrite(t, filepath.Join(profile, "bin", "name'withquote"), "#!/bin/sh\n", 0o755)
		}
		return nil
	}}

	var stdout, stderr bytes.Buffer
	err = Run(Options{
		Flake:           flake,
		Backend:         "host",
		HomeDir:         home,
		DataHome:        dataHome,
		BinHome:         binHome,
		OperatingSystem: "linux",
		Executor:        executor,
		CommandExists:   commandExistsWith("nix"),
		Stdout:          &stdout,
		Stderr:          &stderr,
	})
	if err != nil {
		t.Fatal(err)
	}

	hello := readText(t, filepath.Join(binHome, "hello"))
	helloTarget := filepath.Join(dataHome, "nix-dotfiles/immutable/profile/bin/hello")
	if !strings.Contains(hello, Marker) || !strings.Contains(hello, "exec "+helloTarget+" \"$@\"") {
		t.Fatalf("hello wrapper = %q", hello)
	}
	quoted := readText(t, filepath.Join(binHome, "name'withquote"))
	quotedTarget := filepath.Join(dataHome, "nix-dotfiles/immutable/profile/bin/name'withquote")
	if !strings.Contains(quoted, "exec "+shellwords.QuotePosix(quotedTarget)+" \"$@\"") {
		t.Fatalf("quoted wrapper did not escape single quote: %q", quoted)
	}
	if _, err := os.Stat(filepath.Join(binHome, "stale")); !os.IsNotExist(err) {
		t.Fatalf("stale wrapper stat err = %v; want not exist", err)
	}
	if got := readText(t, filepath.Join(binHome, "keep")); got != "#!/bin/sh\nexit 0\n" {
		t.Fatalf("non-managed wrapper changed: %q", got)
	}
	if !containsArgv(
		executor.commands,
		[]string{
			"ansible-playbook",
			"-i",
			filepath.Join(normalizedFlake, "ansible/inventory/localhost.yml"),
			filepath.Join(normalizedFlake, "ansible/playbooks/userland.yml"),
		},
	) {
		t.Fatalf("ansible-playbook command not run: %#v", executor.commands)
	}
	if !strings.Contains(stdout.String(), "wrappers managed") {
		t.Fatalf("stdout = %q", stdout.String())
	}
}

func TestContainerActivationSequencesDistroboxCommands(t *testing.T) {
	root := t.TempDir()
	flake := filepath.Join(root, "flake")
	home := filepath.Join(root, "home")
	manifest := filepath.Join(root, "distrobox.ini")
	mustMkdir(t, flake)
	mustMkdir(t, home)
	mustWrite(t, filepath.Join(flake, "flake.nix"), "", 0o644)
	mustWrite(t, manifest, "[fedora-nix]\nimage=fedora:latest\n", 0o644)
	normalizedFlake, err := activationflake.Normalize(flake)
	if err != nil {
		t.Fatal(err)
	}
	executor := &fakeExecutor{}

	err = Run(Options{
		Flake:             flake,
		Backend:           "container",
		ResetContainers:   true,
		Update:            true,
		SkipAnsible:       true,
		HomeDir:           home,
		WorkDir:           root,
		DistroboxManifest: manifest,
		OperatingSystem:   "linux",
		Executor:          executor,
		CommandExists:     commandExistsWith(),
		Stdout:            &bytes.Buffer{},
		Stderr:            &bytes.Buffer{},
	})
	if err != nil {
		t.Fatal(err)
	}

	wantPrefixes := [][]string{
		{"distrobox", "assemble", "rm", "--file", manifest, "--name", nixContainerName},
		{"distrobox", "rm", "--force", legacyNixContainerName},
		{"distrobox", "assemble", "create", "--file", manifest, "--name", nixContainerName},
		{
			"distrobox",
			"enter",
			"--name",
			nixContainerName,
			"--",
			"env",
			"PATH=" + activationcontainer.NixPath(home),
			"nix",
			"--version",
		},
	}
	for i, want := range wantPrefixes {
		if !slices.Equal(executor.commands[i].Argv, want) {
			t.Fatalf("command %d = %#v; want %#v", i, executor.commands[i].Argv, want)
		}
	}
	updateCommand := []string{
		"distrobox",
		"enter",
		"--name",
		nixContainerName,
		"--",
		"env",
		"PATH=" + activationcontainer.NixPath(home),
		"nix",
		"--extra-experimental-features",
		"nix-command flakes",
		"flake",
		"update",
		"--flake",
		normalizedFlake,
	}
	if !containsArgv(executor.commands, updateCommand) {
		t.Fatalf("nix update command missing: %#v", executor.commands)
	}
	profileAddCommand := []string{
		"distrobox",
		"enter",
		"--name",
		nixContainerName,
		"--",
		"env",
		"PATH=" + activationcontainer.NixPath(home),
		"nix",
		"--extra-experimental-features",
		"nix-command flakes",
		"profile",
		"install",
		"path:" + normalizedFlake + "#immutable-profile",
	}
	if !containsArgv(executor.commands, profileAddCommand) {
		t.Fatalf("container profile install command missing: %#v", executor.commands)
	}
	exportCommand := executor.commands[len(executor.commands)-1]
	if !strings.Contains(exportCommand.Stdin, "distrobox-export --bin") {
		t.Fatalf("export stdin = %q", exportCommand.Stdin)
	}
	if !slices.Contains(exportCommand.Argv, "bash") {
		t.Fatalf("export command should run script with bash: %#v", exportCommand.Argv)
	}
	if !slices.Contains(
		exportCommand.Argv,
		"NIX_DOTFILES_EXPORT_DIR="+filepath.Join(home, ".local/share/nix-dotfiles/immutable/bin"),
	) {
		t.Fatalf("export env missing from argv: %#v", exportCommand.Argv)
	}
}

func TestSkipAnsibleBypassesBootstrapPreflight(t *testing.T) {
	root := t.TempDir()
	flake := filepath.Join(root, "flake")
	home := filepath.Join(root, "home")
	dataHome := filepath.Join(root, "data")
	binHome := filepath.Join(root, "bin")
	pathBin := filepath.Join(root, "path-bin")
	mustMkdir(t, flake)
	mustMkdir(t, home)
	mustMkdir(t, binHome)
	mustWrite(t, filepath.Join(flake, "flake.nix"), "", 0o644)
	mustWrite(t, filepath.Join(flake, "ansible/playbooks/userland.yml"), "", 0o644)
	mustWrite(t, filepath.Join(pathBin, "nix"), "#!/bin/sh\n", 0o755)
	t.Setenv("PATH", pathBin)
	executor := &fakeExecutor{onRun: func(command Command) error {
		if len(command.Argv) >= 2 && slices.Equal(command.Argv[:2], []string{"nix", "build"}) {
			profile := command.Argv[slices.Index(command.Argv, "--profile")+1]
			mustWrite(t, filepath.Join(profile, "bin", "hello"), "#!/bin/sh\n", 0o755)
		}
		return nil
	}}

	err := Run(Options{
		Flake:           flake,
		Backend:         "host",
		SkipAnsible:     true,
		HomeDir:         home,
		DataHome:        dataHome,
		BinHome:         binHome,
		OperatingSystem: "linux",
		Executor:        executor,
		CommandExists: func(name string) bool {
			return name == "nix"
		},
		Stdout: &bytes.Buffer{},
		Stderr: &bytes.Buffer{},
	})
	if err != nil {
		t.Fatal(err)
	}
	if containsArgvPrefix(executor.commands, []string{"ansible-playbook"}) {
		t.Fatalf("ansible-playbook command ran with SkipAnsible: %#v", executor.commands)
	}
}

func TestAutoBackendUsesHostWhenNixExists(t *testing.T) {
	root := t.TempDir()
	bin := filepath.Join(root, "bin")
	flake := filepath.Join(root, "flake")
	home := filepath.Join(root, "home")
	dataHome := filepath.Join(root, "data")
	binHome := filepath.Join(root, "home-bin")
	mustWrite(t, filepath.Join(bin, "nix"), "#!/bin/sh\n", 0o755)
	mustMkdir(t, flake)
	mustMkdir(t, home)
	mustWrite(t, filepath.Join(flake, "flake.nix"), "", 0o644)
	mustWrite(t, filepath.Join(flake, "ansible/playbooks/userland.yml"), "", 0o644)
	t.Setenv("PATH", bin)
	normalizedFlake, err := activationflake.Normalize(flake)
	if err != nil {
		t.Fatal(err)
	}
	executor := &fakeExecutor{onRun: func(command Command) error {
		if len(command.Argv) >= 2 && slices.Equal(command.Argv[:2], []string{"nix", "build"}) {
			profile := command.Argv[slices.Index(command.Argv, "--profile")+1]
			mustWrite(t, filepath.Join(profile, "bin", "hello"), "#!/bin/sh\n", 0o755)
		}
		return nil
	}}

	err = Run(Options{
		Flake:           flake,
		Backend:         "auto",
		SkipAnsible:     true,
		HomeDir:         home,
		DataHome:        dataHome,
		BinHome:         binHome,
		WorkDir:         root,
		OperatingSystem: "linux",
		Executor:        executor,
		CommandExists:   commandExistsWith("nix"),
		Stdout:          &bytes.Buffer{},
		Stderr:          &bytes.Buffer{},
	})
	if err != nil {
		t.Fatal(err)
	}
	if !containsArgv(executor.commands, []string{
		"nix",
		"build",
		"--profile",
		filepath.Join(dataHome, "nix-dotfiles/immutable/profile"),
		normalizedFlake + "#immutable-profile",
	}) {
		t.Fatalf("host profile build missing: %#v", executor.commands)
	}
}

func TestDetectHostUpdaterFromOSRelease(t *testing.T) {
	root := t.TempDir()
	osRelease := filepath.Join(root, "os-release")
	mustWrite(t, osRelease, "ID=ublue\nID_LIKE=\"fedora rhel\"\n", 0o644)
	app, err := newApp(Options{
		HomeDir:           root,
		WorkDir:           root,
		OSReleasePath:     osRelease,
		OstreeBootedPath:  filepath.Join(root, "not-ostree"),
		OperatingSystem:   "linux",
		Executor:          &fakeExecutor{},
		Stdout:            &bytes.Buffer{},
		Stderr:            &bytes.Buffer{},
		DistroboxManifest: filepath.Join(root, "missing"),
	})
	if err != nil {
		t.Fatal(err)
	}
	got, err := updater.Detect(app.options, "auto")
	if err != nil {
		t.Fatal(err)
	}
	if got != "dnf" {
		t.Fatalf("updater = %q; want dnf", got)
	}
}

type fakeExecutor struct {
	commands  []Command
	onRun     func(Command) error
	onCapture func(Command) (process.Output, error)
}

func (f *fakeExecutor) Run(command Command) error {
	command.Argv = slices.Clone(command.Argv)
	command.Env = slices.Clone(command.Env)
	f.commands = append(f.commands, command)
	if f.onRun != nil {
		return f.onRun(command)
	}
	return nil
}

func (f *fakeExecutor) Capture(command Command) (process.Output, error) {
	command.Argv = slices.Clone(command.Argv)
	command.Env = slices.Clone(command.Env)
	f.commands = append(f.commands, command)
	if f.onCapture != nil {
		return f.onCapture(command)
	}
	return process.Output{StatusCode: 0, Success: true}, nil
}

func containsArgv(commands []Command, argv []string) bool {
	return slices.ContainsFunc(commands, func(command Command) bool {
		return slices.Equal(command.Argv, argv)
	})
}

func commandExistsWith(extra ...string) func(string) bool {
	commands := map[string]bool{
		"ansible-playbook": true,
		"git":              true,
		"git-lfs":          true,
		"chezmoi":          true,
		"go":               true,
		"rustup":           true,
		"podman":           true,
		"distrobox":        true,
		"podman-compose":   true,
		"cc":               true,
		"c++":              true,
		"clang":            true,
		"clang++":          true,
		"cmake":            true,
		"gcc":              true,
		"g++":              true,
		"make":             true,
		"patch":            true,
		"perl":             true,
		"pkg-config":       true,
	}
	for _, name := range extra {
		commands[name] = true
	}
	return func(name string) bool {
		return commands[name]
	}
}

func containsArgvPrefix(commands []Command, prefix []string) bool {
	return slices.ContainsFunc(commands, func(command Command) bool {
		return len(command.Argv) >= len(prefix) && slices.Equal(command.Argv[:len(prefix)], prefix)
	})
}

func mustMkdir(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(path, 0o755); err != nil {
		t.Fatal(err)
	}
}

func mustWrite(t *testing.T, path, text string, mode os.FileMode) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(text), mode); err != nil {
		t.Fatal(err)
	}
}

func readText(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}
