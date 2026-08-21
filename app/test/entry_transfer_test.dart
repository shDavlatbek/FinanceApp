/// The transfer flow in the entry sheet.
///
/// The load-bearing property is not "a transfer can be created" but "creating
/// one changes no total": moving 500 into savings must leave the month's spent
/// figure exactly where it was, or putting money aside reads as losing it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tally/core/theme.dart';
import 'package:tally/data/providers.dart';
import 'package:tally/data/repo/transactions_repository.dart';
import 'package:tally/features/common/buttons.dart';
import 'package:tally/features/entry/entry_sheet.dart';
import 'package:tally/features/entry/numpad.dart';
import 'package:tally/l10n/l10n.dart';

import 'support/test_db.dart';

const String _cash = 'a1c7e2f0-0001-4a00-9000-000000000001';
const String _card = 'a1c7e2f0-0002-4a00-9000-000000000002';
const String _savings = 'a1c7e2f0-0003-4a00-9000-000000000003';
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

/// Pumps a bare host whose only job is to open the entry sheet, so the test
/// drives the sheet itself rather than a whole app shell.
Future<void> _pumpSheet(
  WidgetTester tester,
  AppDatabase db, {
  Transaction? existing,
  String? initialKind,
  String? initialToAccountId,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: tallyTheme(Brightness.dark),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showEntrySheet(
                  context,
                  existing: existing,
                  initialKind: initialKind,
                  initialToAccountId: initialToAccountId,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  await tester.tap(find.text('open'));
  await _settle(tester);
}

/// Taps the digits of [amount] on the custom numpad.
///
/// Scoped to the [Numpad] subtree: the oversized amount display shows the same
/// digits, so a bare `find.text('5')` is ambiguous the moment anything is typed.
Future<void> _type(WidgetTester tester, String amount) async {
  for (final String ch in amount.split('')) {
    await tester.tap(find.descendant(
      of: find.byType(Numpad),
      matching: find.text(ch),
    ));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await _settle(tester);
}

/// Taps the sheet's primary action.
Future<void> _submit(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(AccentButton, label));
  await _settle(tester);
}

void main() {
  late AppDatabase db;

  setUp(() => db = openTestDb());
  tearDown(() => db.close());

  testWidgets('the sheet offers all three kinds', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSheet(tester, db);
    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);
    // An expense picks a category and the account it comes out of.
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('From'), findsNothing);

    await _teardownTree(tester);
  });

  testWidgets('switching to Transfer swaps the category grid for two pickers',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSheet(tester, db);
    await tester.tap(find.text('Transfer'));
    await _settle(tester);

    expect(find.text('From'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    // A transfer has no category by contract, so the grid is gone, not just
    // disabled.
    expect(find.text('Groceries'), findsNothing);
    // Nothing chosen on the destination side yet, so the sheet says so.
    expect(find.text('Pick two different accounts'), findsOneWidget);
    expect(find.text('Move money'), findsWidgets);

    await _teardownTree(tester);
  });

  testWidgets('a transfer saves ONE row with two accounts and no category',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Opened the way the Accounts screen opens it: transfer mode, destination
    // already chosen.
    await _pumpSheet(
      tester,
      db,
      initialKind: Kind.transfer,
      initialToAccountId: _savings,
    );
    expect(find.text('Pick two different accounts'), findsNothing,
        reason: 'source defaults to the default account, destination is given');

    await _type(tester, '500');
    await _submit(tester, 'Move money');

    final List<Transaction> rows = await db.select(db.transactions).get();
    expect(rows, hasLength(1), reason: 'one row, never a matched pair');
    final Transaction t = rows.single;
    expect(t.kind, Kind.transfer);
    expect(t.amountMinor, 50000);
    expect(t.accountId, _cash, reason: 'the seed default account');
    expect(t.toAccountId, _savings);
    expect(t.categoryId, isEmpty);
    expect(t.dirty, isTrue);

    await _teardownTree(tester);
  });

  testWidgets('a transfer created in the sheet moves no income or expense total',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await TransactionsRepository(db).insert(
      kind: Kind.expense,
      amountMinor: 20000,
      categoryId: _groceries,
      accountId: _cash,
    );

    await _pumpSheet(
      tester,
      db,
      initialKind: Kind.transfer,
      initialToAccountId: _savings,
    );
    await _type(tester, '500');
    await _submit(tester, 'Move money');

    // Aggregated with a one-shot query rather than the watch* streams: those
    // hang in testWidgets' fake-async zone. The invariant itself is also
    // covered against the summaries repository in accounts_test.dart.
    final List<Transaction> rows = await db.select(db.transactions).get();
    int totalOf(String kind) => rows
        .where((Transaction t) => t.kind == kind && t.deletedAtMs == null)
        .fold<int>(0, (int sum, Transaction t) => sum + t.amountMinor);

    expect(rows, hasLength(2));
    expect(totalOf(Kind.expense), 20000,
        reason: 'putting money aside is not spending');
    expect(totalOf(Kind.income), 0);
    expect(totalOf(Kind.transfer), 50000,
        reason: 'the money did move — just not into a total');

    await _teardownTree(tester);
  });

  testWidgets('editing an expense into a transfer clears its category',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final Transaction expense = await TransactionsRepository(db).insert(
      kind: Kind.expense,
      amountMinor: 20000,
      categoryId: _groceries,
      accountId: _card,
      note: 'was a purchase',
    );

    await _pumpSheet(tester, db, existing: expense);
    await tester.tap(find.text('Transfer'));
    await _settle(tester);
    // The account choices survive the kind switch, so the source stays Card;
    // only the destination is still missing.
    await tester.tap(find.text('Savings').last);
    await _settle(tester);
    await _submit(tester, 'Save changes');

    final Transaction updated =
        (await db.select(db.transactions).get()).single;
    expect(updated.id, expense.id);
    expect(updated.kind, Kind.transfer);
    expect(updated.accountId, _card);
    expect(updated.toAccountId, _savings);
    // Left behind, the category would put a transfer in a spending breakdown.
    expect(updated.categoryId, isEmpty);

    await _teardownTree(tester);
  });

  testWidgets('editing a transfer back into an expense clears the destination',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final Transaction transfer =
        await TransactionsRepository(db).insertTransfer(
      amountMinor: 50000,
      fromAccountId: _card,
      toAccountId: _savings,
    );

    await _pumpSheet(tester, db, existing: transfer);
    // The sheet opens on the row's own kind.
    expect(find.text('From'), findsOneWidget);
    await tester.tap(find.text('Expense'));
    await _settle(tester);
    await tester.tap(find.text('Groceries'));
    await _settle(tester);
    await _submit(tester, 'Save changes');

    final Transaction updated =
        (await db.select(db.transactions).get()).single;
    expect(updated.kind, Kind.expense);
    expect(updated.categoryId, _groceries);
    // A destination on anything but a transfer double-counts in every balance.
    expect(updated.toAccountId, isEmpty);

    await _teardownTree(tester);
  });

  testWidgets('undoing a deleted transfer brings back BOTH accounts',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Regression: undo used to re-INSERT from the fields it remembered, which
    // minted a new id and dropped account_id, to_account_id and sort_order —
    // an undone transfer came back with no destination, i.e. a row the peers'
    // sanitizer throws away.
    final Transaction transfer =
        await TransactionsRepository(db).insertTransfer(
      amountMinor: 50000,
      fromAccountId: _card,
      toAccountId: _savings,
      note: 'rainy day',
    );

    await _pumpSheet(tester, db, existing: transfer);
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await _settle(tester);
    expect((await db.select(db.transactions).get()).single.deletedAtMs,
        isNotNull);

    await tester.tap(find.text('Undo'));
    await _settle(tester);

    final Transaction restored =
        (await db.select(db.transactions).get()).single;
    expect(restored.id, transfer.id, reason: 'the same row, not a copy');
    expect(restored.deletedAtMs, isNull);
    expect(restored.kind, Kind.transfer);
    expect(restored.accountId, _card);
    expect(restored.toAccountId, _savings);
    expect(restored.note, 'rainy day');

    await _teardownTree(tester);
  });
}
