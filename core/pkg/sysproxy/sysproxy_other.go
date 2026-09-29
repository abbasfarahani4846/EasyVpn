//go:build !windows && !darwin && !linux

package sysproxy

func platformBackend() backend { return nil }
