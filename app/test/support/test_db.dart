/// Shared test helper: opens in-memory AppDatabases for tests.
///
/// package:sqlite3 >= 3.x ships the native sqlite3 library via Dart build
/// hooks (native assets), so no manual DLL loading is needed on Windows.
/// If loading ever fails on a host, download the official x64 sqlite3 DLL
/// and pre-load it here with `DynamicLibrary.open` before the first query.
library;

import 'package:drift/native.dart';

import 'package:tally/data/db/database.dart';

/// A fresh in-memory [AppDatabase] (schema created + seeds inserted lazily on
/// first use). Callers must `close()` it.
AppDatabase openTestDb() => AppDatabase(NativeDatabase.memory());
