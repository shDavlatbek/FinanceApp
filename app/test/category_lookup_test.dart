/// Archived categories must keep resolving in id lookups: transactions keep
/// referencing them (SPEC: archive, "transactions keep referencing it"),
/// while pickers only show active categories.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tally/core/constants.dart';
import 'package:tally/data/providers.dart';

import 'support/test_db.dart';

void main() {
  test('categoriesByIdProvider still resolves archived categories', () async {
    final db = openTestDb();
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    // LIFO teardown: dispose the container (cancels stream subscriptions and
    // the sync engine's debounce timer) before closing the database.
    addTearDown(db.close);
    addTearDown(container.dispose);

    final groceries = seedCategories.first;
    await container.read(categoriesRepoProvider).archive(groceries.id);

    // Wait for the first emission of both category streams.
    final all = await container.read(allCategoriesProvider.future);
    final active = await container.read(allActiveCategoriesProvider.future);

    // Picker stream drops the archived category…
    expect(active.map((c) => c.id), isNot(contains(groceries.id)));
    // …but the lookup map keeps it, so old transactions stay labeled.
    final byId = container.read(categoriesByIdProvider);
    expect(byId[groceries.id]?.name, groceries.name);
    expect(byId[groceries.id]?.emoji, groceries.emoji);
    expect(all.map((c) => c.id), contains(groceries.id));
  });
}
