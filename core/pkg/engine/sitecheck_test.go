package engine

import "testing"

func TestClassifySiteAnswers(t *testing.T) {
	gem := Site{Name: "Gemini", Blocked: []string{"isn't supported in your country"}}
	api := Site{Name: "API", OKStatus: []int{401}, Blocked: []string{"unsupported_country"}}
	cases := []struct {
		s      Site
		status int
		body   string
		want   string
	}{
		{gem, 200, "<html>Gemini</html>", "ok"},
		{gem, 200, "Gemini isn't supported in your country yet", "blocked"},
		{api, 401, `{"error":"missing key"}`, "ok"},
		{api, 403, `{"error":{"code":"unsupported_country_region_territory"}}`, "blocked"},
		{Site{}, 451, "", "blocked"},
		{Site{}, 403, "", "blocked"},
		{Site{}, 302, "", "ok"},
		{Site{}, 502, "", "error"},
	}
	for _, c := range cases {
		if got, _ := classify(c.s, c.status, []byte(c.body)); got != c.want {
			t.Errorf("%s %d %q: got %s want %s", c.s.Name, c.status, c.body, got, c.want)
		}
	}
}
