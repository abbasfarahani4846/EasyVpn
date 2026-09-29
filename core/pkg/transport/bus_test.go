package transport

import (
	"testing"
	"time"
)

func TestBusBatchingAndPriority(t *testing.T) {
	b := NewBus()
	defer b.Close()
	ch, unsub := b.Subscribe()
	defer unsub()

	// Priority events must flow.
	b.Publish(KindPriority, "state", map[string]string{"state": "connected"})
	select {
	case batch := <-ch:
		if len(batch) == 0 || batch[0].Type != "state" {
			t.Fatalf("expected state event first, got %+v", batch)
		}
	case <-time.After(2 * time.Second):
		t.Fatalf("timed out waiting for priority event")
	}
}

func TestBusBulkFlow(t *testing.T) {
	b := NewBus()
	defer b.Close()
	ch, unsub := b.Subscribe()
	defer unsub()

	for i := 0; i < 40; i++ {
		b.Publish(KindBulk, "log", map[string]string{"msg": "x"})
	}
	got := 0
	deadline := time.After(3 * time.Second)
	for got < 40 {
		select {
		case batch := <-ch:
			got += len(batch)
		case <-deadline:
			t.Fatalf("only received %d/40 bulk events", got)
		}
	}
}

func TestBusNeverBlocksWhenNoSubscriber(t *testing.T) {
	b := NewBus()
	defer b.Close()
	done := make(chan struct{})
	go func() {
		defer close(done)
		for i := 0; i < 5000; i++ {
			b.Publish(KindBulk, "log", i)
		}
	}()
	select {
	case <-done:
	case <-time.After(3 * time.Second):
		t.Fatalf("publish blocked with no subscriber")
	}
}
