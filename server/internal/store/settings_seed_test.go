package store

import (
	"path/filepath"
	"testing"

	"github.com/xensa/tally/internal/model"
)

// The regression this file guards:
//
// The settings singleton used to be seeded at SeedUpdatedAtMs — the exact
// value the Flutter app seeds (app/lib/core/constants.dart). Under the
// contract's strict LWW ("ties keep the local row") the row could then never
// move in either direction until a human edited it. A server seeded from
// DEFAULT_CURRENCY=UZS (exponent 0) therefore stayed on UZS forever while the
// app stayed on USD (exponent 2), so a bot entry typed as "250" was stored as
// 250 minor units and rendered by the phone as $2.50 — a silent 100x
// corruption of every bot-entered row. settings.language was stuck the same
// way, defeating the feature where the phone tells the bot which language to
// speak.

// A peer's settings row must beat the local seed placeholder, in whichever
// direction it arrives.
func TestSettingsSeedNeverBlocksAPeerValue(t *testing.T) {
	s, err := Open(filepath.Join(t.TempDir(), "tally.db"), "UZS")
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()

	// The app's own seed, which carries the fixed contract timestamp.
	appSeed := model.Settings{
		ID: model.SettingsID, Currency: "USD", Language: "", UpdatedAtMs: SeedUpdatedAtMs,
	}
	applied, err := s.MergeRemote(Batch{Settings: []model.Settings{appSeed}})
	if err != nil {
		t.Fatal(err)
	}
	if applied != 1 {
		t.Fatalf("the app's seeded settings row lost to our placeholder (%d applied) — "+
			"the two peers would diverge on currency forever", applied)
	}
	got, err := s.Settings()
	if err != nil {
		t.Fatal(err)
	}
	if got.Currency != "USD" || got.UpdatedAtMs != SeedUpdatedAtMs {
		t.Fatalf("settings after merge = %+v, want the peer's USD row", got)
	}

	// And a real edit on the phone still wins over that.
	edit := model.Settings{
		ID: model.SettingsID, Currency: "RUB", Language: "ru", UpdatedAtMs: SeedUpdatedAtMs + 1,
	}
	if _, err := s.MergeRemote(Batch{Settings: []model.Settings{edit}}); err != nil {
		t.Fatal(err)
	}
	if got, _ = s.Settings(); got.Currency != "RUB" || got.Language != "ru" {
		t.Fatalf("a real peer edit did not win: %+v", got)
	}
}

// The placeholder must never travel: a snapshot carrying updated_at_ms = 0 is
// dropped by the peer's validator, so it cannot clobber anything either.
func TestSettingsSeedIsBelowTheWireThreshold(t *testing.T) {
	if SettingsUnsetMs > 0 {
		t.Fatalf("SettingsUnsetMs = %d; a placeholder above 0 would be published to peers", SettingsUnsetMs)
	}
}

// A database written by an earlier build carries the deadlocked timestamp;
// reopening it must unstick the row so the peers can converge, without
// touching a currency the user actually chose.
func TestMigrationUnsticksTheOldSettingsPlaceholder(t *testing.T) {
	path := filepath.Join(t.TempDir(), "tally.db")
	s, err := Open(path, "UZS")
	if err != nil {
		t.Fatal(err)
	}
	// Recreate the old on-disk shape.
	if _, err := s.db.Exec(`UPDATE settings SET updated_at_ms = ? WHERE id = ?`,
		int64(SeedUpdatedAtMs), model.SettingsID); err != nil {
		t.Fatal(err)
	}
	s.Close()

	s2, err := Open(path, "UZS")
	if err != nil {
		t.Fatal(err)
	}
	defer s2.Close()
	got, err := s2.Settings()
	if err != nil {
		t.Fatal(err)
	}
	if got.UpdatedAtMs != SettingsUnsetMs {
		t.Fatalf("settings still at %d — an existing install stays deadlocked against the app forever",
			got.UpdatedAtMs)
	}
	if got.Currency != "UZS" {
		t.Fatalf("the migration changed the currency to %q", got.Currency)
	}
	if dirty, _ := s2.HasDirty(); dirty {
		t.Fatal("the migration marked the row dirty; it is a placeholder, not a value to publish")
	}
}

// A row a human actually edited must survive the migration untouched.
func TestMigrationLeavesRealSettingsAlone(t *testing.T) {
	path := filepath.Join(t.TempDir(), "tally.db")
	s, err := Open(path, "USD")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.MergeRemote(Batch{Settings: []model.Settings{
		{ID: model.SettingsID, Currency: "RUB", Language: "ru", UpdatedAtMs: 1800000000000},
	}}); err != nil {
		t.Fatal(err)
	}
	s.Close()

	s2, err := Open(path, "USD")
	if err != nil {
		t.Fatal(err)
	}
	defer s2.Close()
	got, _ := s2.Settings()
	if got.Currency != "RUB" || got.Language != "ru" || got.UpdatedAtMs != 1800000000000 {
		t.Fatalf("a real settings row was mangled by the migration: %+v", got)
	}
}

// DEFAULT_CURRENCY used to be honoured only by seed(), i.e. only on an empty
// database, so changing it in .env and restarting was a silent no-op forever.
func TestApplyDefaultCurrency(t *testing.T) {
	path := filepath.Join(t.TempDir(), "tally.db")
	s, err := Open(path, "USD")
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()

	// First boot with an explicit DEFAULT_CURRENCY: applied at "now" so LWW
	// carries it to the phone, and marked dirty so a sync pass publishes it.
	applied, err := s.ApplyDefaultCurrency("UZS", 1800000000000)
	if err != nil {
		t.Fatal(err)
	}
	if !applied {
		t.Fatal("an explicitly configured DEFAULT_CURRENCY was ignored")
	}
	got, _ := s.Settings()
	if got.Currency != "UZS" || got.UpdatedAtMs != 1800000000000 {
		t.Fatalf("settings = %+v, want UZS at the supplied timestamp", got)
	}
	if dirty, _ := s.HasDirty(); !dirty {
		t.Fatal("the applied currency was not marked dirty, so it would never reach the phone")
	}

	// Re-running with the SAME value must not touch the row: the user may have
	// picked something else in the app since, and a stale .env line must not
	// clobber it on every restart.
	if _, err := s.MergeRemote(Batch{Settings: []model.Settings{
		{ID: model.SettingsID, Currency: "RUB", Language: "ru", UpdatedAtMs: 1800000000001},
	}}); err != nil {
		t.Fatal(err)
	}
	applied, err = s.ApplyDefaultCurrency("UZS", 1900000000000)
	if err != nil {
		t.Fatal(err)
	}
	if applied {
		t.Fatal("an unchanged DEFAULT_CURRENCY overwrote the currency picked in the app")
	}
	if got, _ = s.Settings(); got.Currency != "RUB" {
		t.Fatalf("settings = %+v, want the app's RUB left alone", got)
	}

	// Changing the env value IS an operator decision and must take effect.
	applied, err = s.ApplyDefaultCurrency("EUR", 1900000000000)
	if err != nil {
		t.Fatal(err)
	}
	if !applied {
		t.Fatal("a changed DEFAULT_CURRENCY was ignored — the documented env var would be a no-op")
	}
	if got, _ = s.Settings(); got.Currency != "EUR" || got.Language != "ru" {
		t.Fatalf("settings = %+v, want EUR with the language preserved", got)
	}

	// An unset DEFAULT_CURRENCY never writes anything.
	if applied, err = s.ApplyDefaultCurrency("", 2000000000000); err != nil || applied {
		t.Fatalf("empty DEFAULT_CURRENCY wrote something: applied=%v err=%v", applied, err)
	}
}

// A clock-skewed peer must not be able to veto the operator's configuration.
func TestApplyDefaultCurrencyBeatsAFutureTimestamp(t *testing.T) {
	s, err := Open(filepath.Join(t.TempDir(), "tally.db"), "USD")
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()

	if _, err := s.MergeRemote(Batch{Settings: []model.Settings{
		{ID: model.SettingsID, Currency: "USD", UpdatedAtMs: 4000000000000}, // year 2096
	}}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.ApplyDefaultCurrency("UZS", 1800000000000); err != nil {
		t.Fatal(err)
	}
	got, _ := s.Settings()
	if got.Currency != "UZS" {
		t.Fatalf("settings = %+v, want UZS despite the peer's future timestamp", got)
	}
}
