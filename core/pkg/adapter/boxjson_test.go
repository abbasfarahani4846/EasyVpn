package adapter

import (
	"context"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	singjson "github.com/sagernet/sing/common/json"
)

// optionsJSON is a tiny wrapper used by tests that build configs as JSON.
type optionsJSON struct {
	raw []byte
}

// newBoxFromJSON parses a sing-box JSON config with the full protocol
// registry in context and returns a ready-to-start box.
func newBoxFromJSON(cfg []byte) (*box.Box, error) {
	ctx := include.Context(context.Background())
	var opts option.Options
	if err := singjson.UnmarshalContext(ctx, cfg, &opts); err != nil {
		return nil, err
	}
	return box.New(box.Options{Context: ctx, Options: opts})
}
