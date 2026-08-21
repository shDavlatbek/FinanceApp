/// The Accounts screen and its edit sheet, driven through the real widgets.
///
/// Exercises screen → repository → database rather than the repository alone,
/// so a screen that renders the list but forgets to wire a callback fails here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tally/core/theme.dart';
import 'package:tally/data/providers.dart';
import 'package:tally/data/repo/accounts_repository.dart';
import 'package:tally/data/repo/settings_repository.dart';
import 'package:tally/data/repo/transactions_repository.dart';
import 'package:tally/features/accounts/accounts_screen.dart';
import 'package:tally/l10n/l10n.dart';

import 'support/test_db.dart';

const String _cash = 'a1c7e2f0-0001-4a00-9000-000000000001';
const String _card = 'a1c7e2f0-0002-4a00-9000-000000000002';
const String _savings = 'a1c7e2f0-0003-4a00-9000-000000000003';
const String _groceries = 'c1a7e2f0-0001-4a00-9000-000000000001';
const String _salary = 'c1a7e2f0-0101-4a00-9000-000000000101';

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

Future<void> _pumpAccounts(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: tallyTheme(Brightness.dark),
        home: const AccountsScreen(),
      ),
    ),
  );
  await _settle(tester);
}

void main() {
  testWidgets('lists the seed accounts with derived balances and their total',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppDatabase db = openTestDb();
    addTearDown(db.close);
    final TransactionsRepository txs = TransactionsRepository(db);

    await txs.insert(
      kind: Kind.income,
      amountMinor: 300000,
      categoryId: _salary,
      accountId: _card,
    );
    await txs.insert(
      kind: Kind.expense,
      amountMinor: 50000,
      categoryId: _groceries,
      accountId: _card,
    );
    // A transfer moves money without changing the total.
    await txs.insertTransfer(
      amountMinor: 100000,
      fromAccountId: _card,
      toAccountId: _savings,
    );

    await _pumpAccounts(tester, db);

    expect(find.text('TOTAL BALANCE'), findsOneWidget);
    expect(find.text('Cash'), findsWidgets);
    expect(find.text('Savings'), findsWidgets);

    // Card: +3000 − 500 − 1000 = 1500. Savings: +1000. Total: 2500 — the
    // transfer moved money between two accounts and left the sum alone.
    expect(find.text(r'$1,500.00'), findsOneWidget);
    expect(find.text(r'$1,000.00'), findsOneWidget);
    expect(find.text(r'$2,500.00'), findsOneWidget);

    await _teardownTree(tester);
  });

  testWidgets('creating an account writes it, negative opening balance and all',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppDatabase db = openTestDb();
    addTearDown(db.close);

    await _pumpAccounts(tester, db);

    await tester.tap(find.text('New account'));
    await _settle(tester);
    expect(find.text('Create account'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Account name'), 'Credit card');
    await _settle(tester);
    // A card carrying debt: the one money field in the app where a minus is a
    // real value.
    await tester.enterText(find.byType(TextField).last, '-250.50');
    await _settle(tester);
    await tester.tap(find.text('Investments').last);
    await _settle(tester);

    await tester.tap(find.text('Create account'));
    await _settle(tester);

    // One-shot selects, never `watchActive().first`: testWidgets runs in a
    // fake-async zone where drift's stream keep-alive timer never fires, so
    // awaiting a stream here hangs forever.
    final List<Account> accounts = await db.select(db.accounts).get();
    final Account created =
        accounts.firstWhere((Account a) => a.name == 'Credit card');
    expect(created.openingBalanceMinor, -25050);
    expect(created.kind, AccountKind.investment);
    // Appended after the four seeds rather than colliding with one of them.
    expect(created.sortOrder, 4);

    await _teardownTree(tester);
  });

  testWidgets('picking a default account writes the synced settings row',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppDatabase db = openTestDb();
    addTearDown(db.close);

    await _pumpAccounts(tester, db);
    expect(await SettingsRepository(db).getDefaultAccountId(), _cash);

    // The chips in the "Telegram bot books to" card are the last Savings chip
    // on screen (the rows above are list entries, not choices).
    await tester.tap(find.text('Savings').last);
    await _settle(tester);

    expect(await SettingsRepository(db).getDefaultAccountId(), _savings);

    await _teardownTree(tester);
  });

  testWidgets('the send-to chip opens a transfer with that destination chosen',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppDatabase db = openTestDb();
    addTearDown(db.close);

    await _pumpAccounts(tester, db);

    // Savings and Investments are savings/investment kinds, so both get a
    // one-tap chip. This is the "send to savings" path the feature exists for.
    expect(find.text('Send to Savings'), findsOneWidget);
    expect(find.text('Send to Investments'), findsOneWidget);

    await tester.tap(find.text('Send to Savings'));
    await _settle(tester);

    // The sheet opens already in transfer mode…
    expect(find.text('Move money'), findsWidgets);
    expect(find.text('From'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    // …so the only thing left is the amount.
    expect(find.text('Pick two different accounts'), findsNothing);

    await _teardownTree(tester);
  });

  testWidgets('archiving an account keeps its transactions resolvable',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final AppDatabase db = openTestDb();
    addTearDown(db.close);
    final Transaction booked = await TransactionsRepository(db).insert(
      kind: Kind.expense,
      amountMinor: 100,
      categoryId: _groceries,
      accountId: _card,
    );

    await _pumpAccounts(tester, db);

    await tester.tap(find.text('Card').first);
    await _settle(tester);
    // The sheet is taller than a phone screen, so the destructive action at
    // the bottom of it has to be scrolled to — exactly what a real hand does.
    await tester.ensureVisible(find.text('Archive account'));
    await _settle(tester);
    await tester.tap(find.text('Archive account'));
    await _settle(tester);
    // Confirmation dialog: the destructive action is never one tap.
    expect(find.textContaining('disappears from the pickers'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Archive account'));
    await _settle(tester);

    final AccountsRepository accounts = AccountsRepository(db);
    final List<Account> live = <Account>[
      for (final Account a in await db.select(db.accounts).get())
        if (a.deletedAtMs == null) a,
    ];
    expect(live, hasLength(3));
    // The account row is tombstoned, not deleted, and the entry still points
    // at it: history must not lose entries because a wallet was closed.
    final Account? archived = await accounts.getById(_card);
    expect(archived, isNotNull);
    expect(archived!.deletedAtMs, isNotNull);
    final Transaction? kept =
        await TransactionsRepository(db).getById(booked.id);
    expect(kept!.accountId, _card);

    await _teardownTree(tester);
  });
}
