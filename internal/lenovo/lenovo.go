package lenovo

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/log"
	"github.com/euvlok/nix-dotfiles/internal/lenovo/backend"
)

type (
	Action         string
	actionDecision func(current bool) (desired bool, shouldWrite bool)
)

const (
	Status  Action = "status"
	On      Action = "on"
	Enable  Action = "enable"
	Off     Action = "off"
	Disable Action = "disable"
	Toggle  Action = "toggle"
)

var actionDecisions = map[Action]actionDecision{
	Status:  keepCurrent,
	On:      enableMode,
	Enable:  enableMode,
	Off:     disableMode,
	Disable: disableMode,
	Toggle:  toggleMode,
}

var stateLabels = map[bool]string{
	true:  "ENABLED (60% charge)",
	false: "DISABLED (100% charge)",
}

func ParseAction(value string) (Action, error) {
	if value == "" {
		return Toggle, nil
	}
	action := Action(strings.ToLower(value))
	if _, ok := actionDecisions[action]; ok {
		return action, nil
	}
	return "", fmt.Errorf("unknown action %q", value)
}

func Run(action Action) error {
	supported, err := backend.IsSupportedLenovo()
	if err != nil {
		return err
	}
	if !supported {
		log.Info(
			"Lenovo conservation mode is only supported on Lenovo laptops with a known Linux backend; skipping",
		)
		return nil
	}
	current, err := backend.ReadMode()
	if err != nil {
		return err
	}
	decide, ok := actionDecisions[action]
	if !ok {
		return fmt.Errorf("unknown action %q", action)
	}
	desired, shouldWrite := decide(current)
	if shouldWrite && desired != current {
		if err := backend.WriteMode(desired); err != nil {
			return err
		}
	}
	fmt.Printf("Conservation Mode: %s\n", StateLabel(desired))
	return nil
}

func StateLabel(enabled bool) string {
	return stateLabels[enabled]
}

func keepCurrent(current bool) (bool, bool) {
	return current, false
}

func enableMode(bool) (bool, bool) {
	return true, true
}

func disableMode(bool) (bool, bool) {
	return false, true
}

func toggleMode(current bool) (bool, bool) {
	return !current, true
}
