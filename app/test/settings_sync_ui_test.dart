/// The Settings sync card against a real DriveSyncEngine backed by a fake
/// Drive: the escape hatch after Google access is revoked, and the snackbar a
/// manual "Sync now" shows when a pass is already in flight.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tally/core/constants.dart';
import 'package:tally/core/theme.dart';
import 'package:tally/data/drive/drive_client.dart';
import 'package:tally/data/providers.dart';
import 'package:tally/features/settings/settings_screen.dart';
import 'package:tally/l10n/l10n.dart';

import 'support/fake_drive.dart';
import 'support/test_db.dart';

/// A connected engine (refresh token + device identity already in meta).
Future<DriveSyncEngine> _connectedEngine(
  AppDatabase db,
  FakeDriveClient drive,
) async {
  await db.setMeta(MetaKeys.googleRefreshToken, 'refresh-A');
  await db.setMeta(MetaKeys.deviceId, 'device-a');
  await db.setMeta(MetaKeys.deviceName, 'Test Device');
  final DriveSyncEngine engine = DriveSyncEngine(
    db,
    auth: FakeDeviceAuth(),
    driveClientFactory: (_) => drive,
  );
  await engine.init();
  return engine;
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  required AppDatabase db,
  required DriveSyncEngine engine,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        databaseProvider.overrideWithValue(db),
        syncEngineProvider.overrideWithValue(engine),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: tallyTheme(Brightness.dark),
        home: const Scaffold(body: SettingsScreen()),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (final int ms in const <int>[100, 300, 500]) {
    await tester.pump(Duration(milliseconds: ms));
  }
}

Future<void> _teardownTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 4));
}

void main() {
  testWidgets('a revoked token offers a way back in, not just Disconnect',
      (WidgetTester tester) async {
    // Regression: `configured` stayed true after SyncError(authRevoked), so
    // the card rendered only "Sync now" + "Disconnect". Every sync failed the
    // same way and the only escape was guessing that Disconnect came first.
    final AppDatabase db = openTestDb();
    addTearDown(db.close);
    final FakeDriveClient drive = FakeDriveClient()
      ..failWith = const DriveException(401, 'authError', 'invalid creds');
    final DriveSyncEngine engine = await _connectedEngine(db, drive);
    addTearDown(engine.dispose);

    expect(await engine.syncNow(), isFalse);
    expect((engine.status as SyncError).code, SyncErrorCode.authExpired);

    await _pumpSettings(tester, db: db, engine: engine);

    expect(find.text('Google access expired — connect Drive again'),
        findsOneWidget);
    expect(find.text('Reconnect Drive'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
    // "Sync now" would only fail again, so it gives up its slot.
    expect(find.text('Sync now'), findsNothing);

    await _teardownTree(tester);
  });

  testWidgets('a healthy connection keeps Sync now + Disconnect',
      (WidgetTester tester) async {
    final AppDatabase db = openTestDb();
    addTearDown(db.close);
    final FakeDriveClient drive = FakeDriveClient();
    final DriveSyncEngine engine = await _connectedEngine(db, drive);
    addTearDown(engine.dispose);
    expect(await engine.syncNow(), isTrue);

    await _pumpSettings(tester, db: db, engine: engine);

    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Sync now'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
    expect(find.text('Reconnect Drive'), findsNothing);

    await _teardownTree(tester);
  });

  testWidgets('Sync now during an in-flight pass reports Synced, not failed',
      (WidgetTester tester) async {
    // Regression: syncNow() returned false for the coalescing case, so tapping
    // the button within 3 s of a local write (or right after a resume) showed
    // "Sync failed" while the status row said "Connected".
    final AppDatabase db = openTestDb();
    addTearDown(db.close);
    final FakeDriveClient drive = FakeDriveClient();
    final DriveSyncEngine engine = await _connectedEngine(db, drive);
    addTearDown(engine.dispose);

    // Hold the very first pass open inside the upload.
    final Completer<void> upload = Completer<void>();
    drive.onBeforeUpload = () async {
      drive.onBeforeUpload = null;
      await upload.future;
    };
    final Future<bool> background = engine.syncNow();

    await _pumpSettings(tester, db: db, engine: engine);
    expect(find.text('Syncing…'), findsOneWidget);

    await tester.tap(find.text('Sync now'));
    await tester.pump();

    // The button stays busy while the queued run is still working…
    expect(find.text('Synced'), findsNothing);
    expect(find.text('Sync failed — see status above'), findsNothing);

    upload.complete();
    expect(await background, isTrue);
    await _settle(tester);

    // …and reports the outcome the pass actually reached.
    expect(find.text('Synced'), findsOneWidget);
    expect(find.text('Sync failed — see status above'), findsNothing);

    await _teardownTree(tester);
  });
}
