package auth

import (
	"strings"
	"testing"
)

func TestValidBio(t *testing.T) {
	for in, want := range map[string]string{
		"":                             "",
		"   ":                          "",
		"  Hi there  ":                 "Hi there",
		"one\r\ntwo\rthree":            "one\ntwo\nthree",
		"a  \n\n\n\nb":                 "a\n\nb",
		"tab\there":                    "tab here",
		"bell\a and  line sep":         "bell and line sep",
		"\n\nfirst\n":                  "first",
		strings.Repeat("ä", MaxBioLen): strings.Repeat("ä", MaxBioLen),
	} {
		got, ok := ValidBio(in)
		if !ok || got != want {
			t.Errorf("ValidBio(%q) = %q, %v; want %q", in, got, ok, want)
		}
	}
	for _, in := range []string{
		strings.Repeat("ä", MaxBioLen+1),
		strings.Repeat("x\n", MaxBioLines) + "x", // seven lines
	} {
		if _, ok := ValidBio(in); ok {
			t.Errorf("ValidBio(%q) passed", in)
		}
	}
	// blank lines do not count against the limit once collapsed
	if _, ok := ValidBio("a\n\n\n\n\n\n\n\nb"); !ok {
		t.Error("collapsed blank lines must pass")
	}
}
