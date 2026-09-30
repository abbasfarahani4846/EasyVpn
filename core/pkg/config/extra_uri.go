package config

import (
	"fmt"
	"net/url"
	"strconv"

	"easyvpn/core/pkg/protocol"
)

// anytls://password@host:port?sni=...&insecure=1#name
func parseAnyTLS(body, fragment string) (*protocol.ProxyNode, error) {
	u, err := url.Parse("anytls://" + body)
	if err != nil {
		return nil, err
	}
	if u.Host == "" || u.User == nil {
		return nil, fmt.Errorf("invalid anytls URI")
	}
	port, err := strconv.Atoi(u.Port())
	if err != nil {
		return nil, fmt.Errorf("invalid anytls port: %w", err)
	}
	q := u.Query()
	q.Set("security", "tls")
	node := &protocol.ProxyNode{
		Name:     displayName(fragment, "AnyTLS", u),
		Type:     protocol.ProtoAnyTLS,
		Server:   u.Hostname(),
		Port:     port,
		Password: u.User.Username(),
		TLS:      parseTLSQuery(q),
	}
	if node.TLS.ServerName == "" {
		node.TLS.ServerName = u.Hostname()
	}
	node.EnsureID()
	return node, nil
}

// ssh://user:password@host:port#name
func parseSSH(body, fragment string) (*protocol.ProxyNode, error) {
	u, err := url.Parse("ssh://" + body)
	if err != nil {
		return nil, err
	}
	if u.Host == "" || u.User == nil {
		return nil, fmt.Errorf("invalid ssh URI")
	}
	port := 22
	if u.Port() != "" {
		if port, err = strconv.Atoi(u.Port()); err != nil {
			return nil, fmt.Errorf("invalid ssh port: %w", err)
		}
	}
	pass, _ := u.User.Password()
	node := &protocol.ProxyNode{
		Name:     displayName(fragment, "SSH", u),
		Type:     protocol.ProtoSSH,
		Server:   u.Hostname(),
		Port:     port,
		UUID:     u.User.Username(),
		Password: pass,
	}
	if pk := u.Query().Get("private_key"); pk != "" {
		node.SSH = &protocol.SSHConfig{PrivateKey: pk}
	}
	node.EnsureID()
	return node, nil
}
