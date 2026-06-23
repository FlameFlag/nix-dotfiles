package main

import (
	"context"
	"os"

	"github.com/FlameFlag/nix-dotfiles/internal/common/cli"
	"github.com/FlameFlag/nix-dotfiles/internal/ndtools/app"
)

var version = "dev"

func main() {
	if err := cli.Execute(context.Background(), app.Command(), os.Args[1:], version); err != nil {
		os.Exit(1)
	}
}
