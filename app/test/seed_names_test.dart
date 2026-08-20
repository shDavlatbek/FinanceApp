/// The seed-name localization rule from docs/ARCHITECTURE.md:
/// a seed category is localized only while the user has not renamed it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:tally/core/constants.dart';
import 'package:tally/core/seed_names.dart';

/// Stand-in for the generated AppLocalizations lookup the i18n agent wires up.
String? _ru(String key) => const <String, String>{
      'seedCategoryGroceries': 'Продукты',
      'seedCategorySalary': 'Зарплата',
      'seedCategoryOtherIncome': 'Прочий доход',
    }[key];

void main() {
  test('every seed id has a canonical name and a stable ARB key', () {
    expect(seedCategoryIds, hasLength(15));
    for (final SeedCategory c in seedCategories) {
      expect(isSeedId(c.id), isTrue, reason: c.id);
      expect(canonicalSeedName(c.id), c.name);
      expect(seedNameKey(c.id), isNotNull, reason: c.id);
    }
    // Keys are unique — two categories must never share a translation.
    expect(seedCategoryNameKeys.values.toSet(), hasLength(15));
    expect(seedCategoryNameKeys.keys.toSet(),
        seedCategories.map((SeedCategory c) => c.id).toSet());
  });

  test('user categories are never seeds', () {
    const String userId = 'ffffffff-0000-4000-9000-000000000001';
    expect(isSeedId(userId), isFalse);
    expect(canonicalSeedName(userId), isNull);
    expect(seedNameKey(userId), isNull);
    expect(isRenamedSeed(userId, 'Cats'), isFalse);
    expect(
      categoryDisplayName(id: userId, name: 'Cats', localize: _ru),
      'Cats',
    );
  });

  test('an untouched seed localizes', () {
    const String groceries = 'c1a7e2f0-0001-4a00-9000-000000000001';
    expect(isUnrenamedSeed(groceries, 'Groceries'), isTrue);
    expect(isRenamedSeed(groceries, 'Groceries'), isFalse);
    expect(
      categoryDisplayName(id: groceries, name: 'Groceries', localize: _ru),
      'Продукты',
    );
  });

  test('a renamed seed displays verbatim in every language', () {
    const String groceries = 'c1a7e2f0-0001-4a00-9000-000000000001';
    expect(isUnrenamedSeed(groceries, 'Еда'), isFalse);
    expect(isRenamedSeed(groceries, 'Еда'), isTrue);
    expect(
      categoryDisplayName(id: groceries, name: 'Еда', localize: _ru),
      'Еда',
    );
  });

  test('a missing translation falls back to the canonical English name', () {
    const String cafe = 'c1a7e2f0-0002-4a00-9000-000000000002';
    expect(
      categoryDisplayName(id: cafe, name: 'Cafe', localize: _ru),
      'Cafe',
    );
    expect(
      categoryDisplayName(id: cafe, name: 'Cafe', localize: (_) => ''),
      'Cafe',
    );
    // The no-i18n path used by tests and the pre-i18n UI.
    expect(
      categoryDisplayName(id: cafe, name: 'Cafe', localize: (_) => null),
      'Cafe',
    );
  });
}
