/// Visual-verification harness: renders the real screens with the bundled
/// fonts and writes PNGs under test/shots/ for eyeballing.
///
///   flutter test --dart-define=CAPTURE=true --update-goldens \
///       test/capture_screens_test.dart
///
/// Skipped unless CAPTURE is set: these are for looking at, not pixel-diffing,
/// and font rasterization differs across machines, so comparing them in CI
/// would fail for no useful reason.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tally/data/providers.dart';
import 'package:tally/data/repo/accounts_repository.dart';
import 'package:tally/features/entry/amount_input.dart';
import 'package:tally/data/repo/settings_repository.dart';
import 'package:tally/data/repo/transactions_repository.dart';
import 'package:tally/main.dart';

import 'support/test_db.dart';

const _groceries = 'c1a7e2f0-0001-4a00-9000-000000000001';
const _cafe = 'c1a7e2f0-0002-4a00-9000-000000000002';
const _transport = 'c1a7e2f0-0003-4a00-9000-000000000003';
const _home = 'c1a7e2f0-0004-4a00-9000-000000000004';
const _utilities = 'c1a7e2f0-0005-4a00-9000-000000000005';
const _fun = 'c1a7e2f0-0008-4a00-9000-000000000008';
const _subs = 'c1a7e2f0-0009-4a00-9000-000000000009';
const _salary = 'c1a7e2f0-0101-4a00-9000-000000000101';

const _card = 'a1c7e2f0-0002-4a00-9000-000000000002';
const _savings = 'a1c7e2f0-0003-4a00-9000-000000000003';
const _investments = 'a1c7e2f0-0004-4a00-9000-000000000004';

Future<void> _loadFonts() async {
  final loader = FontLoader('Manrope');
  for (final w in const [
    'Regular',
    'Medium',
    'SemiBold',
    'Bold',
    'ExtraBold',
  ]) {
    loader.addFont(rootBundle.load('assets/fonts/Manrope-$w.ttf'));
  }
  await loader.load();

  // Material icon glyphs (bundled by uses-material-design: true) are not
  // registered in the test environment by default, so they render as .notdef
  // boxes without this.
  try {
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  } catch (_) {
    // Non-fatal: captures still render, icons just show as boxes.
  }
}

Future<void> _seed(AppDatabase db, {int scale = 1}) async {
  final repo = TransactionsRepository(db, onMutation: () {});
  final now = DateTime.now();
  // Distinct times of day, so the captures show real time-of-day ordering
  // rather than every row sharing the clock time of the test run.
  DateTime d(int daysAgo, [int hour = 12, int minute = 0]) => DateTime(
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      ).subtract(Duration(days: daysAgo));

  Future<void> tx(
    String kind,
    int minor,
    String cat,
    String note,
    DateTime at,
  ) =>
      repo.insert(
        kind: kind,
        amountMinor: minor * scale,
        categoryId: cat,
        note: note,
        occurredAt: at,
      );

  // Current month. Two entries an hour apart on the same day, so the captures
  // show time-of-day ordering (and what manual placement overrides).
  await tx('income', 420000, _salary, 'August salary', d(18));
  await tx('expense', 24850, _groceries, 'weekly shop', d(1, 18, 40));
  await tx('expense', 6200, _cafe, 'flat white', d(1, 8, 15));
  await tx('expense', 3400, _transport, 'metro top-up', d(2, 7, 55));
  await tx('expense', 128000, _home, 'rent', d(4, 9, 5));
  await tx('expense', 8790, _utilities, 'electricity', d(5, 16, 30));
  await tx('expense', 15990, _fun, 'cinema + snacks', d(6, 20, 10));
  await tx('expense', 1099, _subs, 'music', d(7));
  await tx('expense', 31200, _groceries, 'big restock', d(9));
  await tx('expense', 4500, _cafe, 'lunch with Kate', d(11));
  await tx('expense', 7250, _transport, 'airport taxi', d(13));

  // Money put aside, so the captures show a transfer rendered as one: neutral
  // ink, no sign, the two accounts as the subtitle.
  await repo.insertTransfer(
    amountMinor: 500000 * scale,
    fromAccountId: _card,
    toAccountId: _savings,
    note: 'rainy day',
    occurredAt: d(3, 11, 20),
  );
  await repo.insertTransfer(
    amountMinor: 250000 * scale,
    fromAccountId: _card,
    toAccountId: _investments,
    occurredAt: d(8, 14, 5),
  );
  // A card carrying debt, so the Accounts screen shows a negative balance in
  // neutral ink rather than red.
  await AccountsRepository(db, onMutation: () {})
      .update(id: _card, openingBalanceMinor: -75000 * scale);

  // Earlier months, for the six-month trend.
  for (var m = 1; m <= 5; m++) {
    final base = DateTime(now.year, now.month - m, 15);
    await tx('income', 410000 + m * 3000, _salary, 'salary', base);
    await tx('expense', 120000, _home, 'rent', base);
    await tx('expense', 52000 + m * 7000, _groceries, 'groceries', base);
    await tx('expense', 18000 + m * 2500, _fun, 'fun', base);
  }
}

/// Types into the entry sheet's hero amount field, which is the only
/// [AmountField] on screen (the note is an ordinary TextField).
Future<void> _typeAmount(WidgetTester tester, String amount) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(AmountField),
      matching: find.byType(TextField),
    ),
    amount,
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (final ms in const [100, 300, 500, 800, 1200]) {
    await tester.pump(Duration(milliseconds: ms));
  }
}

Future<void> _teardownTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 4));
}

const _capture = bool.fromEnvironment('CAPTURE');

void main() {
  setUpAll(_loadFonts);

  testWidgets('capture dark screens', skip: !_capture, (tester) async {
    tester.view.physicalSize = const Size(1170, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = openTestDb();
    addTearDown(db.close);
    await _seed(db);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const TallyApp(),
      ),
    );
    await _settle(tester);

    await expectLater(
      find.byType(TallyApp),
      matchesGoldenFile('shots/01_home_dark.png'),
    );

    // Entry sheet.
    await tester.tap(find.byIcon(Icons.add_rounded));
    await _settle(tester);
    await expectLater(
      find.byType(TallyApp),
      matchesGoldenFile('shots/02_entry_sheet.png'),
    );
    // Type an amount into the hero field.
    await _typeAmount(tester, '2499');
    await expectLater(
      find.byType(TallyApp),
      matchesGoldenFile('shots/03_entry_typed.png'),
    );
    await tester.tap(find.byIcon(Icons.close_rounded));
    await _settle(tester);

    for (final (tab, shot) in const [
      ('History', 'shots/04_history.png'),
      ('Stats', 'shots/05_stats.png'),
      ('Settings', 'shots/06_settings.png'),
    ]) {
      await tester.tap(find.text(tab).last);
      await _settle(tester);
      await expectLater(find.byType(TallyApp), matchesGoldenFile(shot));
    }

    await _teardownTree(tester);
  });

  testWidgets('capture russian screens', skip: !_capture, (tester) async {
    tester.view.physicalSize = const Size(1170, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = openTestDb();
    addTearDown(db.close);
    await _seed(db);
    await SettingsRepository(db, onMutation: () {}).setLanguage('ru');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const TallyApp(),
      ),
    );
    await _settle(tester);

    await expectLater(
      find.byType(TallyApp),
      matchesGoldenFile('shots/08_home_ru.png'),
    );

    await tester.tap(find.byIcon(Icons.settings_rounded));
    await _settle(tester);
    await expectLater(
      find.byType(TallyApp),
      matchesGoldenFile('shots/09_settings_ru.png'),
    );

    await _teardownTree(tester);
  });

  testWidgets('capture uzbek home', skip: !_capture, (tester) async {
    tester.view.physicalSize = const Size(1170, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = openTestDb();
    addTearDown(db.close);
    await _seed(db);
    await SettingsRepository(db, onMutation: () {}).setLanguage('uz');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const TallyApp(),
      ),
    );
    await _settle(tester);

    await expectLater(
      find.byType(TallyApp),
      matchesGoldenFile('shots/10_home_uz.png'),
    );

    await _teardownTree(tester);
  });

  testWidgets('capture period pickers', skip: !_capture, (tester) async {
    tester.view.physicalSize = const Size(1170, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = openTestDb();
    addTearDown(db.close);
    await _seed(db);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const TallyApp(),
      ),
    );
    await _settle(tester);

    // Entering the range lens opens the picker straight away.
    await tester.tap(find.text('Range'));
    await _settle(tester);
    await expectLater(
      find.byType(TallyApp),
      matchesGoldenFile('shots/13_range_picker.png'),
    );

    await tester.tap(find.text('Last 30 days'));
    await _settle(tester);
    await tester.tap(find.text('Apply range'));
    await _settle(tester);
    await expectLater(
      find.byType(TallyApp),
      matchesGoldenFile('shots/14_home_range.png'),
    );

    // Back to the month lens, then tap the date itself to pick a month.
    await tester.tap(find.text('Month'));
    await _settle(tester);
    await tester.tap(find.byIcon(Icons.expand_more_rounded));
    await _settle(tester);
    await expectLater(
      find.byType(TallyApp),
      matchesGoldenFile('shots/15_month_picker.png'),
    );

    await _teardownTree(tester);
  });

  // The reason the adaptive money text exists: UZS is zero-decimal and
  // high-denomination, so every amount is several times wider than the same
  // number of dollars.
  testWidgets('capture uzs screens', skip: !_capture, (tester) async {
    tester.view.physicalSize = const Size(1170, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = openTestDb();
    addTearDown(db.close);
    await _seed(db, scale: 12000);
    final settings = SettingsRepository(db, onMutation: () {});
    await settings.setCurrency('UZS');
    await settings.setLanguage('uz');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const TallyApp(),
      ),
    );
    await _settle(tester);

    await expectLater(
      find.byType(TallyApp),
      matchesGoldenFile('shots/11_home_uzs.png'),
    );

    await tester.tap(find.byIcon(Icons.donut_small_rounded));
    await _settle(tester);
    await expectLater(
      find.byType(TallyApp),
      matchesGoldenFile('shots/12_stats_uzs.png'),
    );

    await _teardownTree(tester);
  });

  testWidgets('capture light home', skip: !_capture, (tester) async {
    tester.view.physicalSize = const Size(1170, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = openTestDb();
    addTearDown(db.close);
    await _seed(db);
    await db.setMeta('ui_theme_mode', 'light');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const TallyApp(),
      ),
    );
    await _settle(tester);

    await expectLater(
      find.byType(TallyApp),
      matchesGoldenFile('shots/07_home_light.png'),
    );

    await _teardownTree(tester);
  });

  testWidgets('capture accounts and transfers', skip: !_capture,
      (tester) async {
    tester.view.physicalSize = const Size(1170, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = openTestDb();
    addTearDown(db.close);
    await _seed(db);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const TallyApp(),
      ),
    );
    await _settle(tester);

    // Settings holds the entry points for both new surfaces. The Backup
    // section is shot first, while nothing is covering the screen: a modal
    // sheet is far easier to open than to dismiss from a test.
    await tester.tap(find.text('Settings').last);
    await _settle(tester);
    await tester.scrollUntilVisible(find.text('Import a backup'), 250);
    await _settle(tester);
    await expectLater(
      find.byType(TallyApp),
      matchesGoldenFile('shots/20_backup.png'),
    );

    // Plain finder, no `.last`: scrollUntilVisible probes the finder on every
    // drag step, and `.last` throws rather than reporting "not found yet"
    // while the target is still off screen.
    await tester.scrollUntilVisible(find.text('Accounts'), -250);
    await _settle(tester);
    await tester.tap(find.text('Accounts'));
    await _settle(tester);
    await expectLater(
      find.byType(TallyApp),
      matchesGoldenFile('shots/21_accounts.png'),
    );

    // One-tap "send to savings": the entry sheet in transfer mode.
    await tester.tap(find.text('Send to Savings'));
    await _settle(tester);
    await _typeAmount(tester, '500');
    await expectLater(
      find.byType(TallyApp),
      matchesGoldenFile('shots/22_transfer_sheet.png'),
    );
    await tester.tap(find.byIcon(Icons.close_rounded));
    await _settle(tester);

    // The account editor last, so nothing has to dismiss it.
    await tester.tap(find.text('Card').first);
    await _settle(tester);
    await expectLater(
      find.byType(TallyApp),
      matchesGoldenFile('shots/23_account_edit.png'),
    );

    await _teardownTree(tester);
  });
}
