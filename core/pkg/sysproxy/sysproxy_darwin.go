//go:build darwin

package sysproxy

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
)

// macOS: networksetup for every network service.
type nsBackend struct{}

func platformBackend() backend { return nsBackend{} }

type nsService struct {
	Name   string `json:"name"`
	Web    string `json:"web"`
	Secure string `json:"secure"`
	Socks  string `json:"socks"`
	Bypass string `json:"bypass"`
}

func services() ([]string, error) {
	out, err := exec.Command("networksetup", "-listallnetworkservices").Output()
	if err != nil {
		return nil, err
	}
	var names []string
	for i, l := range strings.Split(string(out), "\n") {
		l = strings.TrimSpace(l)
		if i == 0 || l == "" || strings.HasPrefix(l, "*") {
			continue
		}
		names = append(names, l)
	}
	return names, nil
}

func ns(args ...string) (string, error) {
	out, err := exec.Command("networksetup", args...).CombinedOutput()
	return strings.TrimSpace(string(out)), err
}

func (nsBackend) snapshot() (json.RawMessage, error) {
	names, err := services()
	if err != nil {
		return nil, err
	}
	var snap []nsService
	for _, n := range names {
		s := nsService{Name: n}
		s.Web, _ = ns("-getwebproxy", n)
		s.Secure, _ = ns("-getsecurewebproxy", n)
		s.Socks, _ = ns("-getsocksfirewallproxy", n)
		s.Bypass, _ = ns("-getproxybypassdomains", n)
		snap = append(snap, s)
	}
	return json.Marshal(snap)
}

func (nsBackend) apply(host string, port int, bypass []string) error {
	names, err := services()
	if err != nil {
		return err
	}
	p := fmt.Sprint(port)
	for _, n := range names {
		for _, cmd := range []string{"-setwebproxy", "-setsecurewebproxy", "-setsocksfirewallproxy"} {
			if _, err := ns(cmd, n, host, p); err != nil {
				return err
			}
		}
		args := append([]string{"-setproxybypassdomains", n}, bypass...)
		if _, err := ns(args...); err != nil {
			return err
		}
	}
	return nil
}

func parseNS(s string) (enabled bool, host, port string) {
	for _, l := range strings.Split(s, "\n") {
		kv := strings.SplitN(l, ":", 2)
		if len(kv) != 2 {
			continue
		}
		v := strings.TrimSpace(kv[1])
		switch strings.TrimSpace(kv[0]) {
		case "Enabled":
			enabled = v == "Yes"
		case "Server":
			host = v
		case "Port":
			port = v
		}
	}
	return
}

func (nsBackend) restore(raw json.RawMessage) error {
	var snap []nsService
	if err := json.Unmarshal(raw, &snap); err != nil {
		return err
	}
	for _, s := range snap {
		for _, e := range []struct{ set, state, val string }{
			{"-setwebproxy", "-setwebproxystate", s.Web},
			{"-setsecurewebproxy", "-setsecurewebproxystate", s.Secure},
			{"-setsocksfirewallproxy", "-setsocksfirewallproxystate", s.Socks},
		} {
			on, host, port := parseNS(e.val)
			if host != "" && port != "" && port != "0" {
				_, _ = ns(e.set, s.Name, host, port)
			}
			st := "off"
			if on {
				st = "on"
			}
			_, _ = ns(e.state, s.Name, st)
		}
		if strings.Contains(s.Bypass, "aren't any") || s.Bypass == "" {
			_, _ = ns("-setproxybypassdomains", s.Name, "Empty")
		} else {
			args := append([]string{"-setproxybypassdomains", s.Name}, strings.Split(s.Bypass, "\n")...)
			_, _ = ns(args...)
		}
	}
	return nil
}
