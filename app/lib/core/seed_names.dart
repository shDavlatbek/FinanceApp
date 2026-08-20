/// Seed-category name localization (docs/ARCHITECTURE.md § Seed category
/// naming).
///
/// A category `name` is user data and stays **canonical English** in the
/// database on every peer. For display, a seed category is localized *only
/// while the user has not renamed it*:
///
/// ```
/// displayName(c) = (isSeedId(c.id) && c.name == canonicalSeedName(c.id))
///                    ? localized(seedNameKey(c.id))
///                    : c.name
/// ```
///
/// Rename a category and it displays verbatim in every language from then on.
/// The Go bot implements the identical rule.
///
/// This file deliberately exposes **keys**, never translated strings: the
/// localized text lives in the ARB catalogs and is injected through the
/// [localize] callback.
library;

import 'constants.dart';

/// Stable ARB key for every seed category id, e.g.
/// `c1a7e2f0-0001-…` -> `seedCategoryGroceries`.
///
/// Keys are derived from the canonical English name and are part of the
/// contract with the ARB catalogs — do not rename them.
const Map<String, String> seedCategoryNameKeys = <String, String>{
  'c1a7e2f0-0001-4a00-9000-000000000001': 'seedCategoryGroceries',
  'c1a7e2f0-0002-4a00-9000-000000000002': 'seedCategoryCafe',
  'c1a7e2f0-0003-4a00-9000-000000000003': 'seedCategoryTransport',
  'c1a7e2f0-0004-4a00-9000-000000000004': 'seedCategoryHome',
  'c1a7e2f0-0005-4a00-9000-000000000005': 'seedCategoryUtilities',
  'c1a7e2f0-0006-4a00-9000-000000000006': 'seedCategoryHealth',
  'c1a7e2f0-0007-4a00-9000-000000000007': 'seedCategoryShopping',
  'c1a7e2f0-0008-4a00-9000-000000000008': 'seedCategoryFun',
  'c1a7e2f0-0009-4a00-9000-000000000009': 'seedCategorySubscriptions',
  'c1a7e2f0-000a-4a00-9000-00000000000a': 'seedCategoryTravel',
  'c1a7e2f0-000b-4a00-9000-00000000000b': 'seedCategoryOther',
  'c1a7e2f0-0101-4a00-9000-000000000101': 'seedCategorySalary',
  'c1a7e2f0-0102-4a00-9000-000000000102': 'seedCategoryFreelance',
  'c1a7e2f0-0103-4a00-9000-000000000103': 'seedCategoryGifts',
  'c1a7e2f0-0104-4a00-9000-000000000104': 'seedCategoryOtherIncome',
};

/// Canonical English name of every seed category id, straight from the
/// contract table.
final Map<String, String> _canonicalSeedNames = <String, String>{
  for (final SeedCategory c in seedCategories) c.id: c.name,
};

/// Every seed category id, in contract order.
List<String> get seedCategoryIds =>
    <String>[for (final SeedCategory c in seedCategories) c.id];

/// True when [id] is one of the 15 fixed seed category ids.
bool isSeedId(String id) => _canonicalSeedNames.containsKey(id);

/// The contract's English name for a seed id, or null for user categories.
String? canonicalSeedName(String id) => _canonicalSeedNames[id];

/// The ARB key for a seed id, or null for user categories.
String? seedNameKey(String id) => seedCategoryNameKeys[id];

/// True when [id] is a seed category whose [name] still matches the canonical
/// English name — i.e. the user has *not* renamed it, so it may be localized.
bool isUnrenamedSeed(String id, String name) => canonicalSeedName(id) == name;

/// True when [id] is a seed category the user has renamed. Renamed seeds
/// display verbatim in every language.
bool isRenamedSeed(String id, String name) =>
    isSeedId(id) && canonicalSeedName(id) != name;

/// Resolves the name to show for a category.
///
/// [localize] receives an ARB key from [seedCategoryNameKeys] and returns the
/// translated string, or null when the catalog has no entry (in which case the
/// canonical English name is used). Pass `(_) => null` for the raw/English
/// behaviour — e.g. in tests or before the i18n layer exists.
String categoryDisplayName({
  required String id,
  required String name,
  required String? Function(String key) localize,
}) {
  if (!isUnrenamedSeed(id, name)) return name;
  final String? key = seedNameKey(id);
  if (key == null) return name;
  final String? translated = localize(key);
  return (translated == null || translated.isEmpty) ? name : translated;
}
