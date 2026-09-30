//go:build !windows && !darwin && !(linux && !android)

package sysproxy

func platformBackend() backend { return nil }
