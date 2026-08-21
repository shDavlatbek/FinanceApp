/// The Backup section in Settings, driven through the real widgets with a fake
/// file transport.
///
/// The transport is faked, not the service: what matters is that the rows build
/// the right file, hand it over, and report honestly — including the two
/// outcomes that are easy to get wrong, a cancelled dialog and a merge that
/// applied nothing.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tally/core/theme.dart';
import 'package:tally/data/providers.dart';
import 'package:tally/data/repo/transactions_repository.dart';
import 'package:tally/features/settings/settings_screen.dart';
import 'package:tally/l10n/l10n.dart';

import 'support/test_db.dart';

const String _groceries = 'c1a7e2f0-0001-4a00-9000-000000000001';

/// Records what the screen asked to save, and hands back what it is told to
/// hand back on a pick.
class _FakeTransport implements BackupFileTransport {
  _FakeTransport({this.saveResult = true, this.pickResult});

  final bool saveResult;
  PickedBackupFile? pickResult;
  final List<BackupFile> saved = <BackupFile>[];
  int pickCalls = 0;

  @override
  Future<bool> save(BackupFile file) async {
    saved.add(file);
    return saveResult;
  }

  @override
  Future<PickedBackupFile?> pick() async {
    pickCalls++;
    return pickResult;
  }
}

/// A transport whose save blows up, standing in for a full disk or a revoked
/// document permission.
class _FailingTransport implements BackupFileTransport {
  @override
  Future<bool> save(BackupFile file) async => throw Exception('disk is full');

  @override
  Future<PickedBackupFile?> pick() async => null;
}

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

Future<void> _pumpSettings(
  WidgetTester tester,
  AppDatabase db,
  BackupFileTransport transport,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        backupTransportProvider.overrideWithValue(transport),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: tallyTheme(Brightness.dark),
        home: const Scaffold(body: SettingsScreen()),
      ),
    ),
  );
  await _settle(tester);
}

/// Scrolls the Backup row with [label] into view and taps it.
Future<void> _tapRow(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(find.text(label), 200);
  await _settle(tester);
  await tester.tap(find.text(label));
  await _settle(tester);
}

void main() {
  late AppDatabase db;

  setUp(() => db = openTestDb());
  tearDown(() => db.close());

  testWidgets('the section offers export, spreadsheet and import',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSettings(tester, db, _FakeTransport());
    await tester.scrollUntilVisible(find.text('Import a backup'), 200);
    await _settle(tester);

    expect(find.text('Export a backup'), findsOneWidget);
    expect(find.text('Export a spreadsheet'), findsOneWidget);
    expect(find.text('Import a backup'), findsOneWidget);
    // The CSV row must never read as a restore path.
    expect(find.textContaining('cannot carry deletions'), findsOneWidget);

    await _teardownTree(tester);
  });

  testWidgets('exporting a backup hands over snapshot JSON and says so',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await TransactionsRepository(db).insert(
      kind: Kind.expense,
      amountMinor: 24850,
      categoryId: _groceries,
      note: 'weekly shop',
    );
    final _FakeTransport transport = _FakeTransport();
    await _pumpSettings(tester, db, transport);
    await _tapRow(tester, 'Export a backup');

    expect(transport.saved, hasLength(1));
    final BackupFile file = transport.saved.single;
    expect(file.fileName, startsWith('tally-backup-'));
    expect(file.fileName, endsWith('.json'));
    expect(file.mimeType, 'application/json');
    final Map<String, Object?> json =
        jsonDecode(utf8.decode(file.bytes)) as Map<String, Object?>;
    expect(json['schema'], isNotNull);
    expect(utf8.decode(file.bytes), contains('weekly shop'));
    expect(find.textContaining('Saved tally-backup-'), findsOneWidget);

    await _teardownTree(tester);
  });

  testWidgets('exporting a spreadsheet uses the UI language for names',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await TransactionsRepository(db).insert(
      kind: Kind.expense,
      amountMinor: 24850,
      categoryId: _groceries,
    );
    final _FakeTransport transport = _FakeTransport();
    await _pumpSettings(tester, db, transport);
    await _tapRow(tester, 'Export a spreadsheet');

    final BackupFile file = transport.saved.single;
    expect(file.fileName, endsWith('.csv'));
    final String csv = utf8.decode(file.bytes);
    // The display names come from the widget layer; the raw kind and the
    // machine-parseable amount do not.
    // Regression: these columns came out EMPTY when the names were read off
    // `categoriesByIdProvider`, a derived provider nothing on this screen
    // subscribes to, so reading it cold handed back an empty map.
    expect(csv, contains('Groceries'));
    expect(csv, contains('Cash'));
    expect(csv, contains(',expense,248.50,USD,'));

    await _teardownTree(tester);
  });

  testWidgets('a cancelled save says nothing was saved',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSettings(tester, db, _FakeTransport(saveResult: false));
    await _tapRow(tester, 'Export a backup');

    // Cancelling is a normal outcome. Reporting "Saved" here would be a lie
    // the owner only discovers when they need the file.
    expect(find.text('Nothing saved'), findsOneWidget);

    await _teardownTree(tester);
  });

  testWidgets('a failing save surfaces the reason', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSettings(tester, db, _FailingTransport());
    await _tapRow(tester, 'Export a backup');

    expect(find.textContaining('disk is full'), findsOneWidget);

    await _teardownTree(tester);
  });

  testWidgets('import asks first, then merges and reports the row count',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // A backup built by another peer, carrying one transaction this app has
    // never seen.
    final AppDatabase other = openTestDb();
    addTearDown(other.close);
    await TransactionsRepository(other).insert(
      kind: Kind.expense,
      amountMinor: 500,
      categoryId: _groceries,
      note: 'from the backup',
    );
    final BackupFile backup =
        await BackupService(other).buildSnapshotBackup();

    final _FakeTransport transport = _FakeTransport(
      pickResult: PickedBackupFile(
        fileName: backup.fileName,
        bytes: backup.bytes,
      ),
    );
    await _pumpSettings(tester, db, transport);
    await _tapRow(tester, 'Import a backup');

    // Confirmation first: the dialog states the merge rule rather than
    // implying a replace.
    expect(find.textContaining('the newer version of each one wins'),
        findsOneWidget);
    expect(transport.pickCalls, 0, reason: 'no picker before consent');
    await tester.tap(find.widgetWithText(TextButton, 'Import'));
    await _settle(tester);

    expect(transport.pickCalls, 1);
    expect(find.textContaining('row merged'), findsOneWidget);
    final List<Transaction> rows = await db.select(db.transactions).get();
    expect(rows.where((Transaction t) => t.note == 'from the backup'),
        hasLength(1));

    await _teardownTree(tester);
  });

  testWidgets('cancelling the import dialog never opens the picker',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final _FakeTransport transport = _FakeTransport();
    await _pumpSettings(tester, db, transport);
    await _tapRow(tester, 'Import a backup');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await _settle(tester);

    expect(transport.pickCalls, 0);

    await _teardownTree(tester);
  });

  testWidgets('a second import of the same file reports that nothing changed',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Import a backup of THIS database into itself: every row ties on
    // updated_at_ms, and a tie keeps the local row.
    await TransactionsRepository(db).insert(
      kind: Kind.expense,
      amountMinor: 500,
      categoryId: _groceries,
    );
    final BackupFile backup = await BackupService(db).buildSnapshotBackup();
    final _FakeTransport transport = _FakeTransport(
      pickResult: PickedBackupFile(
        fileName: backup.fileName,
        bytes: backup.bytes,
      ),
    );

    await _pumpSettings(tester, db, transport);
    await _tapRow(tester, 'Import a backup');
    await tester.tap(find.widgetWithText(TextButton, 'Import'));
    await _settle(tester);

    expect(find.textContaining('already up to date'), findsOneWidget);

    await _teardownTree(tester);
  });

  testWidgets('an unreadable file is reported, not swallowed',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final _FakeTransport transport = _FakeTransport(
      pickResult: PickedBackupFile(
        fileName: 'not-a-backup.json',
        bytes: Uint8List.fromList(utf8.encode('{"nope": true}')),
      ),
    );
    await _pumpSettings(tester, db, transport);
    await _tapRow(tester, 'Import a backup');
    await tester.tap(find.widgetWithText(TextButton, 'Import'));
    await _settle(tester);

    expect(find.textContaining('Cannot read that file'), findsOneWidget);
    expect(await db.select(db.transactions).get(), isEmpty);

    await _teardownTree(tester);
  });
}
