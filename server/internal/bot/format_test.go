package bot

import (
	"testing"
	"time"
)

// The regression these guard:
//
// dayRange / weekRange / monthRange used to force UTC calendar boundaries
// while the Flutter app computes the same periods from LOCAL midnight
// (app/lib/core/dates.dart: `monthStart(d) => DateTime(d.year, d.month)`,
// converted to UTC only for the string comparison the query does). On a
// UTC+5 host — this product targets Uzbekistan (UTC+5) and Russia (UTC+3) —
// anything logged between 00:00 and 05:00 local was attributed to the
// previous day, and at 02:00 on the 1st `/month` reported the previous month,
// so the bot and the phone's Home screen disagreed about identical data.

var tashkent = time.FixedZone("UZT", 5*60*60) // UTC+5, no DST

func TestDayRangeUsesTheConfiguredCalendar(t *testing.T) {
	// 02:00 on 20 Aug in Tashkent is still 21:00 on 19 Aug in UTC.
	now := time.Date(2026, 8, 20, 2, 0, 0, 0, tashkent)
	from, to := dayRange(now)

	if got := from.Format(time.RFC3339); got != "2026-08-20T00:00:00+05:00" {
		t.Fatalf("day starts at %s, want local midnight on the 20th", got)
	}
	if got := to.Format(time.RFC3339); got != "2026-08-21T00:00:00+05:00" {
		t.Fatalf("day ends at %s", got)
	}
	if !from.Before(now) || !to.After(now) {
		t.Fatalf("now (%s) is outside its own day [%s, %s)", now, from, to)
	}
	// The UTC instants the store queries with straddle the date line, which is
	// the whole point: they must cover the user's day, not UTC's.
	if got := from.UTC().Format(time.RFC3339); got != "2026-08-19T19:00:00Z" {
		t.Fatalf("UTC bound = %s", got)
	}
}

func TestMonthRangeUsesTheConfiguredCalendar(t *testing.T) {
	// 02:00 on the 1st: UTC still says the previous month.
	now := time.Date(2026, 9, 1, 2, 0, 0, 0, tashkent)
	from, to := monthRange(now)

	if from.Year() != 2026 || from.Month() != time.September || from.Day() != 1 {
		t.Fatalf("month starts at %s, want 1 September local", from)
	}
	if to.Month() != time.October {
		t.Fatalf("month ends at %s, want 1 October local", to)
	}
	if now.Before(from) || !now.Before(to) {
		t.Fatalf("now (%s) is outside its own month [%s, %s)", now, from, to)
	}
	if now.UTC().Month() != time.August {
		t.Fatal("test premise broken: the instant should still be August in UTC")
	}
}

func TestWeekRangeStartsOnLocalMonday(t *testing.T) {
	// Monday 24 Aug 2026, 01:00 local — Sunday 23rd 20:00 in UTC.
	now := time.Date(2026, 8, 24, 1, 0, 0, 0, tashkent)
	from, to := weekRange(now)

	if from.Weekday() != time.Monday || from.Day() != 24 {
		t.Fatalf("week starts %s (%s), want Monday the 24th", from, from.Weekday())
	}
	if to.Sub(from) != 7*24*time.Hour {
		t.Fatalf("week spans %s", to.Sub(from))
	}
	if now.UTC().Weekday() != time.Sunday {
		t.Fatal("test premise broken: the instant should still be Sunday in UTC")
	}
}

// UTC stays the default, so an operator who sets no TZ sees the old behaviour.
func TestRangesInUTCAreUnchanged(t *testing.T) {
	now := time.Date(2026, 8, 20, 2, 0, 0, 0, time.UTC)
	from, to := dayRange(now)
	if from.Format(time.RFC3339) != "2026-08-20T00:00:00Z" || to.Format(time.RFC3339) != "2026-08-21T00:00:00Z" {
		t.Fatalf("UTC day = [%s, %s)", from, to)
	}
	mf, mt := monthRange(now)
	if mf.Format(time.RFC3339) != "2026-08-01T00:00:00Z" || mt.Format(time.RFC3339) != "2026-09-01T00:00:00Z" {
		t.Fatalf("UTC month = [%s, %s)", mf, mt)
	}
}

// A zone west of UTC must work the same way.
func TestDayRangeWestOfUTC(t *testing.T) {
	newYork := time.FixedZone("EST", -5*60*60)
	// 22:00 on 19 Aug in New York is already 03:00 on the 20th in UTC.
	now := time.Date(2026, 8, 19, 22, 0, 0, 0, newYork)
	from, to := dayRange(now)
	if from.Day() != 19 || to.Day() != 20 {
		t.Fatalf("day = [%s, %s), want the local 19th", from, to)
	}
	if now.UTC().Day() != 20 {
		t.Fatal("test premise broken: the instant should already be the 20th in UTC")
	}
}
