package engine

import (
	"errors"
	"net"
	"sync"
	"testing"
	"time"

	"easyvpn/core/pkg/protocol"
)

// "Cancel" while connecting: Stop racing Start must always end disconnected
// (never a zombie "connected" session with a listening port).
func TestStopCancelsStartInProgress(t *testing.T) {
	e := NewEngine(t.TempDir())
	node := &protocol.ProxyNode{Name: "up", Type: protocol.ProtoSocks, Server: "127.0.0.1", Port: startSocks(t)}
	for i := 0; i < 15; i++ {
		var wg sync.WaitGroup
		var startErr error
		wg.Add(1)
		go func() {
			defer wg.Done()
			startErr = e.Start(StartParams{Node: node, Mode: "proxy_only", LocalPort: 26570})
		}()
		time.Sleep(time.Duration(i%5) * time.Millisecond)
		_ = e.Stop()
		wg.Wait()
		if startErr == nil {
			// Start won the race: a later Stop must still bring it down.
			_ = e.Stop()
		} else if !errors.Is(startErr, ErrCancelled) && e.GetState() != StateDisconnected {
			t.Logf("start: %v", startErr)
		}
		if st := e.GetState(); st != StateDisconnected {
			t.Fatalf("iteration %d: state %v after cancel", i, st)
		}
		if c, err := net.DialTimeout("tcp", "127.0.0.1:26570", 200*time.Millisecond); err == nil {
			c.Close()
			t.Fatalf("iteration %d: local port still listening after cancel", i)
		}
	}
}
