package zellijtheme

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"

	commonprocess "github.com/euvlok/nix-dotfiles/internal/common/process"
	"github.com/euvlok/nix-dotfiles/internal/zellijtheme/codex"
)

func (r runnerSpec) run(extraArgs []string) (int, error) {
	programs := r.Programs
	if len(programs) == 0 {
		programs = []string{r.Name}
	}
	var skip []string
	for _, name := range r.SkipEnv {
		if value := os.Getenv(name); value != "" {
			skip = append(skip, value)
		}
	}
	if exe, err := os.Executable(); err == nil {
		skip = append(skip, exe)
	}
	executable := ""
	for _, rawName := range programs {
		name := expandPath(rawName)
		if envName, ok := strings.CutPrefix(rawName, "$"); ok {
			value := os.Getenv(envName)
			if value == "" {
				continue
			}
			name = value
		}
		var candidates []string
		if commonprocess.IsPathLike(name) {
			info, err := os.Stat(name)
			if err == nil && commonprocess.IsExecutableFile(info) {
				candidates = append(candidates, name)
			}
		} else {
			for _, dir := range filepath.SplitList(os.Getenv("PATH")) {
				path := filepath.Join(dir, name)
				info, err := os.Stat(path)
				if err == nil && commonprocess.IsExecutableFile(info) {
					candidates = append(candidates, path)
				}
			}
			if len(candidates) == 0 {
				if path, err := exec.LookPath(name); err == nil {
					candidates = append(candidates, path)
				}
			}
		}
		for _, candidate := range candidates {
			matchedSkip := false
			for _, other := range skip {
				samePath := candidate == other
				sameResolvedPath := false
				if !samePath {
					left, lerr := filepath.EvalSymlinks(candidate)
					right, rerr := filepath.EvalSymlinks(other)
					sameResolvedPath = lerr == nil && rerr == nil && left == right
				}
				if samePath || sameResolvedPath {
					matchedSkip = true
					break
				}
			}
			if !matchedSkip {
				executable = candidate
				break
			}
		}
		if executable != "" {
			break
		}
	}
	if executable == "" {
		return 1, fmt.Errorf("%s executable not found", r.Name)
	}
	if r.StartupPaneColor {
		startup := StartStartupPaneColor()
		defer startup.Close()
	}

	runtimeEnv := []string(nil)
	cleanup := func() {}
	switch r.EnvOverlay {
	case "":
	case "codex-trust":
		overlay, overlayCleanup, err := codex.CreateTrustOverlay(DetectSystemTheme().Name)
		if err != nil {
			return 1, err
		}
		runtimeEnv = []string{"CODEX_HOME=" + overlay}
		cleanup = overlayCleanup
	default:
		return 1, fmt.Errorf("%s has unknown env overlay %q", r.Name, r.EnvOverlay)
	}
	defer cleanup()

	args := slices.Clone(r.DefaultArgs)
	for _, arg := range r.ThemeArgs {
		value := arg.Dark
		if DetectSystemTheme().Name == Latte.Name {
			value = arg.Light
		}
		if value != "" {
			args = append(args, value)
		}
	}
	if r.Config != nil {
		configArgs, cleanup, err := r.Config.args(extraArgs)
		if err != nil {
			return 1, err
		}
		defer cleanup()
		args = append(args, configArgs...)
		extraArgs = stripArgs(extraArgs, r.Config.ArgNames)
	}
	args = append(args, extraArgs...)
	var childEnv []string
	if len(r.Env) > 0 || len(r.EnvUnset) > 0 || len(runtimeEnv) > 0 {
		childEnv = os.Environ()
		for _, name := range r.EnvUnset {
			prefix := name + "="
			childEnv = slices.DeleteFunc(childEnv, func(item string) bool {
				return strings.HasPrefix(item, prefix)
			})
		}
		childEnv = slices.Concat(childEnv, r.Env, runtimeEnv)
	}
	return RunInheritEnv(executable, args, childEnv)
}

func stripArgs(args, names []string) []string {
	var out []string
	for index := 0; index < len(args); index++ {
		arg := args[index]
		removed := false
		for _, name := range names {
			if arg == name {
				index++
				removed = true
				break
			}
			if strings.HasPrefix(arg, name+"=") {
				removed = true
				break
			}
		}
		if !removed {
			out = append(out, arg)
		}
	}
	return out
}
