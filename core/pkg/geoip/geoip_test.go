package geoip

import "testing"

func TestDetectPriority(t *testing.T) {
	cases := []struct {
		s    Signals
		want string
		src  string
	}{
		{Signals{SIMCountry: "IR", Locale: "en_US"}, "ir", "sim"},
		{Signals{Locale: "fa_IR"}, "ir", "locale"},
		{Signals{Locale: "en", Timezone: "Asia/Tehran"}, "ir", "timezone"},
		{Signals{Locale: "fa"}, "ir", "language"},
		{Signals{Locale: "en"}, "", "none"},
	}
	for _, c := range cases {
		r := Detect(c.s)
		if r.Country != c.want || r.Source != c.src {
			t.Errorf("%+v => %+v", c.s, r)
		}
	}
}
