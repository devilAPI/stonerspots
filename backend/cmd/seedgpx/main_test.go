package main

import (
	"reflect"
	"testing"
)

func TestInferTags(t *testing.T) {
	cases := []struct {
		in   string
		want []string
	}{
		{"", []string{}},
		{"Wiese am Rand", []string{}},
		{"Überdachte Bank", []string{"roof", "seating"}},
		{"Ueberdachter Platz", []string{"roof"}},
		{"Kleine HÜTTE im Wald", []string{"roof"}},
		{"Unterführung", []string{"roof"}},
		{"Pavillon im Park", []string{"roof"}},
		{"Glashaus", []string{"roof"}},
		{"Container am Fluss", []string{"roof", "water"}},
		{"Sitzgelegenheit", []string{"seating"}},
		{"Bänke", []string{"seating"}},
		{"Tolle Aussicht", []string{"view"}},
		{"Blick auf die Stadt", []string{"view"}},
		{"ruhig und chill", []string{"quiet"}},
		{"Teich", []string{"water"}},
		{"am See", []string{"water"}},
		{"Seeufer", []string{}}, // see\b: "see" must end the word
		{"Brunnen und Bach", []string{"water"}},
		{"Dach mit Blick, ruhig, am Weiher, Bank", []string{"roof", "seating", "view", "quiet", "water"}},
	}
	for _, c := range cases {
		got := inferTags(c.in)
		if !reflect.DeepEqual(got, c.want) {
			t.Errorf("inferTags(%q) = %v, want %v", c.in, got, c.want)
		}
	}
}
