// Package rpc is the single method dispatcher shared by every entry point:
// the c-shared library (Android/iOS/desktop in-process) and the desktop
// process-mode server. Methods take/return JSON so the Dart bridge is
// identical everywhere (docs/MASTER_PROMPT.md §3.3, Appendix B).
package rpc

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"strings"

	"easyvpn/core/pkg/adapter"
	"easyvpn/core/pkg/backup"
	"easyvpn/core/pkg/engine"
	"easyvpn/core/pkg/export"
	"easyvpn/core/pkg/geoip"
	"easyvpn/core/pkg/pinger"
	"easyvpn/core/pkg/protocol"
	"easyvpn/core/pkg/router"
	"easyvpn/core/pkg/rulesync"
	"easyvpn/core/pkg/transport"
	"easyvpn/core/pkg/update"
)

// Server dispatches RPC calls onto an Engine.
type Server struct {
	Eng *engine.Engine

	cancelPing context.CancelFunc
}

// Envelope is the wire format for calls and results.
type Request struct {
	ID     string          `json:"id"`
	Method string          `json:"method"`
	Args   json.RawMessage `json:"args,omitempty"`
}

type Response struct {
	ID     string `json:"id"`
	Result any    `json:"result,omitempty"`
	Error  string `json:"error,omitempty"`
}

// Handle decodes a request JSON and returns the response JSON.
func (s *Server) Handle(reqJSON []byte) []byte {
	var req Request
	resp := Response{}
	if err := json.Unmarshal(reqJSON, &req); err != nil {
		resp.Error = "bad request: " + err.Error()
	} else {
		resp.ID = req.ID
		res, err := s.Call(req.Method, req.Args)
		if err != nil {
			resp.Error = err.Error()
		} else {
			resp.Result = res
		}
	}
	b, _ := json.Marshal(resp)
	return b
}

func decode[T any](raw json.RawMessage) (T, error) {
	var v T
	if len(raw) == 0 {
		return v, nil
	}
	err := json.Unmarshal(raw, &v)
	return v, err
}

// Call runs one method.
func (s *Server) Call(method string, raw json.RawMessage) (any, error) {
	e := s.Eng
	ctx := context.Background()
	switch method {
	case "Init", "Info":
		return e.Info(), nil
	case "GetState":
		return map[string]any{"state": e.GetState(), "stats": e.GetStats()}, nil

	case "Start":
		p, err := decode[engine.StartParams](raw)
		if err != nil {
			return nil, err
		}
		return map[string]any{}, e.Start(p)
	case "Stop":
		return map[string]any{}, e.Stop()
	case "Shutdown":
		e.Shutdown()
		return map[string]any{}, nil
	case "SwitchNode":
		a, err := decode[struct{ Node *protocol.ProxyNode }](raw)
		if err != nil {
			return nil, err
		}
		return map[string]any{}, e.SwitchNode(a.Node)
	case "ExitInfo":
		a, err := decode[struct {
			URL string `json:"url"`
		}](raw)
		if err != nil {
			return nil, err
		}
		return e.LookupExit(ctx, a.URL)
	case "GetStats":
		return e.GetStats(), nil
	case "DumpConfig":
		p, err := decode[engine.StartParams](raw)
		if err != nil {
			return nil, err
		}
		cfg, err := e.DumpConfig(p)
		return map[string]string{"config": cfg}, err

	case "ParseContent":
		a, err := decode[struct {
			Content string `json:"content"`
		}](raw)
		if err != nil {
			return nil, err
		}
		res, err := e.ParseSubscriptionWithWarnings(a.Content)
		if err != nil {
			return nil, err
		}
		return map[string]any{"nodes": res.Nodes, "warnings": res.Warnings}, nil
	case "FetchSubscription":
		a, err := decode[struct {
			URL      string `json:"url"`
			UA       string `json:"ua"`
			ViaProxy bool   `json:"via_proxy"`
		}](raw)
		if err != nil {
			return nil, err
		}
		r, err := e.FetchSubscription(ctx, a.URL, a.UA, a.ViaProxy)
		if err != nil {
			e.Bus().Publish(transport.KindPriority, "subSync", map[string]any{"url": a.URL, "error": err.Error()})
			return nil, err
		}
		e.Bus().Publish(transport.KindPriority, "subSync", map[string]any{"url": a.URL, "count": len(r.Nodes), "via": r.Via})
		return r, nil

	case "WarpRegister":
		a, err := decode[struct {
			Name     string `json:"name"`
			Endpoint string `json:"endpoint"`
			License  string `json:"license"`
		}](raw)
		if err != nil {
			return nil, err
		}
		n, acc, err := e.WarpRegister(ctx, a.Name, a.Endpoint, a.License)
		if err != nil {
			return nil, err
		}
		return map[string]any{"node": n, "account": acc}, nil
	case "WindscribeExpand":
		a, err := decode[struct {
			Template *protocol.ProxyNode `json:"template"`
			Pro      bool                `json:"pro"`
		}](raw)
		if err != nil {
			return nil, err
		}
		nodes, err := e.WindscribeExpand(ctx, a.Template, a.Pro)
		if err != nil {
			return nil, err
		}
		return map[string]any{"nodes": nodes}, nil
	case "UpdateCheck":
		a, err := decode[struct {
			Channel string        `json:"channel"`
			Current string        `json:"current"`
			Target  update.Target `json:"target"`
		}](raw)
		if err != nil {
			return nil, err
		}
		return e.UpdateCheck(ctx, a.Channel, a.Current, a.Target)
	case "UpdateDownload":
		a, err := decode[struct {
			URL    string `json:"url"`
			Name   string `json:"name"`
			SHA256 string `json:"sha256"`
		}](raw)
		if err != nil {
			return nil, err
		}
		p, err := e.UpdateDownload(context.Background(), a.URL, a.Name, a.SHA256)
		if err != nil {
			return nil, err
		}
		return map[string]any{"path": p}, nil

	case "PingBatch":
		a, err := decode[struct {
			Nodes   []*protocol.ProxyNode `json:"nodes"`
			Mode    string                `json:"mode"`
			URL     string                `json:"url"`
			Workers int                   `json:"workers"`
		}](raw)
		if err != nil {
			return nil, err
		}
		return s.ping(a.Nodes, a.Mode, a.URL, a.Workers)
	case "CancelPing":
		if s.cancelPing != nil {
			s.cancelPing()
		}
		return map[string]any{}, nil

	case "SetRouting":
		m, err := decode[router.Model](raw)
		if err != nil {
			return nil, err
		}
		e.SetRoutingModel(m)
		return e.GetRoutingModel(), nil
	case "GetRouting":
		return e.GetRoutingModel(), nil
	case "SetCountry":
		a, err := decode[struct {
			Country string `json:"country"`
		}](raw)
		if err != nil {
			return nil, err
		}
		pack, err := e.SetCountry(a.Country)
		if err != nil {
			return nil, err
		}
		return map[string]any{"routing": e.GetRoutingModel(), "pack": pack}, nil
	case "DetectCountry":
		sig, err := decode[geoip.Signals](raw)
		if err != nil {
			return nil, err
		}
		return e.DetectCountry(sig), nil
	case "SetTricks":
		t, err := decode[adapter.TLSTricks](raw)
		if err != nil {
			return nil, err
		}
		e.SetTricks(t)
		return map[string]any{}, nil

	case "SyncRuleSets":
		a, err := decode[struct {
			Tags []string `json:"tags"`
		}](raw)
		if err != nil {
			return nil, err
		}
		evs, err := e.SyncRuleSets(ctx, a.Tags)
		return map[string]any{"events": evs}, err
	case "RuleSetStatus":
		st, err := e.RuleSetStatus()
		return map[string]any{"statuses": st}, err
	case "Countries":
		rm, err := e.Rules()
		if err != nil {
			return nil, err
		}
		out := map[string]any{}
		for _, c := range rm.Countries() {
			p := rm.CountryPack(c)
			out[c] = map[string]any{"name": p.Name, "tls_tricks": p.TLSTricks, "rule_sets": len(p.RuleSets)}
		}
		return out, nil
	case "AddRuleSet":
		en, err := decode[rulesync.RuleSetEntry](raw)
		if err != nil {
			return nil, err
		}
		rm, err := e.Rules()
		if err != nil {
			return nil, err
		}
		return map[string]any{}, rm.AddCustom(en)
	case "RemoveRuleSet":
		a, err := decode[struct {
			Tag string `json:"tag"`
		}](raw)
		if err != nil {
			return nil, err
		}
		rm, err := e.Rules()
		if err != nil {
			return nil, err
		}
		return map[string]any{}, rm.RemoveCustom(a.Tag)

	case "Export":
		a, err := decode[struct {
			Format string                `json:"format"` // uri|clash|singbox|wgquick
			Nodes  []*protocol.ProxyNode `json:"nodes"`
		}](raw)
		if err != nil {
			return nil, err
		}
		return doExport(a.Format, a.Nodes)

	case "Seal", "Open":
		a, err := decode[struct {
			Key   string   `json:"key"` // base64, 32 bytes
			Items []string `json:"items"`
		}](raw)
		if err != nil {
			return nil, err
		}
		key, err := base64.StdEncoding.DecodeString(a.Key)
		if err != nil {
			return nil, fmt.Errorf("bad key encoding")
		}
		out := make([]string, len(a.Items))
		for i, it := range a.Items {
			if method == "Seal" {
				sealed, err := backup.Seal(key, []byte(it))
				if err != nil {
					return nil, err
				}
				out[i] = base64.StdEncoding.EncodeToString(sealed)
				continue
			}
			blob, err := base64.StdEncoding.DecodeString(it)
			if err != nil {
				return nil, fmt.Errorf("item %d: bad encoding", i)
			}
			pt, err := backup.Open(key, blob)
			if err != nil {
				return nil, fmt.Errorf("item %d: %w", i, err)
			}
			out[i] = string(pt)
		}
		return map[string]any{"items": out}, nil
	case "BackupEncrypt":
		a, err := decode[struct {
			Data       json.RawMessage `json:"data"`
			Passphrase string          `json:"passphrase"`
		}](raw)
		if err != nil {
			return nil, err
		}
		blob, err := backup.Encrypt(a.Data, a.Passphrase)
		if err != nil {
			return nil, err
		}
		return map[string]string{"blob": base64.StdEncoding.EncodeToString(blob)}, nil
	case "BackupDecrypt":
		a, err := decode[struct {
			Blob       string `json:"blob"`
			Passphrase string `json:"passphrase"`
		}](raw)
		if err != nil {
			return nil, err
		}
		blob, err := base64.StdEncoding.DecodeString(a.Blob)
		if err != nil {
			return nil, fmt.Errorf("bad backup encoding")
		}
		pt, err := backup.Decrypt(blob, a.Passphrase)
		if err != nil {
			return nil, err
		}
		return map[string]json.RawMessage{"data": pt}, nil
	}
	return nil, fmt.Errorf("unknown method %q", method)
}

func (s *Server) ping(nodes []*protocol.ProxyNode, mode, url string, workers int) (any, error) {
	ctx, cancel := context.WithCancel(context.Background())
	s.cancelPing = cancel
	defer cancel()
	if strings.EqualFold(mode, "url") {
		res := s.Eng.TestNodesURL(ctx, nodes, url, workers, func(b []adapter.URLTestResult) {
			s.Eng.Bus().Publish(transport.KindPriority, "delay", b)
		})
		return map[string]any{"results": res}, nil
	}
	res := s.Eng.TestNodesLatency(ctx, nodes, pinger.ModeTCP, func(b []pinger.Result) {
		s.Eng.Bus().Publish(transport.KindPriority, "delay", b)
	})
	return map[string]any{"results": res}, nil
}

func doExport(format string, nodes []*protocol.ProxyNode) (any, error) {
	switch strings.ToLower(format) {
	case "uri":
		out, skipped := export.URIList(nodes)
		return map[string]any{"payload": out, "skipped": skipped}, nil
	case "clash":
		y, err := export.ClashYAML(nodes)
		return map[string]any{"payload": y}, err
	case "singbox":
		j, err := adapter.ExportSingBox(nodes)
		return map[string]any{"payload": j}, err
	case "wgquick":
		if len(nodes) == 0 {
			return nil, fmt.Errorf("no node")
		}
		c, err := export.WGQuick(nodes[0])
		return map[string]any{"payload": c}, err
	}
	return nil, fmt.Errorf("unknown export format %q", format)
}
