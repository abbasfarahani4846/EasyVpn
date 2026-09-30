//go:build windows

package adapter

import "errors"

func dupFD(int) (int, error) { return 0, errors.New("file-descriptor TUN is not supported on Windows") }
