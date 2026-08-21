/// The CSV export's wire format (docs/ARCHITECTURE.md § CSV export).
///
/// CSV is read by programs that guess — Excel guesses the encoding, a formula
/// guesses the decimal separator — so every rule here exists because getting
/// it wrong silently corrupts the owner's numbers rather than failing loudly.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tally/core/constants.dart';
import 'package:tally/data/backup/backup_service.dart';
import 'package:tally/data/backup/csv.dart';
import 'package:tally/data/db/database.dart';
import 'package:tally/data/repo/accounts_repository.dart';
import 'package:tally/data/repo/transactions_repository.dart';

import 'support/test_db.dart';

const String _cash = 'a1c7e2f0-0001-4a00-9000-000000000001';
const String _savings = 'a1c7e2f0-0003-4a00-9000-000000000003';
const String _groceries = 'c1a7e2f0-0001-4a00-9000-000000000001';

/// Stands in for the widget layer's seed-name rule: the service hands over an
/// `(id, name)` pair and gets back what the UI would show.
String _account(String id, String name) => name;
String _category(String id, String name) => name;

void main() {
  late AppDatabase db;
  late TransactionsRepository txs;
  late BackupService backup;

  setUp(() {
    db = openTestDb();
    txs = TransactionsRepository(db);
    backup = BackupService(
      db,
      clock: () => DateTime(2026, 8, 21, 14, 25, 30),
    );
  });
  tearDown(() => db.close());

  Future<String> exportCsv({String currency = 'USD'}) async {
    final file = await backup.buildCsvExport(
      currency: currency,
      localizeCategory: _category,
      localizeAccount: _account,
    );
    return utf8.decode(file.bytes);
  }

  group('field quoting (RFC 4180)', () {
    test('leaves an ordinary value alone', () {
      expect(csvField('Groceries'), 'Groceries');
    });

    test('quotes a value containing a comma', () {
      // A note reading `weekly shop, big one` split into two columns is
      // silently corrupted data, not a rendering nit.
      expect(csvField('weekly shop, big one'), '"weekly shop, big one"');
    });

    test('doubles an embedded quote and wraps the field', () {
      expect(csvField('the "big" shop'), '"the ""big"" shop"');
    });

    test('quotes a value containing a line break', () {
      expect(csvField('two\nlines'), '"two\nlines"');
    });
  });

  group('amount column', () {
    test('scales by the currency exponent, with a dot separator', () {
      expect(csvAmount(24850, 'USD'), '248.50');
      expect(csvAmount(5, 'USD'), '0.05');
      expect(csvAmount(500000, 'USD'), '5000.00');
    });

    test('writes a zero-decimal currency with no decimal point at all', () {
      // UZS has exponent 0: `15360000.00` would be a hundredfold lie.
      expect(csvAmount(15360000, 'UZS'), '15360000');
    });

    test('never groups digits, in any language', () {
      // The column is machine-parseable by contract, so a thousands separator
      // — which is a comma in English — must never appear.
      expect(csvAmount(123456789, 'USD'), '1234567.89');
      expect(csvAmount(123456789, 'USD').contains(','), isFalse);
      expect(csvAmount(123456789, 'USD').contains(' '), isFalse);
    });

    test('survives an int64 past double precision', () {
      // 2^53 + 1 — the value that would silently round if amounts were ever
      // routed through a float.
      expect(csvAmount(9007199254740993, 'UZS'), '9007199254740993');
    });
  });

  group('document', () {
    test('starts with the UTF-8 BOM bytes and uses CRLF endings', () async {
      final file = await backup.buildCsvExport(
        currency: 'USD',
        localizeCategory: _category,
        localizeAccount: _account,
      );
      // Asserted on the BYTES, not the decoded string: Dart's UTF-8 decoder
      // silently swallows a leading BOM, so a string check here would pass
      // just as happily against a file Excel would then mis-decode.
      expect(file.bytes.take(3), <int>[0xEF, 0xBB, 0xBF]);
      expect(utf8.decode(file.bytes), contains('\r\n'));
    });

    test('declares the contract header, in order', () async {
      final String csv = await exportCsv();
      expect(
        csv.split('\r\n').first,
        'date,kind,amount,currency,category,account,to_account,note',
      );
      expect(csv.split('\r\n').first, kCsvHeader.join(','));
    });

    test('an expense carries a category and no destination', () async {
      await txs.insert(
        kind: Kind.expense,
        amountMinor: 24850,
        categoryId: _groceries,
        accountId: _cash,
        note: 'weekly shop',
        occurredAt: DateTime.utc(2026, 8, 18, 9, 30).toLocal(),
      );
      final List<String> rows = (await exportCsv()).trim().split('\r\n');
      expect(rows, hasLength(2));
      expect(rows[1], '2026-08-18,expense,248.50,USD,Groceries,Cash,,weekly shop');
    });

    test('a transfer carries two accounts and NO category', () async {
      // The contract's own example row. A category here would let a transfer
      // reach a spending breakdown.
      await txs.insertTransfer(
        amountMinor: 500000,
        fromAccountId: _cash,
        toAccountId: _savings,
        note: 'rainy day',
        occurredAt: DateTime.utc(2026, 8, 20, 12).toLocal(),
      );
      final List<String> rows = (await exportCsv()).trim().split('\r\n');
      expect(rows[1], '2026-08-20,transfer,5000.00,USD,,Cash,Savings,rainy day');
    });

    test('kind is the raw value, never a translation', () async {
      await txs.insert(
        kind: Kind.income,
        amountMinor: 100,
        categoryId: 'c1a7e2f0-0101-4a00-9000-000000000101',
      );
      expect(await exportCsv(), contains(',income,'));
    });

    test('the date column is the UTC calendar day', () async {
      // 23:30 UTC is "tomorrow" in Tashkent (+5) and "today" in New York.
      // The column is pinned to UTC so the file means one thing everywhere.
      await txs.insert(
        kind: Kind.expense,
        amountMinor: 100,
        categoryId: _groceries,
        occurredAt: DateTime.utc(2026, 8, 19, 23, 30).toLocal(),
      );
      expect(await exportCsv(), contains('2026-08-19,expense,'));
    });

    test('skips tombstoned rows', () async {
      final Transaction t = await txs.insert(
        kind: Kind.expense,
        amountMinor: 100,
        categoryId: _groceries,
        note: 'gone',
      );
      await txs.softDelete(t.id);
      expect(await exportCsv(), isNot(contains('gone')));
    });

    test('rows come out in the app display order, newest day first', () async {
      final DateTime older = DateTime.now().subtract(const Duration(days: 3));
      final DateTime newer = DateTime.now().subtract(const Duration(days: 1));
      await txs.insert(
        kind: Kind.expense,
        amountMinor: 100,
        categoryId: _groceries,
        note: 'older',
        occurredAt: older,
      );
      await txs.insert(
        kind: Kind.expense,
        amountMinor: 200,
        categoryId: _groceries,
        note: 'newer',
        occurredAt: newer,
      );
      final List<String> rows = (await exportCsv()).trim().split('\r\n');
      expect(rows[1], endsWith('newer'));
      expect(rows[2], endsWith('older'));
    });

    test('honours a hand-placed order inside one day', () async {
      final DateTime day = DateTime.now().subtract(const Duration(days: 2));
      DateTime at(int h) => DateTime(day.year, day.month, day.day, h);
      final Transaction morning = await txs.insert(
        kind: Kind.expense,
        amountMinor: 100,
        categoryId: _groceries,
        note: 'morning',
        occurredAt: at(8),
      );
      final Transaction evening = await txs.insert(
        kind: Kind.expense,
        amountMinor: 200,
        categoryId: _groceries,
        note: 'evening',
        occurredAt: at(20),
      );
      // Untouched, the evening entry sorts first; placed by hand, the morning
      // one does. The spreadsheet shows what History shows.
      await txs.reorderDay(<String>[morning.id, evening.id]);
      final List<String> rows = (await exportCsv()).trim().split('\r\n');
      expect(rows[1], endsWith('morning'));
      expect(rows[2], endsWith('evening'));
    });

    test('names accounts and categories through the injected lookups',
        () async {
      // An unknown id resolves to empty rather than leaking a raw UUID into a
      // human-facing column.
      await txs.insert(
        kind: Kind.expense,
        amountMinor: 100,
        categoryId: 'not-a-real-category',
        accountId: _cash,
      );
      final List<String> rows = (await exportCsv()).trim().split('\r\n');
      expect(rows[1], contains(',,Cash,,'));
    });

    test('the file name carries a local timestamp and the csv extension',
        () async {
      final file = await backup.buildCsvExport(
        currency: 'USD',
        localizeCategory: _category,
        localizeAccount: _account,
      );
      expect(file.fileName, 'tally-20260821-142530.csv');
      expect(file.mimeType, 'text/csv');
    });
  });

  test('a zero-decimal currency exports whole units end to end', () async {
    await AccountsRepository(db).update(id: _cash, openingBalanceMinor: 0);
    await txs.insert(
      kind: Kind.expense,
      amountMinor: 15360000,
      categoryId: _groceries,
      accountId: _cash,
      occurredAt: DateTime.utc(2026, 8, 21, 10).toLocal(),
    );
    final String csv = await exportCsv(currency: 'UZS');
    expect(csv, contains('2026-08-21,expense,15360000,UZS,Groceries,Cash,,'));
  });
}
