// Package textmatch ranks names against what someone typed into a search:
// case and accents do not matter, words may come in any order, a word may
// be the start or the end of a compound ("park" finds "Stadtpark" and
// "Parkbank"), and small typos are forgiven.
package textmatch

import (
	"strings"
	"unicode"
)

// Tiers, best first. A result's tier decides its place before anything
// else; within a tier callers order by distance or Score.
const (
	TierExact = iota // the whole name, as typed
	TierWords        // each word typed is a word of the name, its start or its end
	TierLoose        // somewhere inside a word, or with a typo
	TierExtra        // only in the extra text (e.g. a description)
)

var fold = map[rune]string{
	'ß': "ss", 'æ': "ae", 'œ': "oe", 'ø': "o", 'ł': "l", 'đ': "d", 'ð': "d", 'þ': "th",
}

// base maps accented Latin letters to their plain letter.
var base = func() map[rune]rune {
	m := map[rune]rune{}
	for plain, accented := range map[rune]string{
		'a': "àáâãäåāăą", 'c': "çćĉċč", 'd': "ď", 'e': "èéêëēĕėęě",
		'g': "ĝğġģ", 'h': "ĥħ", 'i': "ìíîïĩīĭįı", 'j': "ĵ", 'k': "ķ",
		'l': "ĺļľŀ", 'n': "ñńņňŉ", 'o': "òóôõöōŏő", 'r': "ŕŗř",
		's': "śŝşšș", 't': "ţťŧț", 'u': "ùúûüũūŭůűų", 'w': "ŵ",
		'y': "ýÿŷ", 'z': "źżž",
	} {
		for _, r := range accented {
			m[r] = plain
		}
	}
	return m
}()

// Fold lower-cases s, takes accents off, and turns everything that is not
// a letter or digit into a space.
func Fold(s string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(s) {
		switch {
		case fold[r] != "":
			b.WriteString(fold[r])
		case base[r] != 0:
			b.WriteRune(base[r])
		case unicode.IsLetter(r) || unicode.IsDigit(r):
			b.WriteRune(r)
		default:
			b.WriteByte(' ')
		}
	}
	return b.String()
}

// Words is the folded words of s.
func Words(s string) []string { return strings.Fields(Fold(s)) }

// Query is what was typed, ready to match against many names.
type Query struct {
	phrase string   // folded words joined by one space
	words  []string // all words
	// required words must match; short ones ("am", "zu") only add to the
	// score, unless every word is short
	required []bool
}

// NewQuery prepares q.
func NewQuery(q string) Query {
	words := Words(q)
	long := 0
	for _, w := range words {
		if runes(w) >= 3 {
			long++
		}
	}
	req := make([]bool, len(words))
	for i, w := range words {
		req[i] = long == 0 || runes(w) >= 3
	}
	return Query{phrase: strings.Join(words, " "), words: words, required: req}
}

// Empty reports a query without any letter or digit.
func (q Query) Empty() bool { return len(q.words) == 0 }

func runes(s string) int { return len([]rune(s)) }

// kind of a word match, best first; 0 means none
const (
	none = iota
	loose
	strong
)

// wordMatch scores one typed word against the words of a name (and the
// name without spaces, for "park bank" typed as "parkbank").
func wordMatch(tok string, words []string, joined string, fuzzy bool) (int, float64) {
	n := runes(tok)
	kind, best := none, 0.0
	take := func(k int, s float64) {
		if k > kind || (k == kind && s > best) {
			kind, best = k, s
		}
	}
	for _, w := range words {
		m := runes(w)
		switch {
		case w == tok:
			take(strong, 1)
		case strings.HasPrefix(w, tok):
			take(strong, 0.85+0.15*float64(n)/float64(m))
		case n >= 3 && strings.HasSuffix(w, tok):
			take(strong, 0.75+0.1*float64(n)/float64(m))
		case n >= 3 && strings.Contains(w, tok):
			take(loose, 0.7)
		case fuzzy && n >= 4 && m+maxTypos(n) >= n: // shorter words cannot be near
			if d := typos(tok, w); d <= maxTypos(n) {
				take(loose, 0.65-0.15*float64(d))
			}
		}
	}
	if kind == none && n >= 3 && strings.Contains(joined, tok) {
		take(strong, 0.8)
	}
	return kind, best
}

func maxTypos(n int) int {
	if n >= 8 {
		return 2
	}
	return 1
}

// typos is the fewest edits (insert, delete, change, swap two neighbours)
// that turn tok into w or into the start of w.
func typos(tok, w string) int {
	a, b := []rune(tok), []rune(w)
	best := osa(a, b)
	for l := len(a) - 1; l <= len(a)+1; l++ {
		if l > 0 && l < len(b) {
			best = min(best, osa(a, b[:l]))
		}
	}
	return best
}

// osa is the optimal string alignment distance of a and b.
func osa(a, b []rune) int {
	prev2 := make([]int, len(b)+1)
	prev := make([]int, len(b)+1)
	cur := make([]int, len(b)+1)
	for j := range prev {
		prev[j] = j
	}
	for i := 1; i <= len(a); i++ {
		cur[0] = i
		for j := 1; j <= len(b); j++ {
			cost := 1
			if a[i-1] == b[j-1] {
				cost = 0
			}
			cur[j] = min(prev[j]+1, cur[j-1]+1, prev[j-1]+cost)
			if i > 1 && j > 1 && a[i-1] == b[j-2] && a[i-2] == b[j-1] {
				cur[j] = min(cur[j], prev2[j-2]+1)
			}
		}
		prev2, prev, cur = prev, cur, prev2
	}
	return prev[len(b)]
}

// Match rates name (and, weaker, extra) for q. ok is false when a required
// word is found in neither. Within a tier a higher score is a better match.
func (q Query) Match(name, extra string) (tier int, score float64, ok bool) {
	if q.Empty() {
		return 0, 0, false
	}
	nw := Words(name)
	joined := strings.Join(nw, "")
	var ew []string
	tier = TierWords
	matched := 0
	for i, tok := range q.words {
		kind, s := wordMatch(tok, nw, joined, true)
		if kind == none && extra != "" {
			if ew == nil {
				ew = Words(extra)
			}
			if k, es := wordMatch(tok, ew, "", false); k != none {
				kind, s = loose, 0.4*es
				if q.required[i] {
					tier = TierExtra
				}
			}
		}
		if kind == none {
			if q.required[i] {
				return 0, 0, false
			}
			continue
		}
		if kind == loose && q.required[i] && tier < TierLoose {
			tier = TierLoose
		}
		matched++
		if q.required[i] {
			score += s
		} else {
			score += 0.1 * s
		}
	}
	if matched == 0 {
		return 0, 0, false
	}
	score /= float64(len(q.words))
	phrase := strings.Join(nw, " ")
	switch {
	case phrase == q.phrase:
		tier, score = TierExact, score+1
	case strings.HasPrefix(phrase, q.phrase):
		score += 0.5
	case strings.Contains(phrase, q.phrase):
		score += 0.25
	}
	// of two names that match alike, the shorter fits better
	score += 0.2 * min(1, float64(len(q.words))/float64(max(1, len(nw))))
	return tier, score, true
}
