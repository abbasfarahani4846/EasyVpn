// Command libeasycore is compiled as a C-shared library and exposes the
// stable FFI surface consumed by lib/core/ffi/easy_core_ffi.dart.
// All functions are thread-safe; long work happens on Go goroutines and
// progress arrives through the registered event callback.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"encoding/json"
	"sync"
	"unsafe"

	"easyvpn/core/pkg/engine"
	"easyvpn/core/pkg/pinger"
	"easyvpn/core/pkg/protocol"
	"easyvpn/core/pkg/router"
)

var (
	coreMu  sync.Mutex
	coreEng *engine.Engine
	eventFn unsafe.Pointer // C event callback: void (*fn)(const char* json)
)

func main() {}

func getEngine(cacheDir string) *engine.Engine {
	coreMu.Lock()
	defer coreMu.Unlock()
	if coreEng == nil {
		coreEng = engine.NewEngine(cacheDir)
		go pumpEvents(coreEng)
	}
	return coreEng
}

// pumpEvents forwards bus batches to the registered C callback.
func pumpEvents(e *engine.Engine) {
	ch, unsub := e.Bus().Subscribe()
	defer unsub()
	for batch := range ch {
		coreMu.Lock()
		fn := eventFn
		coreMu.Unlock()
		if fn == nil {
			continue
		}
		payload, err := json.Marshal(batch)
		if err != nil {
			continue
		}
		cstr := C.CString(string(payload))
		(*[0]byte)(fn)(unsafe.Pointer(&struct{ p *C.char }{cstr}))
		C.free(unsafe.Pointer(cstr))
	}
}

func cString(s string) *C.char { return C.CString(s) }

func freeCStr(p *C.char) { C.free(unsafe.Pointer(p)) }

//export InitCore
func InitCore(cacheDir *C.char) {
	getEngine(C.GoString(cacheDir))
}

//export RegisterEventCallback
func RegisterEventCallback(cb *C.char) {
	// cb is a C function pointer passed as char* from Dart (NativeCallable).
	coreMu.Lock()
	eventFn = unsafe.Pointer(cb)
	coreMu.Unlock()
}

//export StartProxy
func StartProxy(nodeJSON *C.char, tun C.int) C.int {
	e := getEngine("")
	var node protocol.ProxyNode
	if err := json.Unmarshal([]byte(C.GoString(nodeJSON)), &node); err != nil {
		return -1
	}
	if err := e.StartWithNode(&node, tun == 1); err != nil {
		return -2
	}
	return 0
}

//export StopProxy
func StopProxy() C.int {
	coreMu.Lock()
	e := coreEng
	coreMu.Unlock()
	if e == nil {
		return 0
	}
	if err := e.Stop(); err != nil {
		return -1
	}
	return 0
}

//export SwitchProxy
func SwitchProxy(nodeJSON *C.char) C.int {
	coreMu.Lock()
	e := coreEng
	coreMu.Unlock()
	if e == nil {
		return -1
	}
	var node protocol.ProxyNode
	if err := json.Unmarshal([]byte(C.GoString(nodeJSON)), &node); err != nil {
		return -1
	}
	if err := e.SwitchNode(&node); err != nil {
		return -2
	}
	return 0
}

//export GetStatsJSON
func GetStatsJSON() *C.char {
	coreMu.Lock()
	e := coreEng
	coreMu.Unlock()
	if e == nil {
		return cString(`{}`)
	}
	b, err := json.Marshal(e.GetStats())
	if err != nil {
		return cString(`{}`)
	}
	return cString(string(b))
}

//export ParseSubscription
func ParseSubscription(content *C.char) *C.char {
	e := getEngine("")
	res, err := e.ParseSubscriptionWithWarnings(C.GoString(content))
	if err != nil {
		b, _ := json.Marshal(map[string]any{"error": err.Error(), "nodes": []any{}})
		return cString(string(b))
	}
	b, _ := json.Marshal(map[string]any{"error": "", "nodes": res.Nodes, "warnings": res.Warnings})
	return cString(string(b))
}

//export TestBatchPing
func TestBatchPing(nodesJSON *C.char, mode *C.char) *C.char {
	e := getEngine("")
	var nodes []*protocol.ProxyNode
	if err := json.Unmarshal([]byte(C.GoString(nodesJSON)), &nodes); err != nil {
		return cString(`{"results":[]}`)
	}
	m := pinger.Mode(C.GoString(mode))
	if m == "" {
		m = pinger.ModeTCP
	}
	results := e.TestNodesLatency(context.Background(), nodes, m, nil)
	b, _ := json.Marshal(map[string]any{"results": results})
	return cString(string(b))
}

//export SetCountry
func SetCountry(code *C.char) {
	coreMu.Lock()
	e := coreEng
	coreMu.Unlock()
	if e != nil {
		e.SetRoutingCountry(C.GoString(code))
	}
}

//export SetRoutingMode
func SetRoutingMode(mode *C.char) {
	coreMu.Lock()
	e := coreEng
	coreMu.Unlock()
	if e != nil {
		e.SetRoutingMode(router.RoutingMode(C.GoString(mode)))
	}
}

//export SetLocalPort
func SetLocalPort(port C.int) {
	coreMu.Lock()
	e := coreEng
	coreMu.Unlock()
	if e != nil {
		e.SetLocalPort(int(port))
	}
}

//export SetRoutingModel
func SetRoutingModel(modelJSON *C.char) C.int {
	coreMu.Lock()
	e := coreEng
	coreMu.Unlock()
	if e == nil {
		return -1
	}
	var m router.Model
	if err := json.Unmarshal([]byte(C.GoString(modelJSON)), &m); err != nil {
		return -1
	}
	e.SetRoutingModel(m)
	return 0
}

//export FreeString
func FreeString(str *C.char) {
	freeCStr(str)
}
