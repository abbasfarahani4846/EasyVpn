// Package transport provides the non-blocking event delivery pipeline from
// the Go core to Dart: two bounded queues (priority + bulk) with batched
// flushing, mirroring the FlClash-proven design. Core work NEVER blocks on
// event delivery — a full queue evicts its own oldest event.
package transport

import (
	"sync"
	"time"
)

// EventKind classifies events by delivery queue.
type EventKind int

const (
	// KindPriority: state changes, delay results, rule-sync status.
	KindPriority EventKind = iota
	// KindBulk: logs, traffic stats — high volume, droppable.
	KindBulk
)

// Event is a single message pushed toward Dart.
type Event struct {
	Kind      EventKind `json:"-"`
	Type      string    `json:"type"` // state|stats|delay|log|ruleSync|crash
	Payload   any       `json:"payload,omitempty"`
	Timestamp int64     `json:"ts"` // unix millis
}

// Bus buffers and batches events toward the UI.
type Bus struct {
	mu       sync.Mutex
	priority []Event
	bulk     []Event
	capacity int

	subMu       sync.RWMutex
	subscribers map[int]chan []Event
	nextSubID   int

	flushInterval time.Duration
	batchSize     int
	stopCh        chan struct{}
	stopOnce      sync.Once
}

const (
	defaultCapacity     = 256
	defaultBatchSize    = 32
	defaultFlushEveryMS = 16
)

// NewBus starts a batched event bus.
func NewBus() *Bus {
	b := &Bus{
		capacity:      defaultCapacity,
		subscribers:   make(map[int]chan []Event),
		flushInterval: defaultFlushEveryMS * time.Millisecond,
		batchSize:     defaultBatchSize,
		stopCh:        make(chan struct{}),
	}
	go b.loop()
	return b
}

// Publish enqueues an event without ever blocking the caller.
func (b *Bus) Publish(kind EventKind, typ string, payload any) {
	ev := Event{Kind: kind, Type: typ, Payload: payload, Timestamp: time.Now().UnixMilli()}
	b.mu.Lock()
	defer b.mu.Unlock()
	switch kind {
	case KindPriority:
		b.priority = append(b.priority, ev)
		if len(b.priority) > b.capacity {
			b.priority = b.priority[1:] // evict oldest
		}
	default:
		b.bulk = append(b.bulk, ev)
		if len(b.bulk) > b.capacity {
			b.bulk = b.bulk[1:]
		}
	}
}

// Subscribe returns a channel receiving batches of events.
func (b *Bus) Subscribe() (<-chan []Event, func()) {
	b.subMu.Lock()
	defer b.subMu.Unlock()
	id := b.nextSubID
	b.nextSubID++
	ch := make(chan []Event, 16)
	b.subscribers[id] = ch
	unsub := func() {
		b.subMu.Lock()
		defer b.subMu.Unlock()
		if c, ok := b.subscribers[id]; ok {
			delete(b.subscribers, id)
			close(c)
		}
	}
	return ch, unsub
}

// Close stops the bus after flushing pending events.
func (b *Bus) Close() {
	b.stopOnce.Do(func() { close(b.stopCh) })
}

func (b *Bus) loop() {
	ticker := time.NewTicker(b.flushInterval)
	defer ticker.Stop()
	for {
		select {
		case <-b.stopCh:
			b.flush(true)
			return
		case <-ticker.C:
			b.flush(false)
		}
	}
}

// flush drains queues preferring priority events, with a starvation guard:
// after 8 priority events one bulk batch is guaranteed.
func (b *Bus) flush(force bool) {
	b.mu.Lock()
	var batch []Event
	prioCount := 0
	for len(b.priority) > 0 && (len(batch) < b.batchSize || prioCount < 8) {
		batch = append(batch, b.priority[0])
		b.priority = b.priority[1:]
		prioCount++
		if prioCount == 8 && len(b.bulk) > 0 && len(batch) < b.batchSize {
			batch = append(batch, b.bulk[0])
			b.bulk = b.bulk[1:]
		}
	}
	for len(batch) < b.batchSize && len(b.bulk) > 0 {
		batch = append(batch, b.bulk[0])
		b.bulk = b.bulk[1:]
	}
	if force {
		for len(b.priority) > 0 {
			batch = append(batch, b.priority[0])
			b.priority = b.priority[1:]
		}
		for len(b.bulk) > 0 {
			batch = append(batch, b.bulk[0])
			b.bulk = b.bulk[1:]
		}
	}
	b.mu.Unlock()

	if len(batch) == 0 {
		return
	}
	b.subMu.RLock()
	defer b.subMu.RUnlock()
	for _, ch := range b.subscribers {
		select {
		case ch <- batch:
		default: // slow subscriber: drop the batch rather than block core
		}
	}
}
