/// The Dart sanitizer must apply the SAME rules as the Go one
/// (`Snapshot.Batch`). A peer file is hand-editable, so one bad row must cost
/// only that row — and the two peers must not disagree about which rows are
/// acceptable, or they would converge on different data.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tally/core/constants.dart' show snapshotSchemaVersion;
import 'package:tally/data/drive/snapshot.dart';
import 'package:tally/data/providers.dart';

const String _cash = defaultAccountId;
const String _savings = 'a1c7e2f0-0003-4a00-9000-000000000003';
const String _groceries = 'c1a7e2f0-0001-4a00-9000-000000000001';

Map<String, Object?> _account({
  String id = _savings,
  String name = 'Savings',
  String kind = AccountKind.savings,
  String color = '#E8C95A',
  int updatedAtMs = 1755000000000,
}) =>
    <String, Object?>{
      'id': id,
      'name': name,
      'kind': kind,
      'emoji': '🏦',
      'color': color,
      'opening_balance_minor': 0,
      'sort_order': 2,
      'updated_at_ms': updatedAtMs,
      'deleted_at_ms': null,
    };

Map<String, Object?> _tx({
  String id = 'tx-1',
  String kind = Kind.expense,
  int amountMinor = 1000,
  String categoryId = _groceries,
  String accountId = _cash,
  String toAccountId = '',
  String occurredAt = '2026-08-20T10:00:00Z',
  String source = TxSource.app,
  int updatedAtMs = 1787000000000,
}) =>
    <String, Object?>{
      'id': id,
      'kind': kind,
      'amount_minor': amountMinor,
      'category_id': categoryId,
      'account_id': accountId,
      'to_account_id': toAccountId,
      'note': '',
      'occurred_at': occurredAt,
      'source': source,
      'created_at_ms': updatedAtMs,
      'updated_at_ms': updatedAtMs,
      'deleted_at_ms': null,
    };

TallySnapshot _decode({
  List<Map<String, Object?>> accounts = const [],
  List<Map<String, Object?>> transactions = const [],
  Map<String, Object?>? settings,
}) =>
    TallySnapshot.decode(utf8.encode(jsonEncode(<String, Object?>{
      'schema': snapshotSchemaVersion,
      'device_id': 'peer',
      'device_name': 'Peer',
      'written_at_ms': 1787160000000,
      'accounts': accounts,
      'categories': const <Object?>[],
      'transactions': transactions,
      'settings': ?settings,
    })));

void main() {
  group('accounts', () {
    test('a malformed account is skipped, the good ones survive', () {
      final snap = _decode(accounts: [
        _account(),
        _account(id: 'bad-color', name: 'Broken', color: 'not-a-colour'),
        _account(id: 'bad-kind', name: 'Broken', kind: 'wallet'),
        _account(id: 'no-name', name: ''),
        _account(id: 'no-timestamp', name: 'Broken', updatedAtMs: 0),
      ]);
      expect(snap.accounts.map((Account a) => a.id), <String>[_savings]);
      expect(snap.skipped, hasLength(4));
    });
  });

  group('transactions', () {
    test('an unknown account_id books to the default rather than dropping',
        () {
      final snap = _decode(
          transactions: [_tx(accountId: 'a1c7e2f0-0999-4a00-9000-000000000999')]);
      // Losing an entry is worse than misfiling one.
      expect(snap.transactions, hasLength(1));
      expect(snap.transactions.single.accountId, defaultAccountId);
      expect(snap.skipped.single, contains('unknown account_id'));
    });

    test('the account rewrite cannot manufacture a self-transfer', () {
      // Unknown source + a destination of cash. If the rewrite ran after the
      // self-transfer check, this would become cash -> cash and be accepted.
      final snap = _decode(transactions: [
        _tx(
          kind: Kind.transfer,
          categoryId: '',
          accountId: 'a1c7e2f0-0999-4a00-9000-000000000999',
          toAccountId: _cash,
        )
      ]);
      for (final Transaction t in snap.transactions) {
        expect(t.accountId == t.toAccountId, isFalse,
            reason: 'sanitizer produced a self-transfer');
      }
      expect(snap.transactions, isEmpty);
    });

    test('a transfer to an unknown or identical account is skipped', () {
      expect(
        _decode(accounts: [
          _account()
        ], transactions: [
          _tx(kind: Kind.transfer, categoryId: '', toAccountId: 'nope')
        ]).transactions,
        isEmpty,
      );
      expect(
        _decode(transactions: [
          _tx(kind: Kind.transfer, categoryId: '', toAccountId: _cash)
        ]).transactions,
        isEmpty,
      );
      expect(
        _decode(transactions: [
          _tx(kind: Kind.transfer, categoryId: '', toAccountId: '')
        ]).transactions,
        isEmpty,
      );
    });

    test('a stray category on a transfer is cleared, the row kept', () {
      final snap = _decode(
        accounts: [_account()],
        transactions: [
          _tx(kind: Kind.transfer, categoryId: _groceries, toAccountId: _savings)
        ],
      );
      expect(snap.transactions, hasLength(1));
      expect(snap.transactions.single.categoryId, isEmpty);
    });

    test('a stray destination on an expense is cleared, the row kept', () {
      final snap = _decode(
        accounts: [_account()],
        transactions: [_tx(toAccountId: _savings)],
      );
      expect(snap.transactions, hasLength(1));
      expect(snap.transactions.single.toAccountId, isEmpty);
    });

    test('occurred_at is validated but NOT rewritten', () {
      // Rewriting through toIso8601String() would turn the Go peer's
      // "…:00Z" into "…:00.000Z" and mutate its rows on every merge.
      final snap = _decode(
          accounts: [_account()],
          transactions: [_tx(occurredAt: '2026-08-20T10:00:00Z')]);
      expect(snap.transactions.single.occurredAt, '2026-08-20T10:00:00Z');

      expect(_decode(transactions: [_tx(occurredAt: 'yesterday')]).transactions,
          isEmpty);
    });

    test('structurally broken rows are skipped', () {
      expect(_decode(transactions: [_tx(amountMinor: 0)]).transactions, isEmpty);
      expect(_decode(transactions: [_tx(amountMinor: -5)]).transactions, isEmpty);
      expect(_decode(transactions: [_tx(kind: 'refund')]).transactions, isEmpty);
      expect(_decode(transactions: [_tx(source: 'sms')]).transactions, isEmpty);
      expect(_decode(transactions: [_tx(updatedAtMs: 0)]).transactions, isEmpty);
      expect(_decode(transactions: [_tx(categoryId: '')]).transactions, isEmpty);
    });
  });

  group('settings', () {
    test('an unknown default account is cleared, not a reason to drop the row',
        () {
      // Otherwise one bad account row elsewhere in the file would strand the
      // bot answering in the wrong language.
      final snap = _decode(settings: <String, Object?>{
        'id': 'settings',
        'currency': 'RUB',
        'language': 'ru',
        'default_account_id': 'a1c7e2f0-0999-4a00-9000-000000000999',
        'updated_at_ms': 1787000000000,
      });
      expect(snap.settings, isNotNull);
      expect(snap.settings!.currency, 'RUB');
      expect(snap.settings!.language, 'ru');
      expect(snap.settings!.defaultAccountId, isEmpty);
    });
  });

  group('seed account naming', () {
    test('localizes only while unrenamed', () {
      String? localize(String key) => key == 'seedAccountSavings' ? 'Накопления' : null;

      expect(
        accountDisplayName(id: _savings, name: 'Savings', localize: localize),
        'Накопления',
      );
      // Renamed: shows verbatim in every language from then on.
      expect(
        accountDisplayName(id: _savings, name: 'Ipoteka', localize: localize),
        'Ipoteka',
      );
      // A user account is never localized.
      expect(
        accountDisplayName(id: 'user-1', name: 'Crypto', localize: localize),
        'Crypto',
      );
    });

    test('every seed account has an ARB key', () {
      for (final SeedAccount a in seedAccounts) {
        expect(seedAccountNameKey(a.id), isNotNull, reason: a.name);
        expect(canonicalSeedAccountName(a.id), a.name);
      }
    });
  });
}
