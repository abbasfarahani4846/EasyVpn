//go:build linux

package adapter

import (
	"context"
	"encoding/binary"
	"io"
	"net"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"
	"unsafe"

	"github.com/vishvananda/netlink"
	"golang.org/x/sys/unix"

	"easyvpn/core/pkg/protocol"
	"easyvpn/core/pkg/router"
)

// newTUN creates a real kernel TUN device, exactly what Android's
// VpnService.Builder.establish() hands to the core as a file descriptor.
func newTUN(t *testing.T, name string) int {
	t.Helper()
	fd, err := unix.Open("/dev/net/tun", unix.O_RDWR|unix.O_CLOEXEC, 0)
	if err != nil {
		t.Skipf("no /dev/net/tun: %v", err)
	}
	var ifr [unix.IFNAMSIZ + 64]byte
	copy(ifr[:], name)
	*(*uint16)(unsafe.Pointer(&ifr[unix.IFNAMSIZ])) = unix.IFF_TUN | unix.IFF_NO_PI
	if _, _, e := unix.Syscall(unix.SYS_IOCTL, uintptr(fd), uintptr(unix.TUNSETIFF), uintptr(unsafe.Pointer(&ifr[0]))); e != 0 {
		unix.Close(fd)
		t.Skipf("TUNSETIFF (need root/CAP_NET_ADMIN): %v", e)
	}
	return fd
}

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

// TestTUNFileDescriptorCarriesTCP is the Android path on Linux: a host-created
// TUN fd is passed via StartRequest.Tun.FD, the in-process gVisor stack serves
// it, and a plain TCP/HTTP request routed into the TUN reaches the upstream.
func TestTUNFileDescriptorCarriesTCP(t *testing.T) {
	if os.Geteuid() != 0 {
		t.Skip("needs root")
	}
	echo, closeEcho := startEchoServer(t)
	defer closeEcho()
	socks := startAnySOCKS(t, strings.TrimPrefix(echo, "http://"))

	fd := newTUN(t, "evtest0")
	link, err := netlink.LinkByName("evtest0")
	if err != nil {
		t.Fatal(err)
	}
	addr, _ := netlink.ParseAddr("172.19.0.1/30")
	if err := netlink.AddrAdd(link, addr); err != nil {
		t.Fatal(err)
	}
	_ = netlink.LinkSetMTU(link, 1500)
	if err := netlink.LinkSetUp(link); err != nil {
		t.Fatal(err)
	}
	_, dst, _ := net.ParseCIDR("198.18.77.0/24")
	if err := netlink.RouteAdd(&netlink.Route{LinkIndex: link.Attrs().Index, Dst: dst}); err != nil {
		t.Fatal(err)
	}

	host, port := splitHostPort(t, socks)
	node := &protocol.ProxyNode{Name: "any-socks", Type: protocol.ProtoSocks, Server: host, Port: port}
	a := NewSingBoxAdapter()
	err = a.Start(context.Background(), &StartRequest{
		Node:     node,
		Mode:     ModeTUN,
		Routing:  router.Model{Mode: router.ModeGlobalProxy, LogLevel: "warn"},
		LogLevel: "warn",
		CacheDir: t.TempDir(),
		Tun:      TunSettings{FD: fd, MTU: 1500},
	})
	if err != nil {
		t.Fatalf("start with tun fd: %v", err)
	}
	defer func() { _ = a.Stop(context.Background()) }()

	cl := &http.Client{Timeout: 8 * time.Second}
	resp, err := cl.Get("http://198.18.77.9/generate_204")
	if err != nil {
		t.Fatalf("request through TUN failed: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("status %d", resp.StatusCode)
	}
}

// TUN + Xray-only node (xhttp stream-up + padding obfs, as the user's
// provider) with the sidecar dialing through sing-box's bypass inbound: the
// exact wiring the engine uses in Tunnel mode on every platform.
func TestTUNWithXraySidecarBypass(t *testing.T) {
	if os.Geteuid() != 0 {
		t.Skip("needs root")
	}
	echo, closeEcho := startEchoServer(t)
	defer closeEcho()
	cert, key := selfSigned(t)
	xhttp := map[string]any{"mode": "stream-up", "path": "/", "host": "myket.ir",
		"extra": map[string]any{"xPaddingBytes": "100-1000", "xPaddingObfsMode": true}}
	port := freePort(t)
	srvCfg := map[string]any{
		"log": map[string]any{"loglevel": "warning"},
		"inbounds": []any{map[string]any{"listen": "127.0.0.1", "port": port, "protocol": "vless",
			"settings": map[string]any{"clients": []any{map[string]any{"id": "b831381d-6324-4d53-ad4f-8cda48b30811"}}, "decryption": "none"},
			"streamSettings": map[string]any{"network": "xhttp", "security": "tls", "xhttpSettings": xhttp,
				"tlsSettings": map[string]any{"certificates": []any{map[string]any{"certificateFile": cert, "keyFile": key}}}}}},
		// the "internet" of the test: everything lands on the echo server
		"outbounds": []any{map[string]any{"protocol": "freedom", "settings": map[string]any{"redirect": strings.TrimPrefix(echo, "http://")}}},
	}
	stopSrv := startXrayConfig(t, srvCfg)
	defer stopSrv()
	time.Sleep(300 * time.Millisecond)

	node := importXrayJSON(t, map[string]any{"protocol": "vless", "tag": "proxy",
		"settings": map[string]any{"vnext": []any{map[string]any{"address": "127.0.0.1", "port": port,
			"users": []any{map[string]any{"id": "b831381d-6324-4d53-ad4f-8cda48b30811", "encryption": "none"}}}}},
		"streamSettings": map[string]any{"network": "xhttp", "security": "tls",
			"tlsSettings": map[string]any{"serverName": "localhost", "allowInsecure": true}, "xhttpSettings": xhttp}})

	fd := newTUN(t, "evtest1")
	link, err := netlink.LinkByName("evtest1")
	if err != nil {
		t.Fatal(err)
	}
	addr, _ := netlink.ParseAddr("172.19.0.5/30")
	_ = netlink.AddrAdd(link, addr)
	_ = netlink.LinkSetUp(link)
	_, dst, _ := net.ParseCIDR("198.18.78.0/24")
	if err := netlink.RouteAdd(&netlink.Route{LinkIndex: link.Attrs().Index, Dst: dst}); err != nil {
		t.Fatal(err)
	}

	bp := freePort(t)
	sc, err := StartXraySidecarWith(node, SidecarOptions{BypassPort: bp})
	if err != nil {
		t.Fatal(err)
	}
	defer sc.Close()
	a := NewSingBoxAdapter()
	if err := a.Start(context.Background(), &StartRequest{
		Node: sc.Node(), Mode: ModeTUN, Routing: router.Model{Mode: router.ModeGlobalProxy, LogLevel: "warn"},
		CacheDir: t.TempDir(), Tun: TunSettings{FD: fd, MTU: 1500}, XrayBypassPort: bp,
	}); err != nil {
		t.Fatal(err)
	}
	defer a.Stop(context.Background())
	cl := &http.Client{Timeout: 8 * time.Second}
	resp, err := cl.Get("http://198.18.78.9/generate_204")
	if err != nil {
		t.Fatalf("TUN -> sing-box -> xray(xhttp obfs) -> bypass -> server failed: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("status %d", resp.StatusCode)
	}
}
