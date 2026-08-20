/// The active UI language.
///
/// The preference lives in the **synced** `settings.language` row (docs/
/// ARCHITECTURE.md § Internationalization) — not in local meta — because the
/// Telegram bot reads the same field to decide which language to reply in.
/// `''` means "follow the device locale".
library;

import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tally/data/providers.dart';

/// The selected language code: `''` (System) | `'en'` | `'ru'` | `'uz'`.
///
/// Seeded from the synced settings row and written straight back to it.
/// [LocaleController.setLanguage] updates `state` *before* awaiting the write
/// so the UI switches on the same frame as the tap.
final localeControllerProvider =
    NotifierProvider<LocaleController, String>(LocaleController.new);

class LocaleController extends Notifier<String> {
  @override
  String build() => _normalize(ref.watch(languageProvider).value);

  /// Persists the language to the synced settings row. Pass `''` to follow
  /// the device locale.
  Future<void> setLanguage(String code) async {
    final String next = _normalize(code);
    state = next;
    await ref.read(settingsRepoProvider).setLanguage(next);
  }

  static String _normalize(String? code) =>
      (code != null && supportedLanguageCodes.contains(code))
          ? code
          : defaultLanguage;
}

/// What `MaterialApp.locale` receives: `null` = follow the device locale,
/// which lets `basicLocaleListResolution` pick a supported locale (or `en`).
final appLocaleProvider = Provider<Locale?>((Ref ref) {
  final String code = ref.watch(localeControllerProvider);
  return code.isEmpty ? null : Locale(code);
});
