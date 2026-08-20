/// Smoke test: the full app boots against an in-memory database and the
/// Home screen renders its hero block.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tally/data/providers.dart';
import 'package:tally/features/home/home_screen.dart';
import 'package:tally/main.dart';

import 'support/test_db.dart';

void main() {
  testWidgets('app boots and Home renders', (tester) async {
    final db = openTestDb();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const TallyApp(),
      ),
    );

    // First frame + async DB streams + entrance animations.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Tally'), findsOneWidget);
    expect(find.text('NET THIS MONTH'), findsOneWidget);
    expect(find.text('Income'), findsWidgets);
    expect(find.text('Spent'), findsWidgets);

    // Entry sheet opens from the FAB (springy route) and closes again.
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('New entry'), findsOneWidget);
    expect(find.text('Add expense'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // All four tabs render.
    for (final (label, probe) in [
      ('History', 'Search notes'),
      ('Stats', 'LAST 6 MONTHS'),
      ('Settings', 'Standalone mode'),
    ]) {
      await tester.tap(find.text(label).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.textContaining(probe), findsWidgets,
          reason: 'tab $label should render');
    }

    // Dispose the tree inside the test body and pump a few frames so drift's
    // stream keep-alive timers (Timer.run on unsubscribe) fire before the
    // binding's pending-timer invariant check.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('leaving a tab takes its branch offstage', (tester) async {
    // Regression: TickerMode used to wrap the branch fade, so an outgoing
    // branch never finished animating out and stayed painted on top of the
    // new tab — every screen ghosted through every other screen.
    final db = openTestDb();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const TallyApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('NET THIS MONTH'), findsOneWidget);

    await tester.tap(find.text('History').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // `find` skips offstage subtrees, so Home's hero must be gone once the
    // fade-out completes.
    expect(
      find.text('NET THIS MONTH'),
      findsNothing,
      reason: 'the Home branch should be offstage after switching tabs',
    );
    expect(find.textContaining('Search notes'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 4));
  });
}
