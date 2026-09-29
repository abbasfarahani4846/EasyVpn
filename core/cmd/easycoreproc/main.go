// Command easycoreproc is the desktop process-mode core (CGO_ENABLED=0).
// It speaks a newline-delimited JSON-RPC protocol on stdin/stdout:
//
//	→ {"id":"1","method":"ParseContent","args":{"content":"..."}}
//	← {"id":"1","result":{...}}   |   {"id":"1","error":"..."}
//	← {"type":"state|stats|delay|log","payload":{...}}   (events, no id)
//
// The Dart desktop side owns the process lifetime and the transport; this
// binary stays engine-agnostic and only wraps pkg/engine.
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"sync"

	"easyvpn/core/pkg/engine"
	"easyvpn/core/pkg/pinger"
	"easyvpn/core/pkg/protocol"
	"easyvpn/core/pkg/router"
)

type request struct {
	ID     string          `json:"id"`
	Method string          `json:"method"`
	Args   json.RawMessage `json:"args,omitempty"`
}

type response struct {
	ID     string          `json:"id"`
	Result json.RawMessage `json:"result,omitempty"`
	Error  string          `json:"error,omitempty"`
}

type event struct {
	Type    string `json:"type"`
	Payload any    `json:"payload,omitempty"`
}

var (
	outMu sync.Mutex
	out   = bufio.NewWriter(os.Stdout)
)

func writeLine(v any) {
	b, err := json.Marshal(v)
	if err != nil {
		return
	}
	outMu.Lock()
	defer outMu.Unlock()
	out.Write(b)
	out.WriteByte('\n')
	out.Flush()
}

func reply(id string, result any, errText string) {
	var raw json.RawMessage
	if result != nil {
		raw, _ = json.Marshal(result)
	}
	writeLine(response{ID: id, Result: raw, Error: errText})
}

func main() {
	cacheDir := "."
	if len(os.Args) > 1 {
		cacheDir = os.Args[1]
	}
	eng := engine.NewEngine(cacheDir)

	// Fan out core events to stdout as one-line JSON events.
	events, unsub := eng.Bus().Subscribe()
	go func() {
		for batch := range events {
			for _, ev := range batch {
				writeLine(event{Type: ev.Type, Payload: ev.Payload})
			}
		}
	}()
	defer unsub()

	ctx := context.Background()
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 1024*1024), 16*1024*1024) // big subscription payloads

	for scanner.Scan() {
		line := scanner.Bytes()
		if len(line) == 0 {
			continue
		}
		var req request
		if err := json.Unmarshal(line, &req); err != nil {
			reply("", nil, "bad request: "+err.Error())
			continue
		}
		handle(ctx, eng, req)
	}
}

func handle(ctx context.Context, eng *engine.Engine, req request) {
	switch req.Method {
	case "GetState":
		reply(req.ID, map[string]string{"state": string(eng.GetState())}, "")

	case "Start":
		var args struct {
			Node      protocol.ProxyNode `json:"node"`
			TUN       bool               `json:"tun"`
			LocalPort int                `json:"local_port"`
		}
		if err := json.Unmarshal(req.Args, &args); err != nil {
			reply(req.ID, nil, err.Error())
			return
		}
		if args.LocalPort > 0 {
			eng.SetLocalPort(args.LocalPort)
		}
		if err := eng.StartWithNode(&args.Node, args.TUN); err != nil {
			reply(req.ID, nil, err.Error())
			return
		}
		reply(req.ID, map[string]string{"ok": "true"}, "")

	case "Stop":
		if err := eng.Stop(); err != nil {
			reply(req.ID, nil, err.Error())
			return
		}
		reply(req.ID, map[string]string{"ok": "true"}, "")

	case "ParseContent":
		var args struct {
			Content string `json:"content"`
		}
		if err := json.Unmarshal(req.Args, &args); err != nil {
			reply(req.ID, nil, err.Error())
			return
		}
		res, err := eng.ParseSubscriptionWithWarnings(args.Content)
		if err != nil {
			reply(req.ID, nil, err.Error())
			return
		}
		reply(req.ID, res, "")

	case "PingBatch":
		var args struct {
			Nodes   []*protocol.ProxyNode `json:"nodes"`
			Mode    pinger.Mode           `json:"mode"`
			Workers int                   `json:"workers"`
		}
		if err := json.Unmarshal(req.Args, &args); err != nil {
			reply(req.ID, nil, err.Error())
			return
		}
		results := eng.TestNodesLatency(ctx, args.Nodes, args.Mode, nil)
		reply(req.ID, map[string]any{"results": results}, "")

	case "SetRoutingModel":
		var m router.Model
		if err := json.Unmarshal(req.Args, &m); err != nil {
			reply(req.ID, nil, err.Error())
			return
		}
		eng.SetRoutingModel(m)
		reply(req.ID, map[string]string{"ok": "true"}, "")

	case "SetRouting":
		var args struct {
			Country string             `json:"country"`
			Mode    router.RoutingMode `json:"mode"`
		}
		if err := json.Unmarshal(req.Args, &args); err != nil {
			reply(req.ID, nil, err.Error())
			return
		}
		eng.SetRoutingCountry(args.Country)
		eng.SetRoutingMode(args.Mode)
		reply(req.ID, map[string]string{"ok": "true"}, "")

	default:
		reply(req.ID, nil, fmt.Sprintf("unknown method: %s", req.Method))
	}
}
