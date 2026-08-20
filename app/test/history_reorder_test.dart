/// Dragging a transaction in History persists the whole day's order.
///
/// Exercises the real path — screen widget → repository → database — rather
/// than the repository alone, so a screen that renders the list but forgets to
/// wire the callback would fail here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tally/data/providers.dart';
import 'package:tally/data/repo/transactions_repository.dart';
import 'package:tally/main.dart';

import 'support/test_db.dart';

const String _groceries = 'c1a7e2f0-0001-4a00-9000-000000000001';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (final int ms in const <int>[100, 300, 500, 800]) {
    await tester.pump(Duration(milliseconds: ms));
  }
}

Future<void> _teardownTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 4));
}

void main() {
  testWidgets('dragging a row persists the day order and survives a rebuild',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppDatabase db = openTestDb();
    addTearDown(db.close);

    final TransactionsRepository repo = TransactionsRepository(db);
    final DateTime day = DateTime.now().subtract(const Duration(days: 2));
    DateTime at(int hour) =>
        DateTime(day.year, day.month, day.day, hour);

    // Morning, midday, evening — so the untouched order is evening first.
    final Transaction morning = await repo.insert(
      kind: Kind.expense,
      amountMinor: 100,
      categoryId: _groceries,
      note: 'morning',
      occurredAt: at(8),
    );
    final Transaction midday = await repo.insert(
      kind: Kind.expense,
      amountMinor: 200,
      categoryId: _groceries,
      note: 'midday',
      occurredAt: at(13),
    );
    final Transaction evening = await repo.insert(
      kind: Kind.expense,
      amountMinor: 300,
      categoryId: _groceries,
      note: 'evening',
      occurredAt: at(20),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        child: const TallyApp(),
      ),
    );
    await _settle(tester);
    await tester.tap(find.byIcon(Icons.receipt_long_rounded));
    await _settle(tester);

    // The subtitle is one joined string ("8:00 AM · evening"), so match on a
    // substring rather than the note alone.
    expect(find.textContaining('evening'), findsOneWidget,
        reason: 'the seeded day should be on screen');

    final Finder listFinder = find.byType(ReorderableListView);
    expect(listFinder, findsWidgets);

    // Move the top row (evening, newest) down to the bottom of its day.
    final ReorderableListView list =
        tester.widget<ReorderableListView>(listFinder.first);
    list.onReorderItem!(0, 2);
    await _settle(tester);

    // A one-shot select, not `watchFiltered().first`: testWidgets runs in a
    // fake-async zone where drift's stream keep-alive timer never fires, so
    // awaiting a stream here hangs forever.
    final List<Transaction> rows = await db.select(db.transactions).get();
    expect(
      <String>[for (final Transaction t in sortedForDisplay(rows)) t.note],
      <String>['midday', 'morning', 'evening'],
    );

    // Persisted, not merely reordered on screen: numbered 1..N and dirty so
    // the placement reaches the other peer.
    final Transaction storedEvening = (await repo.getById(evening.id))!;
    final Transaction storedMidday = (await repo.getById(midday.id))!;
    final Transaction storedMorning = (await repo.getById(morning.id))!;
    expect(storedMidday.sortOrder, 1);
    expect(storedMorning.sortOrder, 2);
    expect(storedEvening.sortOrder, 3);
    expect(storedEvening.dirty, isTrue);

    await _teardownTree(tester);
  });
}
