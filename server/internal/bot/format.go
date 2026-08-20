package bot

import (
	"strings"
	"time"
)

// Money, numbers and dates are formatted by internal/i18n, which knows each
// locale's separators, symbol placement and month names. What is left here is
// the locale-independent chrome: the spending bar and the period boundaries.

// bar renders a simple text bar scaled against max (width up to 10 blocks,
// at least 1 for a non-zero value).
func bar(value, max int64) string {
	const width = 10
	if value <= 0 || max <= 0 {
		return ""
	}
	n := int((value*width + max/2) / max)
	if n < 1 {
		n = 1
	}
	if n > width {
		n = width
	}
	return strings.Repeat("█", n)
}

// The period helpers below build their boundaries in now's own location, and
// the caller passes a `now` already converted into the configured timezone.
//
// They must NOT force UTC. The Flutter app computes the same periods from
// LOCAL midnight (app/lib/core/dates.dart: `monthStart(d) => DateTime(d.year,
// d.month)`), converting to UTC only for the string comparison the query does.
// With UTC boundaries on a UTC+5 host — this product targets Uzbekistan
// (UTC+5) and Russia (UTC+3) — everything logged between 00:00 and 05:00
// local lands in the previous day, and at 02:00 on the 1st `/month` reports
// the whole of last month, so the bot and the app's Home screen disagree about
// identical data. The store converts these bounds back to UTC strings.

// dayRange returns [00:00 today, 00:00 tomorrow) in now's location.
func dayRange(now time.Time) (time.Time, time.Time) {
	loc := now.Location()
	from := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc)
	return from, from.AddDate(0, 0, 1)
}

// weekRange returns [Monday 00:00, next Monday 00:00) in now's location.
func weekRange(now time.Time) (time.Time, time.Time) {
	loc := now.Location()
	day := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc)
	offset := (int(day.Weekday()) + 6) % 7 // Monday=0 … Sunday=6
	from := day.AddDate(0, 0, -offset)
	return from, from.AddDate(0, 0, 7)
}

// monthRange returns [1st 00:00, 1st of next month 00:00) in now's location.
func monthRange(now time.Time) (time.Time, time.Time) {
	loc := now.Location()
	from := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, loc)
	return from, from.AddDate(0, 1, 0)
}
