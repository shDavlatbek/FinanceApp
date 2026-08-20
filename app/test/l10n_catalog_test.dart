/// Catalog hygiene for the three ARB files.
///
/// `flutter gen-l10n` only *warns* about a missing key and only *errors* on a
/// missing `other` plural case, so the two bugs that actually ship — an
/// untranslated key and a Russian plural missing `few`/`many` — have to be
/// caught here.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tally/core/seed_names.dart';
import 'package:tally/features/settings/settings_screen.dart'
    show kCommonCurrencies, kLanguageOptions;
import 'package:tally/l10n/l10n.dart' show kLanguageEndonyms;

const List<String> _locales = ['en', 'ru', 'uz'];

Map<String, dynamic> _arb(String locale) => jsonDecode(
      File('lib/l10n/arb/app_$locale.arb').readAsStringSync(),
    ) as Map<String, dynamic>;

/// Message keys only — drops `@@locale` and every `@key` metadata block.
Set<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((String k) => !k.startsWith('@')).toSet();

bool _isPlural(Object? value) =>
    value is String && value.contains(', plural,');

void main() {
  final Map<String, Map<String, dynamic>> catalogs = <String, Map<String, dynamic>>{
    for (final String locale in _locales) locale: _arb(locale),
  };
  final Set<String> englishKeys = _messageKeys(catalogs['en']!);

  test('the template declares a healthy number of messages', () {
    expect(englishKeys.length, greaterThan(150));
  });

  test('every locale declares @@locale matching its file name', () {
    for (final String locale in _locales) {
      expect(catalogs[locale]!['@@locale'], locale);
    }
  });

  group('parity with app_en.arb', () {
    for (final String locale in ['ru', 'uz']) {
      test('app_$locale.arb translates every key', () {
        final Set<String> keys = _messageKeys(catalogs[locale]!);
        expect(
          englishKeys.difference(keys),
          isEmpty,
          reason: 'app_$locale.arb is missing these keys',
        );
        expect(
          keys.difference(englishKeys),
          isEmpty,
          reason: 'app_$locale.arb has keys the template does not declare',
        );
      });

      test('app_$locale.arb has no empty translations', () {
        for (final String key in _messageKeys(catalogs[locale]!)) {
          expect(
            (catalogs[locale]![key] as String).trim(),
            isNotEmpty,
            reason: '$key is blank in app_$locale.arb',
          );
        }
      });
    }
  });

  group('plural cases', () {
    late final List<String> pluralKeys = englishKeys
        .where((String k) => _isPlural(catalogs['en']![k]))
        .toList()
      ..sort();

    test('the template actually uses ICU plurals', () {
      expect(pluralKeys, isNotEmpty);
    });

    test('Russian declares one/few/many/other for every plural', () {
      for (final String key in pluralKeys) {
        final String message = catalogs['ru']![key] as String;
        expect(_isPlural(message), isTrue, reason: '$key lost its plural');
        for (final String form in ['one{', 'few{', 'many{', 'other{']) {
          expect(
            message,
            contains(form),
            reason: 'app_ru.arb $key is missing the "$form" case — Russian '
                'needs all four CLDR forms',
          );
        }
      }
    });

    test('English and Uzbek declare one/other for every plural', () {
      for (final String locale in ['en', 'uz']) {
        for (final String key in pluralKeys) {
          final String message = catalogs[locale]![key] as String;
          for (final String form in ['one{', 'other{']) {
            expect(message, contains(form),
                reason: 'app_$locale.arb $key is missing "$form"');
          }
        }
      }
    });
  });

  test('every seed category id has a translated ARB key', () {
    for (final String id in seedCategoryIds) {
      final String key = seedNameKey(id)!;
      for (final String locale in _locales) {
        expect(catalogs[locale]!.containsKey(key), isTrue,
            reason: 'app_$locale.arb has no $key');
      }
    }
  });

  test('every offered currency has a translated name', () {
    for (final String code in kCommonCurrencies) {
      for (final String locale in _locales) {
        expect(catalogs[locale]!.containsKey('currency$code'), isTrue,
            reason: 'app_$locale.arb has no currency$code');
      }
    }
  });

  test('the language picker offers exactly the shipped locales', () {
    expect(kLanguageOptions.first, '', reason: 'System must come first');
    expect(kLanguageOptions.skip(1).toSet(), _locales.toSet());
    for (final String code in kLanguageOptions.skip(1)) {
      expect(kLanguageEndonyms[code], isNotNull);
    }
  });

  test('Uzbek uses U+02BB / U+02BC, never an ASCII apostrophe', () {
    // `use-escaping` is off precisely so `oʻ` / `gʻ` survive; an ASCII quote
    // sneaking in would render wrong and break the day escaping is enabled.
    for (final String key in _messageKeys(catalogs['uz']!)) {
      expect(
        catalogs['uz']![key] as String,
        isNot(contains("'")),
        reason: 'app_uz.arb $key uses an ASCII apostrophe',
      );
    }
  });

  test('translations use exactly the placeholders the template declares', () {
    final RegExp placeholder = RegExp(r'\{([a-zA-Z][a-zA-Z0-9_]*)\}');
    Set<String> names(String message) =>
        placeholder.allMatches(message).map((m) => m.group(1)!).toSet();

    for (final String key in englishKeys) {
      final Set<String> expected = names(catalogs['en']![key] as String);
      for (final String locale in ['ru', 'uz']) {
        expect(
          names(catalogs[locale]![key] as String),
          expected,
          reason: 'app_$locale.arb $key uses different placeholders',
        );
      }
    }
  });

  test('every message in the template carries a description', () {
    for (final String key in englishKeys) {
      final Object? meta = catalogs['en']!['@$key'];
      expect(meta, isA<Map<String, dynamic>>(), reason: '@$key is missing');
      expect((meta! as Map<String, dynamic>)['description'], isNotNull,
          reason: '@$key has no description');
    }
  });
}
