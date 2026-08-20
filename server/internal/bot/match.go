package bot

import (
	"strings"

	"github.com/xensa/tally/internal/model"
)

// namedCategory pairs a category with every name it answers to: its stored
// (canonical English) name plus, for an unrenamed seed category, its localized
// name in each supported language.
//
// Matching against all of them is what makes "продукты" and "groceries" both
// resolve to Groceries regardless of which language the reply is written in
// (docs/ARCHITECTURE.md § Message grammar).
type namedCategory struct {
	Cat   model.Category
	Names []string
}

// maxDist is a sentinel larger than any realistic edit distance.
const maxDist = 1 << 30

// matchCategory finds a confident match for word among cands (already filtered
// to non-deleted categories of the right kind), in order:
// exact name → unique prefix → unique fuzzy (Levenshtein ≤ 2).
// The alias table is checked by the caller before this. Returns nil when there
// is no confident match.
//
// Ambiguity is resolved per CATEGORY, not per name: a category matching on two
// of its own translations is still one candidate, while two different
// categories matching is a tie and yields nil so the user gets the keyboard.
func matchCategory(word string, cands []namedCategory) *model.Category {
	w := strings.ToLower(strings.TrimSpace(word))
	if w == "" {
		return nil
	}

	// 1. exact (case-insensitive), in any supported language
	for i := range cands {
		for _, n := range cands[i].Names {
			if strings.ToLower(n) == w {
				return &cands[i].Cat
			}
		}
	}

	// 2. unique name prefix
	var prefixHit *model.Category
	prefixCount := 0
	for i := range cands {
		for _, n := range cands[i].Names {
			if strings.HasPrefix(strings.ToLower(n), w) {
				prefixHit = &cands[i].Cat
				prefixCount++
				break
			}
		}
	}
	if prefixCount == 1 {
		return prefixHit
	}
	if prefixCount > 1 {
		return nil // ambiguous
	}

	// 3. unique fuzzy match with distance ≤ 2
	best, bestDist, bestCount := (*model.Category)(nil), 3, 0
	for i := range cands {
		// A category's distance is the best its names can do.
		d := maxDist
		for _, n := range cands[i].Names {
			if x := levenshtein(w, strings.ToLower(n)); x < d {
				d = x
			}
		}
		switch {
		case d < bestDist:
			best, bestDist, bestCount = &cands[i].Cat, d, 1
		case d == bestDist:
			bestCount++
		}
	}
	if best != nil && bestDist <= 2 && bestCount == 1 {
		return best
	}
	return nil
}

// levenshtein computes the edit distance between two strings (rune-wise).
func levenshtein(a, b string) int {
	ra, rb := []rune(a), []rune(b)
	if len(ra) == 0 {
		return len(rb)
	}
	if len(rb) == 0 {
		return len(ra)
	}
	prev := make([]int, len(rb)+1)
	cur := make([]int, len(rb)+1)
	for j := 0; j <= len(rb); j++ {
		prev[j] = j
	}
	for i := 1; i <= len(ra); i++ {
		cur[0] = i
		for j := 1; j <= len(rb); j++ {
			cost := 1
			if ra[i-1] == rb[j-1] {
				cost = 0
			}
			cur[j] = min(prev[j]+1, min(cur[j-1]+1, prev[j-1]+cost))
		}
		prev, cur = cur, prev
	}
	return prev[len(rb)]
}
