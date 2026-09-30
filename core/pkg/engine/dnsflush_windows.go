//go:build windows

package engine

import "golang.org/x/sys/windows"

// flushOSDNSCache empties the Windows resolver cache. Programs that resolved
// names before the tunnel came up (in Iran: to the 10.10.34.x filtering
// sinkhole) would otherwise keep using those poisoned answers.
func flushOSDNSCache() {
	p := windows.NewLazySystemDLL("dnsapi.dll").NewProc("DnsFlushResolverCache")
	if p.Find() == nil {
		_, _, _ = p.Call()
	}
}
