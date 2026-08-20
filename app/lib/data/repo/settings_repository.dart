import '../../core/constants.dart';
import '../db/database.dart';

/// Settings repository (singleton row, id = 'settings').
///
/// Both fields are part of the synced contract: `currency` and `language`.
/// `language` is what tells the Telegram bot which language to reply in, so
/// every write marks the row dirty and schedules a sync.
class SettingsRepository {
  SettingsRepository(
    this._db, {
    this._onMutation,
    int Function()? now,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase _db;
  final void Function()? _onMutation;
  final int Function() _now;

  /// The settings row, or null before the seed has landed.
  Stream<SettingsRow?> watchSettings() =>
      (_db.select(_db.settings)..where((s) => s.id.equals(settingsRowId)))
          .watchSingleOrNull();

  Future<SettingsRow?> getSettings() =>
      (_db.select(_db.settings)..where((s) => s.id.equals(settingsRowId)))
          .getSingleOrNull();

  // ---- currency -----------------------------------------------------------

  /// The active ISO-4217 currency code (falls back to 'USD' if the row is
  /// somehow missing).
  Stream<String> watchCurrency() =>
      watchSettings().map((SettingsRow? row) => row?.currency ?? defaultCurrency);

  Future<String> getCurrency() async =>
      (await getSettings())?.currency ?? defaultCurrency;

  /// Updates the currency; marks the settings row dirty for sync.
  Future<void> setCurrency(String currencyCode) => _mutate(
        (SettingsRow s) => s.copyWith(currency: currencyCode.toUpperCase()),
      );

  // ---- language -----------------------------------------------------------

  /// The chosen UI language: `''` (follow the device locale), `'en'`, `'ru'`
  /// or `'uz'`. Synced, because the bot reads it.
  Stream<String> watchLanguage() =>
      watchSettings().map((SettingsRow? row) => row?.language ?? defaultLanguage);

  Future<String> getLanguage() async =>
      (await getSettings())?.language ?? defaultLanguage;

  /// Sets the language and marks the row dirty. Pass `''` to follow the
  /// device locale. Unknown codes are rejected (kept as `''`).
  Future<void> setLanguage(String languageCode) {
    final String code = supportedLanguageCodes.contains(languageCode)
        ? languageCode
        : defaultLanguage;
    return _mutate((SettingsRow s) => s.copyWith(language: code));
  }

  // ---- internals ----------------------------------------------------------

  /// Read-modify-write so one field never clobbers the other, then bump
  /// `updated_at_ms` and mark dirty exactly once.
  Future<void> _mutate(SettingsRow Function(SettingsRow) apply) async {
    await _db.transaction(() async {
      final SettingsRow current = await getSettings() ??
          SettingsRow(
            id: settingsRowId,
            currency: defaultCurrency,
            language: defaultLanguage,
            updatedAtMs: seedUpdatedAtMs,
            dirty: false,
          );
      await _db.into(_db.settings).insertOnConflictUpdate(
            apply(current).copyWith(updatedAtMs: _now(), dirty: true),
          );
    });
    _onMutation?.call();
  }
}
