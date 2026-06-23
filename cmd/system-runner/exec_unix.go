//go:build !windows

package main

import "syscall"

func execProgram(program string, args, env []string) error {
	return syscall.Exec(program, args, env)
}
