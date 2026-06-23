package chezmoi

import "fmt"

type commandHandler func(Options) error

var commandHandlers = map[string]commandHandler{
	"shell-init":                   withoutOptions(ShellInit),
	"install-vs-extensions":        InstallVSExtensions,
	"install-hyper-window-tiling":  InstallHyperWindowTiling,
	"zed-install-catppuccin-theme": InstallZedCatppuccinTheme,
	"yazi-init":                    InstallYaziPlugins,
	"raycast-beta-patch":           PatchRaycastBetaUser,
}

func Run(command string, options Options) error {
	handler, ok := commandHandlers[command]
	if !ok {
		return fmt.Errorf("unknown command %q", command)
	}
	return handler(options)
}

func withoutOptions(fn func() error) commandHandler {
	return func(Options) error {
		return fn()
	}
}
