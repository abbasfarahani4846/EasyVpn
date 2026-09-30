package adapter

import (
	"fmt"
	"reflect"

	"easyvpn/core/pkg/protocol"

	"github.com/sagernet/sing-box/option"
)

// Chains ("proxy in proxy"): the hops in StartRequest.Chain are dialed before the
// active node, in order:
//
//	app -> Chain[0] -> Chain[1] -> ... -> active node -> internet
//
// Each hop's outbound gets `detour` = previous hop, and every materialized node
// gets `detour` = last hop. This covers "exit via WARP" (Chain=[proxy],
// node=WARP), "WARP in WARP" (Chain=[WARP-A], node=WARP-B), SSH -> VLESS, etc.

// chainTagPrefix is the tag prefix of chain hop outbounds.
const chainTagPrefix = "chain-"

// buildChain compiles the hops and returns them plus the tag of the last hop
// ("" when there is no chain).
func buildChain(hops []*protocol.ProxyNode, tricks TLSTricks) ([]option.Outbound, []option.Endpoint, string, error) {
	var obs []option.Outbound
	var eps []option.Endpoint
	prev := ""
	for i, h := range hops {
		if h == nil {
			continue
		}
		if NeedsXray(h) {
			return nil, nil, "", fmt.Errorf("chain hop %d (%s): Xray-only nodes can only be the last (active) node of a chain", i+1, h.Name)
		}
		tag := fmt.Sprintf("%s%d", chainTagPrefix, i)
		built, err := buildNode(applyTricks(h, tricks), tag)
		if err != nil {
			return nil, nil, "", fmt.Errorf("chain hop %d (%s): %w", i+1, h.Name, err)
		}
		if prev != "" {
			if built.Outbound != nil {
				setDetour(built.Outbound.Options, prev)
			} else {
				setDetour(built.Endpoint.Options, prev)
			}
		}
		if built.Outbound != nil {
			obs = append(obs, *built.Outbound)
		} else {
			eps = append(eps, *built.Endpoint)
		}
		prev = tag
	}
	return obs, eps, prev, nil
}

// setDetour sets DialerOptions.Detour on any sing-box outbound/endpoint options
// struct (they all embed option.DialerOptions). Returns false if the type has
// no dialer (e.g. selector), which is never the case for proxy nodes.
func setDetour(opts any, tag string) bool {
	v := reflect.ValueOf(opts)
	for v.Kind() == reflect.Pointer || v.Kind() == reflect.Interface {
		if v.IsNil() {
			return false
		}
		v = v.Elem()
	}
	if v.Kind() != reflect.Struct {
		return false
	}
	return setDetourValue(v, tag)
}

var dialerOptionsType = reflect.TypeOf(option.DialerOptions{})

func setDetourValue(v reflect.Value, tag string) bool {
	for i := 0; i < v.NumField(); i++ {
		f := v.Field(i)
		ft := v.Type().Field(i)
		if ft.Type == dialerOptionsType && f.CanSet() {
			d := f.Addr().Interface().(*option.DialerOptions)
			d.Detour = tag
			return true
		}
		if ft.Anonymous && f.Kind() == reflect.Struct && setDetourValue(f, tag) {
			return true
		}
	}
	return false
}
