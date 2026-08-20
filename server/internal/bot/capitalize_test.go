package bot

import (
	"testing"
	"unicode/utf8"
)

func TestCapitalizeFirst(t *testing.T) {
	tests := []struct{ in, want string }{
		{"books", "Books"},
		{"такси", "Такси"}, // multi-byte first rune must not be byte-sliced
		{"éclair", "Éclair"},
		{"寿司", "寿司"}, // no upper-case form: unchanged
		{"x", "X"},
		{"", ""},
	}
	for _, tt := range tests {
		got := capitalizeFirst(tt.in)
		if got != tt.want {
			t.Errorf("capitalizeFirst(%q) = %q, want %q", tt.in, got, tt.want)
		}
		if !utf8.ValidString(got) {
			t.Errorf("capitalizeFirst(%q) produced invalid UTF-8: %q", tt.in, got)
		}
	}
}
