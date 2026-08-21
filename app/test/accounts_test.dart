/// Accounts, transfers and the "transfers are not spending" invariant.
///
/// The invariant is the load-bearing one: moving money between two of the
/// owner's own accounts must leave every income total, expense total,
/// category breakdown and trend figure exactly where it was. Otherwise
/// putting money aside reads as losing it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tally/core/constants.dart';
import 'package:tally/data/db/database.dart';
import 'package:tally/data/repo/accounts_repository.dart';
import 'package:tally/data/repo/summaries_repository.dart';
import 'package:tally/data/repo/transactions_repository.dart';

import 'support/test_db.dart';

const String _cash = 'a1c7e2f0-0001-4a00-9000-000000000001';
const String _card = 'a1c7e2f0-0002-4a00-9000-000000000002';
const String _savings = 'a1c7e2f0-0003-4a00-9000-000000000003';
const String _investments = 'a1c7e2f0-0004-4a00-9000-000000000004';
const String _groceries = 'c1a7e2f0-0001-4a00-9000-000000000001';
const String _salary = 'c1a7e2f0-0101-4a00-9000-000000000101';

void main() {
  late AppDatabase db;
  late TransactionsRepository txs;
  late AccountsRepository accounts;
  late SummariesRepository summaries;

  setUp(() {
    db = openTestDb();
    txs = TransactionsRepository(db);
    accounts = AccountsRepository(db);
    summaries = SummariesRepository(db);
  });
  tearDown(() => db.close());

  group('seed accounts', () {
    test('match the contract, byte for byte', () async {
      final List<Account> seeded = await accounts.watchActive().first;
      expect(seeded, hasLength(4));

      final byId = {for (final Account a in seeded) a.id: a};
      expect(byId[_cash]!.name, 'Cash');
      expect(byId[_cash]!.kind, AccountKind.cash);
      expect(byId[_card]!.kind, AccountKind.bank);
      // Savings and investments are seeded, not left to the user: "send to
      // savings" has to work on a fresh install with no setup step.
      expect(byId[_savings]!.kind, AccountKind.savings);
      expect(byId[_investments]!.kind, AccountKind.investment);

      for (final SeedAccount s in seedAccounts) {
        final Account a = byId[s.id]!;
        expect(a.name, s.name);
        expect(a.emoji, s.emoji);
        expect(a.color, s.color);
        expect(a.sortOrder, s.sortOrder);
        expect(a.updatedAtMs, seedUpdatedAtMs);
      }
    });

    test('cash is the default account', () {
      expect(defaultAccountId, _cash);
    });
  });

  group('balances', () {
    test('are opening + income - expenses + transfers in - transfers out',
        () async {
      // A card carrying debt, so a negative opening balance is exercised.
      await accounts.update(id: _card, openingBalanceMinor: -50000);

      await txs.insert(
        kind: Kind.income,
        amountMinor: 300000,
        categoryId: _salary,
        accountId: _card,
      );
      await txs.insert(
        kind: Kind.expense,
        amountMinor: 25000,
        categoryId: _groceries,
        accountId: _card,
      );
      await txs.insert(
        kind: Kind.expense,
        amountMinor: 5000,
        categoryId: _groceries,
        accountId: _cash,
      );
      await txs.insertTransfer(
        amountMinor: 100000,
        fromAccountId: _card,
        toAccountId: _savings,
      );

      final List<AccountBalance> balances = await accounts.watchBalances().first;
      final byId = {
        for (final AccountBalance b in balances) b.account.id: b.balanceMinor,
      };

      // -50000 opening + 300000 income - 25000 expense - 100000 out
      expect(byId[_card], 125000);
      expect(byId[_cash], -5000);
      expect(byId[_savings], 100000);
      expect(byId[_investments], 0);
    });

    test('a deleted transfer stops moving money', () async {
      final Transaction ghost = await txs.insertTransfer(
        amountMinor: 999999,
        fromAccountId: _cash,
        toAccountId: _savings,
      );
      await txs.softDelete(ghost.id);

      final balances = await accounts.watchBalances().first;
      final byId = {
        for (final AccountBalance b in balances) b.account.id: b.balanceMinor,
      };
      expect(byId[_savings], 0);
      expect(byId[_cash], 0);
    });

    test('archiving an account keeps its transactions resolvable', () async {
      await txs.insert(
        kind: Kind.expense,
        amountMinor: 1000,
        categoryId: _groceries,
        accountId: _savings,
      );
      await accounts.archive(_savings);

      // Gone from the live list...
      final live = await accounts.watchActive().first;
      expect(live.map((Account a) => a.id), isNot(contains(_savings)));
      // ...but still resolvable, so history does not lose the entry's label.
      final all = await accounts.watchAll().first;
      expect(all.map((Account a) => a.id), contains(_savings));
      expect((await accounts.getById(_savings))!.deletedAtMs, isNotNull);
    });
  });

  group('transfers are not spending', () {
    test('a transfer moves no total, in either lens', () async {
      final DateTime today = DateTime.now();
      await txs.insert(
        kind: Kind.expense,
        amountMinor: 25000,
        categoryId: _groceries,
        accountId: _cash,
        occurredAt: today,
      );

      final PeriodTotals monthBefore =
          await summaries.watchMonthTotals(today).first;
      final PeriodTotals dayBefore = await summaries.watchDayTotals(today).first;
      final List<CategoryTotal> catsBefore =
          await summaries.watchCategoryTotals(today).first;

      await txs.insertTransfer(
        amountMinor: 700000,
        fromAccountId: _cash,
        toAccountId: _savings,
        occurredAt: today,
      );

      final PeriodTotals monthAfter =
          await summaries.watchMonthTotals(today).first;
      final PeriodTotals dayAfter = await summaries.watchDayTotals(today).first;
      final List<CategoryTotal> catsAfter =
          await summaries.watchCategoryTotals(today).first;

      expect(monthAfter.incomeMinor, monthBefore.incomeMinor);
      expect(monthAfter.expenseMinor, monthBefore.expenseMinor);
      expect(monthAfter.expenseMinor, 25000);
      expect(dayAfter.incomeMinor, dayBefore.incomeMinor);
      expect(dayAfter.expenseMinor, dayBefore.expenseMinor);
      expect(catsAfter.length, catsBefore.length);
      // A transfer has no category, so it cannot even reach a breakdown.
      expect(
        catsAfter.map((CategoryTotal c) => c.category.id),
        isNot(contains('')),
      );
    });

    test('a transfer does not appear in the six-month trend', () async {
      final DateTime today = DateTime.now();
      await txs.insertTransfer(
        amountMinor: 400000,
        fromAccountId: _cash,
        toAccountId: _investments,
        occurredAt: today,
      );
      final List<PeriodTotals> trend =
          await summaries.watchLastSixMonths(today).first;
      expect(trend, hasLength(6));
      expect(
        trend.every((PeriodTotals p) =>
            p.incomeMinor == 0 && p.expenseMinor == 0),
        isTrue,
      );
    });

    test('a transfer does not appear in the day trend', () async {
      final DateTime today = DateTime.now();
      await txs.insertTransfer(
        amountMinor: 400000,
        fromAccountId: _cash,
        toAccountId: _investments,
        occurredAt: today,
      );
      final List<PeriodTotals> trend =
          await summaries.watchLastDays(today, days: 7).first;
      expect(trend, hasLength(7));
      expect(
        trend.every((PeriodTotals p) =>
            p.incomeMinor == 0 && p.expenseMinor == 0),
        isTrue,
      );
    });
  });

  group('insertTransfer guards', () {
    test('refuses a transfer to the same account', () {
      // It would net to zero yet still show money moving in history.
      expect(
        () => txs.insertTransfer(
          amountMinor: 100,
          fromAccountId: _cash,
          toAccountId: _cash,
        ),
        throwsArgumentError,
      );
    });

    test('refuses a non-positive amount', () {
      // Direction carries the sign; the amount never does.
      expect(
        () => txs.insertTransfer(
          amountMinor: 0,
          fromAccountId: _cash,
          toAccountId: _savings,
        ),
        throwsArgumentError,
      );
      expect(
        () => txs.insertTransfer(
          amountMinor: -500,
          fromAccountId: _cash,
          toAccountId: _savings,
        ),
        throwsArgumentError,
      );
    });

    test('stores one row with two accounts and no category', () async {
      final Transaction t = await txs.insertTransfer(
        amountMinor: 5000,
        fromAccountId: _cash,
        toAccountId: _savings,
        note: 'rainy day',
      );
      expect(t.kind, Kind.transfer);
      expect(t.categoryId, isEmpty);
      expect(t.accountId, _cash);
      expect(t.toAccountId, _savings);
      expect(t.dirty, isTrue);

      // ONE row, never a matched expense/income pair — a pair could
      // half-arrive or be half-deleted under last-write-wins.
      final List<Transaction> all = await db.select(db.transactions).get();
      expect(all, hasLength(1));
    });
  });

  group('default account', () {
    test('falls back to a live account when the configured one is archived',
        () async {
      expect((await accounts.resolveDefault(_cash))!.id, _cash);

      await accounts.archive(_cash);
      final Account? resolved = await accounts.resolveDefault(_cash);
      expect(resolved, isNotNull);
      expect(resolved!.id, isNot(_cash));
      expect(resolved.deletedAtMs, isNull);
    });

    test('falls back when the configured id is unknown or empty', () async {
      expect((await accounts.resolveDefault(''))!.id, _cash);
      expect((await accounts.resolveDefault('nope'))!.id, _cash);
    });
  });

  group('balance arithmetic is sound on its own', () {
    test('a self-transfer cannot invent money', () async {
      // Inserted straight into the table, bypassing insertTransfer's guard —
      // exactly how a hand-edited peer file would arrive. A first-match CASE
      // would credit the amount and never reach the debit arm.
      await db.into(db.transactions).insert(Transaction(
            id: 'self',
            kind: Kind.transfer,
            amountMinor: 250000,
            categoryId: '',
            accountId: _cash,
            toAccountId: _cash,
            note: '',
            occurredAt: '2026-08-20T10:00:00Z',
            sortOrder: 0,
            source: TxSource.app,
            createdAtMs: 1787000000000,
            updatedAtMs: 1787000000000,
            deletedAtMs: null,
            dirty: false,
          ));

      final balances = await accounts.watchBalances().first;
      final cash = balances.firstWhere((b) => b.account.id == _cash);
      expect(cash.balanceMinor, 0,
          reason: 'a self-transfer created money out of nothing');
    });
  });

  group('ordering and archiving', () {
    test('reorder renumbers by position and marks every row dirty', () async {
      final List<Account> before = await accounts.watchActive().first;
      final List<String> reversed = <String>[
        for (final Account a in before.reversed) a.id,
      ];

      await accounts.reorder(reversed);

      final List<Account> after = await accounts.watchActive().first;
      expect(<String>[for (final Account a in after) a.id], reversed);
      for (int i = 0; i < after.length; i++) {
        expect(after[i].sortOrder, i);
        // The order has to reach the other peer, so every touched row is
        // dirty and its updated_at_ms bumped.
        expect(after[i].dirty, isTrue);
        expect(after[i].updatedAtMs, greaterThan(seedUpdatedAtMs));
      }
    });

    test('a new account lands after the seeds instead of colliding', () async {
      final Account created = await accounts.insert(
        name: 'Brokerage',
        kind: AccountKind.investment,
        emoji: '📈',
        color: '#9B7DE8',
      );
      expect(created.sortOrder, 4);
    });

    test('unarchive lifts the tombstone off the same row', () async {
      // Undo has to restore the account itself, not a copy: a new id would
      // orphan every transaction booked to the old one.
      final Transaction booked = await txs.insert(
        kind: Kind.expense,
        amountMinor: 100,
        categoryId: _groceries,
        accountId: _card,
      );
      await accounts.archive(_card);
      expect((await accounts.getById(_card))!.deletedAtMs, isNotNull);

      await accounts.unarchive(_card);

      final Account restored = (await accounts.getById(_card))!;
      expect(restored.deletedAtMs, isNull);
      expect(restored.dirty, isTrue);
      expect((await txs.getById(booked.id))!.accountId, _card);
    });
  });

  group('restoring a transaction', () {
    test('brings a transfer back with both of its accounts', () async {
      // Regression: undo used to re-INSERT from remembered fields, which minted
      // a new id and dropped account_id, to_account_id and sort_order.
      final Transaction transfer = await txs.insertTransfer(
        amountMinor: 50000,
        fromAccountId: _card,
        toAccountId: _savings,
        note: 'rainy day',
      );
      await txs.softDelete(transfer.id);
      await txs.restore(transfer.id);

      final Transaction restored = (await txs.getById(transfer.id))!;
      expect(restored.deletedAtMs, isNull);
      expect(restored.kind, Kind.transfer);
      expect(restored.accountId, _card);
      expect(restored.toAccountId, _savings);
      expect(restored.note, 'rainy day');
      expect(restored.dirty, isTrue);
    });

    test('puts the money back in the balance', () async {
      final int opening =
          (await accounts.watchBalances().first)
              .firstWhere((AccountBalance b) => b.account.id == _savings)
              .balanceMinor;
      final Transaction transfer = await txs.insertTransfer(
        amountMinor: 50000,
        fromAccountId: _card,
        toAccountId: _savings,
      );
      await txs.softDelete(transfer.id);
      await txs.restore(transfer.id);

      final int after = (await accounts.watchBalances().first)
          .firstWhere((AccountBalance b) => b.account.id == _savings)
          .balanceMinor;
      expect(after, opening + 50000);
    });
  });
}
