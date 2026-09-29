package stats

import (
	"sync/atomic"
	"time"
)

type Snapshot struct {
	UploadSpeed   int64 `json:"upload_speed"`   // Bytes per second
	DownloadSpeed int64 `json:"download_speed"` // Bytes per second
	TotalUpload   int64 `json:"total_upload"`   // Total bytes
	TotalDownload int64 `json:"total_download"` // Total bytes
	Connections   int32 `json:"connections"`    // Active connections
}

type Tracker struct {
	totalUp       atomic.Int64
	totalDown     atomic.Int64
	lastUp        int64
	lastDown      int64
	uploadSpeed   atomic.Int64
	downloadSpeed atomic.Int64
	activeConns   atomic.Int32
	lastSample    time.Time
	stopChan      chan struct{}
}

func NewTracker() *Tracker {
	t := &Tracker{
		lastSample: time.Now(),
		stopChan:   make(chan struct{}),
	}
	go t.samplerLoop()
	return t
}

func (t *Tracker) AddUpload(bytes int64) {
	t.totalUp.Add(bytes)
}

func (t *Tracker) AddDownload(bytes int64) {
	t.totalDown.Add(bytes)
}

func (t *Tracker) ConnOpened() {
	t.activeConns.Add(1)
}

func (t *Tracker) ConnClosed() {
	t.activeConns.Add(-1)
}

func (t *Tracker) GetSnapshot() Snapshot {
	return Snapshot{
		UploadSpeed:   t.uploadSpeed.Load(),
		DownloadSpeed: t.downloadSpeed.Load(),
		TotalUpload:   t.totalUp.Load(),
		TotalDownload: t.totalDown.Load(),
		Connections:   t.activeConns.Load(),
	}
}

func (t *Tracker) samplerLoop() {
	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-t.stopChan:
			return
		case now := <-ticker.C:
			curUp := t.totalUp.Load()
			curDown := t.totalDown.Load()

			deltaSec := now.Sub(t.lastSample).Seconds()
			if deltaSec <= 0 {
				deltaSec = 1
			}

			upSpeed := int64(float64(curUp-t.lastUp) / deltaSec)
			downSpeed := int64(float64(curDown-t.lastDown) / deltaSec)

			if upSpeed < 0 {
				upSpeed = 0
			}
			if downSpeed < 0 {
				downSpeed = 0
			}

			t.uploadSpeed.Store(upSpeed)
			t.downloadSpeed.Store(downSpeed)

			t.lastUp = curUp
			t.lastDown = curDown
			t.lastSample = now
		}
	}
}

func (t *Tracker) Close() {
	select {
	case <-t.stopChan:
	default:
		close(t.stopChan)
	}
}
