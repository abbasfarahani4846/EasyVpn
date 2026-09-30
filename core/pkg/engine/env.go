package engine

import "os"

// PrepareRuntime makes the process safe on platforms with a read-only working
// directory and no usable HOME/TMPDIR (Android): every relative or temp path the
// embedded engines might use ends up inside the app cache directory.
func PrepareRuntime(cacheDir string) {
	if cacheDir == "" {
		return
	}
	_ = os.MkdirAll(cacheDir, 0o755)
	if !writable(os.TempDir()) {
		_ = os.Setenv("TMPDIR", cacheDir)
	}
	if h := os.Getenv("HOME"); h == "" || !writable(h) {
		_ = os.Setenv("HOME", cacheDir)
	}
	if wd, err := os.Getwd(); err != nil || !writable(wd) {
		_ = os.Chdir(cacheDir)
	}
}

func writable(dir string) bool {
	f, err := os.CreateTemp(dir, ".w")
	if err != nil {
		return false
	}
	name := f.Name()
	f.Close()
	os.Remove(name)
	return true
}
