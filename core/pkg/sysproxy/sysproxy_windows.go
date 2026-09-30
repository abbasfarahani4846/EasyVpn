//go:build windows

package sysproxy

import (
	"encoding/json"
	"fmt"
	"strings"
	"syscall"

	"golang.org/x/sys/windows/registry"
)

const regPath = `Software\Microsoft\Windows\CurrentVersion\Internet Settings`

// WinINET per-user proxy (no elevation needed).
type wininetBackend struct{}

func platformBackend() backend { return wininetBackend{} }

type winSnap struct {
	ProxyEnable   uint32 `json:"proxy_enable"`
	ProxyServer   string `json:"proxy_server"`
	ProxyOverride string `json:"proxy_override"`
	AutoConfigURL string `json:"auto_config_url"`
	HadServer     bool   `json:"had_server"`
	HadOverride   bool   `json:"had_override"`
	HadAutoConfig bool   `json:"had_auto_config"`
}

func (wininetBackend) snapshot() (json.RawMessage, error) {
	k, err := registry.OpenKey(registry.CURRENT_USER, regPath, registry.QUERY_VALUE)
	if err != nil {
		return nil, err
	}
	defer k.Close()
	var s winSnap
	if v, _, err := k.GetIntegerValue("ProxyEnable"); err == nil {
		s.ProxyEnable = uint32(v)
	}
	if v, _, err := k.GetStringValue("ProxyServer"); err == nil {
		s.ProxyServer, s.HadServer = v, true
	}
	if v, _, err := k.GetStringValue("ProxyOverride"); err == nil {
		s.ProxyOverride, s.HadOverride = v, true
	}
	if v, _, err := k.GetStringValue("AutoConfigURL"); err == nil {
		s.AutoConfigURL, s.HadAutoConfig = v, true
	}
	return json.Marshal(s)
}

func (wininetBackend) apply(host string, port int, bypass []string) error {
	k, err := registry.OpenKey(registry.CURRENT_USER, regPath, registry.SET_VALUE)
	if err != nil {
		return err
	}
	defer k.Close()
	if err := k.SetStringValue("ProxyServer", fmt.Sprintf("%s:%d", host, port)); err != nil {
		return err
	}
	if err := k.SetStringValue("ProxyOverride", strings.Join(append(winBypass(bypass), "<local>"), ";")); err != nil {
		return err
	}
	_ = k.DeleteValue("AutoConfigURL")
	if err := k.SetDWordValue("ProxyEnable", 1); err != nil {
		return err
	}
	notify()
	return nil
}

// winBypass converts CIDR shorthands into WinINET wildcards.
func winBypass(in []string) []string {
	var out []string
	for _, b := range in {
		switch b {
		case "10.0.0.0/8":
			out = append(out, "10.*")
		case "172.16.0.0/12":
			for i := 16; i <= 31; i++ {
				out = append(out, fmt.Sprintf("172.%d.*", i))
			}
		case "192.168.0.0/16":
			out = append(out, "192.168.*")
		default:
			out = append(out, b)
		}
	}
	return out
}

func (wininetBackend) restore(raw json.RawMessage) error {
	var s winSnap
	if err := json.Unmarshal(raw, &s); err != nil {
		return err
	}
	k, err := registry.OpenKey(registry.CURRENT_USER, regPath, registry.SET_VALUE)
	if err != nil {
		return err
	}
	defer k.Close()
	set := func(name, v string, had bool) {
		if had {
			_ = k.SetStringValue(name, v)
		} else {
			_ = k.DeleteValue(name)
		}
	}
	set("ProxyServer", s.ProxyServer, s.HadServer)
	set("ProxyOverride", s.ProxyOverride, s.HadOverride)
	set("AutoConfigURL", s.AutoConfigURL, s.HadAutoConfig)
	_ = k.SetDWordValue("ProxyEnable", s.ProxyEnable)
	notify()
	return nil
}

// notify tells running applications that the proxy settings changed.
func notify() {
	dll := syscall.NewLazyDLL("wininet.dll")
	proc := dll.NewProc("InternetSetOptionW")
	const optSettingsChanged, optRefresh = 39, 37
	_, _, _ = proc.Call(0, optSettingsChanged, 0, 0)
	_, _, _ = proc.Call(0, optRefresh, 0, 0)
}
