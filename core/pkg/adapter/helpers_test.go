package adapter

import (
	"context"
	"encoding/binary"
	"io"
	"net"
	"testing"

	"easyvpn/core/pkg/router"

	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	singjson "github.com/sagernet/sing/common/json"
)

func routerDefault() router.Model { return router.Default() }

// startAnySOCKS is a SOCKS5 server that ignores the requested destination and
// always connects to target, so packets sent to a fake address end up at the
// hermetic echo server.
func startAnySOCKS(t *testing.T, target string) string {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go func(c net.Conn) {
				defer c.Close()
				buf := make([]byte, 262)
				if _, err := io.ReadFull(c, buf[:2]); err != nil {
					return
				}
				if _, err := io.ReadFull(c, buf[:int(buf[1])]); err != nil {
					return
				}
				c.Write([]byte{5, 0})
				if _, err := io.ReadFull(c, buf[:4]); err != nil {
					return
				}
				switch buf[3] {
				case 1:
					io.ReadFull(c, buf[:6])
				case 4:
					io.ReadFull(c, buf[:18])
				case 3:
					io.ReadFull(c, buf[:1])
					io.ReadFull(c, buf[:int(buf[0])+2])
				}
				up, err := net.Dial("tcp", target)
				if err != nil {
					c.Write([]byte{5, 5, 0, 1, 0, 0, 0, 0, 0, 0})
					return
				}
				defer up.Close()
				reply := []byte{5, 0, 0, 1, 0, 0, 0, 0, 0, 0}
				binary.BigEndian.PutUint16(reply[8:], 0)
				c.Write(reply)
				go io.Copy(up, c)
				io.Copy(c, up)
			}(c)
		}
	}()
	return ln.Addr().String()
}

// decodeOptionsStrict round-trips options through sing-box's own strict JSON
// decoder (with the full protocol registry in context), catching schema
// drift between our builder and the engine.
func decodeOptionsStrict(b []byte) (*option.Options, error) {
	ctx := include.Context(context.Background())
	var opts option.Options
	if err := singjson.UnmarshalContext(ctx, b, &opts); err != nil {
		return nil, err
	}
	return &opts, nil
}

func routerGlobal() router.Model {
	return router.Model{Mode: router.ModeGlobalProxy, LogLevel: "warn"}
}
