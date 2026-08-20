/// Localization barrel: the generated `AppLocalizations`, the `context.l10n`
/// shorthand, and the two lookups that turn a contract key into translated
/// text (seed category names, currency names).
///
/// Nothing here caches a formatted string outside the widget tree — providers
/// hold data, widgets hold strings, so a locale switch always re-renders.
library;

import 'package:flutter/widgets.dart';

import '../core/seed_names.dart';
import 'gen/app_localizations.dart';

export 'gen/app_localizations.dart';

/// The locales the app ships, in `AppLocalizations.supportedLocales` order.
/// `en` is first, so it is also the fallback for an unmatched device locale.
const List<Locale> kAppLocales = <Locale>[
  Locale('en'),
  Locale('ru'),
  Locale('uz'),
];

/// Endonyms for the language picker. A language name is never translated into
/// the *current* UI language — you must be able to find your own language.
const Map<String, String> kLanguageEndonyms = <String, String>{
  'en': 'English',
  'ru': 'Русский',
  'uz': 'Oʻzbekcha',
};

/// A [Locale] as the tag `intl` wants (`en`, `ru`, `uz`, `pt_BR`).
String intlLocaleTag(Locale locale) =>
    locale.toLanguageTag().replaceAll('-', '_');

extension L10nX on BuildContext {
  /// Translated strings for the *resolved* locale. Non-null:
  /// `nullable-getter: false` in l10n.yaml.
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// The resolved locale as an `intl` tag — pass this to every
  /// `NumberFormat` / `DateFormat` instead of relying on the ambient default.
  String get localeTag => intlLocaleTag(Localizations.localeOf(this));

  /// Display name for a category, applying the seed-name rule from
  /// docs/ARCHITECTURE.md: a seed category is localized only while the user
  /// has not renamed it.
  String categoryName({required String id, required String name}) =>
      localizedCategoryName(l10n, id: id, name: name);
}

/// Translated text for one of the 15 seed-category ARB keys, or null when the
/// key is unknown (which makes [categoryDisplayName] fall back to canonical
/// English).
String? seedCategoryLabel(AppLocalizations l10n, String key) => switch (key) {
      'seedCategoryGroceries' => l10n.seedCategoryGroceries,
      'seedCategoryCafe' => l10n.seedCategoryCafe,
      'seedCategoryTransport' => l10n.seedCategoryTransport,
      'seedCategoryHome' => l10n.seedCategoryHome,
      'seedCategoryUtilities' => l10n.seedCategoryUtilities,
      'seedCategoryHealth' => l10n.seedCategoryHealth,
      'seedCategoryShopping' => l10n.seedCategoryShopping,
      'seedCategoryFun' => l10n.seedCategoryFun,
      'seedCategorySubscriptions' => l10n.seedCategorySubscriptions,
      'seedCategoryTravel' => l10n.seedCategoryTravel,
      'seedCategoryOther' => l10n.seedCategoryOther,
      'seedCategorySalary' => l10n.seedCategorySalary,
      'seedCategoryFreelance' => l10n.seedCategoryFreelance,
      'seedCategoryGifts' => l10n.seedCategoryGifts,
      'seedCategoryOtherIncome' => l10n.seedCategoryOtherIncome,
      _ => null,
    };

/// `displayName(c)` from docs/ARCHITECTURE.md § Seed category naming.
String localizedCategoryName(
  AppLocalizations l10n, {
  required String id,
  required String name,
}) =>
    categoryDisplayName(
      id: id,
      name: name,
      localize: (String key) => seedCategoryLabel(l10n, key),
    );

/// Human name of an ISO-4217 code for the currency picker; falls back to the
/// code itself for currencies the catalog does not name.
String currencyName(AppLocalizations l10n, String code) => switch (code) {
      'USD' => l10n.currencyUSD,
      'EUR' => l10n.currencyEUR,
      'GBP' => l10n.currencyGBP,
      'UAH' => l10n.currencyUAH,
      'PLN' => l10n.currencyPLN,
      'CZK' => l10n.currencyCZK,
      'CHF' => l10n.currencyCHF,
      'SEK' => l10n.currencySEK,
      'NOK' => l10n.currencyNOK,
      'DKK' => l10n.currencyDKK,
      'JPY' => l10n.currencyJPY,
      'CNY' => l10n.currencyCNY,
      'INR' => l10n.currencyINR,
      'CAD' => l10n.currencyCAD,
      'AUD' => l10n.currencyAUD,
      'NZD' => l10n.currencyNZD,
      'BRL' => l10n.currencyBRL,
      'MXN' => l10n.currencyMXN,
      'TRY' => l10n.currencyTRY,
      'KRW' => l10n.currencyKRW,
      'SGD' => l10n.currencySGD,
      'HKD' => l10n.currencyHKD,
      'ILS' => l10n.currencyILS,
      'AED' => l10n.currencyAED,
      'ZAR' => l10n.currencyZAR,
      'RUB' => l10n.currencyRUB,
      'UZS' => l10n.currencyUZS,
      'KZT' => l10n.currencyKZT,
      _ => code,
    };
