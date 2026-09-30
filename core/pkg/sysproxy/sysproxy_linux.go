//go:build linux && !android

package sysproxy

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
)

// GNOME/Cinnamon/Unity via gsettings. KDE and others are best-effort (see
// docs): the mixed port stays available for manual configuration.
type gsettingsBackend struct{}

func platformBackend() backend {
	if _, err := exec.LookPath("gsettings"); err != nil {
		return nil
	}
	return gsettingsBackend{}
}

type gsSnap map[string]string

var gsKeys = [][2]string{
	{"org.gnome.system.proxy", "mode"},
	{"org.gnome.system.proxy", "ignore-hosts"},
	{"org.gnome.system.proxy.http", "host"},
	{"org.gnome.system.proxy.http", "port"},
	{"org.gnome.system.proxy.https", "host"},
	{"org.gnome.system.proxy.https", "port"},
	{"org.gnome.system.proxy.socks", "host"},
	{"org.gnome.system.proxy.socks", "port"},
}

func gset(schema, key, val string) error {
	return exec.Command("gsettings", "set", schema, key, val).Run()
}

func (gsettingsBackend) snapshot() (json.RawMessage, error) {
	s := gsSnap{}
	for _, k := range gsKeys {
		out, err := exec.Command("gsettings", "get", k[0], k[1]).Output()
		if err != nil {
			return nil, fmt.Errorf("gsettings get %s %s: %w", k[0], k[1], err)
		}
		s[k[0]+" "+k[1]] = strings.TrimSpace(string(out))
	}
	return json.Marshal(s)
}

func (gsettingsBackend) apply(host string, port int, bypass []string) error {
	p := fmt.Sprint(port)
	for _, sch := range []string{"http", "https", "socks"} {
		if err := gset("org.gnome.system.proxy."+sch, "host", "'"+host+"'"); err != nil {
			return err
		}
		if err := gset("org.gnome.system.proxy."+sch, "port", p); err != nil {
			return err
		}
	}
	quoted := make([]string, len(bypass))
	for i, b := range bypass {
		quoted[i] = "'" + b + "'"
	}
	if err := gset("org.gnome.system.proxy", "ignore-hosts", "["+strings.Join(quoted, ", ")+"]"); err != nil {
		return err
	}
	return gset("org.gnome.system.proxy", "mode", "'manual'")
}

func (gsettingsBackend) restore(raw json.RawMessage) error {
	var s gsSnap
	if err := json.Unmarshal(raw, &s); err != nil {
		return err
	}
	var firstErr error
	for _, k := range gsKeys {
		if v, ok := s[k[0]+" "+k[1]]; ok {
			if err := gset(k[0], k[1], v); err != nil && firstErr == nil {
				firstErr = err
			}
		}
	}
	return firstErr
}
