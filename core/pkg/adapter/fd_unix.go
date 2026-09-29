//go:build !windows

package adapter

import "syscall"

func dupFD(fd int) (int, error) { return syscall.Dup(fd) }
