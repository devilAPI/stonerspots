package textmatch

import "testing"

func TestFold(t *testing.T) {
	for in, want := range map[string]string{
		"Schöne Straße!":   "schone strasse ",
		"ÉCOLE-Œuvre":      "ecole oeuvre",
		"Park_Bank 42":     "park bank 42",
		"Łódź, Ærøskøbing": "lodz  aeroskobing",
	} {
		if got := Fold(in); got != want {
			t.Errorf("Fold(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestMatchTiers(t *testing.T) {
	cases := []struct {
		query, name, extra string
		tier               int // -1: no match
	}{
		{"park", "Park", "", TierExact},
		{"PARK", "park!", "", TierExact},
		{"schone bank", "Schöne Bank", "", TierExact},
		{"park", "Parkbank am See", "", TierWords},     // start of a word
		{"park", "Stadtpark", "", TierWords},           // end of a compound
		{"see bank", "Parkbank am See", "", TierWords}, // any order
		{"bank am see", "Parkbank am See", "", TierWords},
		{"parkbank", "Park Bank", "", TierWords},        // without the space
		{"muenchen", "München Ost", "", TierLoose},      // ue for ü: one typo
		{"parbank", "Parkbank", "", TierLoose},          // a letter missing
		{"prakbank", "Parkbank", "", TierLoose},         // two swapped
		{"stadtprak", "Stadtpark Wiese", "", TierLoose}, // swapped, long word
		{"park", "Kleinparkanlage", "", TierLoose},      // inside a word
		{"aussicht", "Bank", "Mit toller Aussicht", TierExtra},
		{"bank aussicht", "Bank", "Mit toller Aussicht", TierExtra},
		{"am see", "Bank am See", "", TierWords}, // "am" is short but matches
		{"bank xy", "Bank", "", TierWords},       // short words are optional
		{"bank wiese", "Bank", "", -1},           // long words are not
		{"xyz", "Bank", "", -1},
		{"bnk", "Bank", "", -1}, // three letters: no typo allowed
		{"bamk", "Bank", "", TierLoose},
		{"wald", "Bank", "Am Waldrand", TierExtra}, // start of a word in extra
		{"wlad", "Bank", "Am Waldrand", -1},        // no typos in extra
		{"%%", "100% Chill", "", -1},
		{"ab", "Abendrot", "", TierWords},
		{"ab", "Laberbank", "", -1}, // two letters only at a word's start or end
	}
	for _, c := range cases {
		tier, _, ok := NewQuery(c.query).Match(c.name, c.extra)
		if !ok {
			tier = -1
		}
		if tier != c.tier {
			t.Errorf("%q in %q / %q: tier %d, want %d", c.query, c.name, c.extra, tier, c.tier)
		}
	}
}

func TestMatchScoreOrder(t *testing.T) {
	// best first, all in the same tier
	q := NewQuery("park")
	names := []string{"Parkbank", "Alter Parkplatz", "Unterpark"}
	last := 10.0
	for _, n := range names {
		tier, s, ok := q.Match(n, "")
		if !ok || tier != TierWords {
			t.Fatalf("%q: tier %d ok %v", n, tier, ok)
		}
		if s >= last {
			t.Fatalf("%q scores %v, not below the one before (%v)", n, s, last)
		}
		last = s
	}
	// one typo beats two
	_, one, _ := NewQuery("stadtpaark").Match("Stadtpark", "")
	_, two, _ := NewQuery("stadtpxxrk").Match("Stadtpark", "")
	if one <= two {
		t.Fatalf("one typo %v, two typos %v", one, two)
	}
}

func TestOSA(t *testing.T) {
	for _, c := range []struct {
		a, b string
		d    int
	}{
		{"", "", 0}, {"abc", "abc", 0}, {"abc", "acb", 1}, {"abc", "ab", 1},
		{"kitten", "sitting", 3}, {"ca", "abc", 3},
	} {
		if got := osa([]rune(c.a), []rune(c.b)); got != c.d {
			t.Errorf("osa(%q, %q) = %d, want %d", c.a, c.b, got, c.d)
		}
	}
}
