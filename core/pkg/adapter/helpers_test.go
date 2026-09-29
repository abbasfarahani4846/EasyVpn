package adapter

import (
	"context"

	"easyvpn/core/pkg/router"

	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	singjson "github.com/sagernet/sing/common/json"
)

func routerDefault() router.Model { return router.Default() }

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
