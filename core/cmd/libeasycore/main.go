// Command libeasycore is compiled as a C-shared library and exposes a tiny,
// stable FFI surface consumed by the Dart bridge (and the Android JNI module):
//
//	InitCore(cacheDir)              create/refresh the engine
//	RegisterEventCallback(cb)       batched events (JSON) are pushed to cb
//	CoreCall(requestJSON) -> JSON   run any RPC method (see pkg/rpc)
//	FreeString(p)                   release strings returned by CoreCall
//
// CoreCall blocks until the method finishes: call it from a worker isolate.
package main

/*
#include <stdlib.h>

typedef void (*event_callback_t)(const char* json);

static void invoke_event_callback(event_callback_t cb, const char* json) {
	if (cb != NULL) {
		cb(json);
	}
}
*/
import "C"

import (
	"encoding/json"
	"sync"
	"unsafe"

	"easyvpn/core/pkg/engine"
	"easyvpn/core/pkg/rpc"
)

var (
	coreMu  sync.Mutex
	coreEng *engine.Engine
	server  *rpc.Server
	eventFn C.event_callback_t
)

func main() {}

func getServer(cacheDir string) *rpc.Server {
	coreMu.Lock()
	defer coreMu.Unlock()
	if coreEng == nil {
		coreEng = engine.NewEngine(cacheDir)
		server = &rpc.Server{Eng: coreEng}
		go pumpEvents(coreEng)
	}
	return server
}

func currentServer() *rpc.Server {
	coreMu.Lock()
	defer coreMu.Unlock()
	return server
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
		C.invoke_event_callback(fn, cstr)
		C.free(unsafe.Pointer(cstr))
	}
}

//export InitCore
func InitCore(cacheDir *C.char) {
	getServer(C.GoString(cacheDir))
}

//export RegisterEventCallback
func RegisterEventCallback(cb C.event_callback_t) {
	coreMu.Lock()
	eventFn = cb
	coreMu.Unlock()
}

//export CoreCall
func CoreCall(request *C.char) *C.char {
	s := currentServer()
	if s == nil {
		return C.CString(`{"error":"core not initialized; call InitCore first"}`)
	}
	return C.CString(string(s.Handle([]byte(C.GoString(request)))))
}

//export FreeString
func FreeString(p *C.char) { C.free(unsafe.Pointer(p)) }
