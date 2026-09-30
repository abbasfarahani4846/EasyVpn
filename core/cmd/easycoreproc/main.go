// Command easycoreproc is the desktop process-mode core (CGO-free).
//
// IPC: a loopback TCP listener on a random port protected by a random
// per-launch token (256-bit). On start it prints one JSON line to stdout:
//
//	{"ready":true,"port":51234,"token":"<hex>"}
//
// The parent (Flutter app) reads it, connects, and sends {"auth":"<token>"}
// as the first line; then newline-delimited JSON requests
// {"id","method","args"} get {"id","result"|"error"} responses, and batched
// events arrive as {"event":[...]} lines. Connections without a valid token
// are closed immediately. The process exits when its stdin closes (parent
// death) after restoring the OS proxy.
package main

import (
	"bufio"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"sync"
	"time"

	"easyvpn/core/pkg/engine"
	"easyvpn/core/pkg/rpc"
)

func main() {
	cacheDir := flag.String("cache", "", "cache directory (required)")
	debug := flag.Bool("debug", false, "also serve requests on stdin/stdout (debug only)")
	flag.Parse()
	if *cacheDir == "" {
		fmt.Fprintln(os.Stderr, "usage: easycoreproc -cache <dir>")
		os.Exit(2)
	}

	engine.InstallCrashLog(*cacheDir)
	eng := engine.NewEngine(*cacheDir)
	srv := &rpc.Server{Eng: eng}

	tokenBytes := make([]byte, 32)
	if _, err := rand.Read(tokenBytes); err != nil {
		fmt.Fprintln(os.Stderr, "rng:", err)
		os.Exit(1)
	}
	token := hex.EncodeToString(tokenBytes)

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		fmt.Fprintln(os.Stderr, "listen:", err)
		os.Exit(1)
	}
	port := ln.Addr().(*net.TCPAddr).Port
	ready, _ := json.Marshal(map[string]any{"ready": true, "port": port, "token": token})
	fmt.Println(string(ready))

	go func() { // exit (restoring the OS proxy) when the parent goes away
		_, _ = io.Copy(io.Discard, os.Stdin)
		eng.Shutdown()
		os.Exit(0)
	}()
	if *debug {
		go serve(struct {
			io.Reader
			io.Writer
		}{os.Stdin, os.Stdout}, srv, "")
	}
	for {
		c, err := ln.Accept()
		if err != nil {
			return
		}
		go serve(c, srv, token)
	}
}

func serve(rw io.ReadWriter, srv *rpc.Server, token string) {
	if c, ok := rw.(net.Conn); ok {
		defer c.Close()
		_ = c.SetReadDeadline(time.Now().Add(5 * time.Second))
	}
	r := bufio.NewReaderSize(rw, 1<<20)
	if token != "" {
		line, err := r.ReadBytes('\n')
		var a struct {
			Auth string `json:"auth"`
		}
		if err != nil || json.Unmarshal(line, &a) != nil ||
			subtle.ConstantTimeCompare([]byte(a.Auth), []byte(token)) != 1 {
			return
		}
		if c, ok := rw.(net.Conn); ok {
			_ = c.SetReadDeadline(time.Time{})
		}
	}

	var wmu sync.Mutex
	write := func(b []byte) {
		wmu.Lock()
		defer wmu.Unlock()
		_, _ = rw.Write(append(b, '\n'))
	}

	events, unsub := srv.Eng.Bus().Subscribe()
	defer unsub()
	done := make(chan struct{})
	defer close(done)
	go func() {
		for {
			select {
			case batch, ok := <-events:
				if !ok {
					return
				}
				b, err := json.Marshal(map[string]any{"event": batch})
				if err == nil {
					write(b)
				}
			case <-done:
				return
			}
		}
	}()

	for {
		line, err := r.ReadBytes('\n')
		if len(line) > 1 {
			// Calls run concurrently so long operations (ping, sync) never
			// block state queries.
			go func(l []byte) { write(srv.Handle(l)) }(append([]byte(nil), line...))
		}
		if err != nil {
			return
		}
	}
}
