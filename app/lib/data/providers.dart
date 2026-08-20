/// Riverpod wiring: db -> repositories -> sync engine -> derived state.
///
/// Plain providers, no codegen. The UI consumes these; nothing below
/// `lib/data/` should be constructed manually by widgets.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

export '../core/constants.dart'
    show
        Kind,
        TxSource,
        defaultCurrency,
        defaultLanguage,
        supportedLanguageCodes,
        driveFolderName;
export '../core/seed_names.dart'
    show
        categoryDisplayName,
        canonicalSeedName,
        isSeedId,
        isRenamedSeed,
        isUnrenamedSeed,
        seedNameKey,
        seedCategoryNameKeys;
export 'db/database.dart';
export 'drive/device_auth.dart'
    show DeviceAuthClient, DeviceAuthException, DeviceAuthPrompt;
export 'drive/drive_sync_engine.dart'
    show
        DriveConnection,
        DriveSyncEngine,
        SyncStatus,
        SyncNotConfigured,
        SyncIdle,
        SyncSyncing,
        SyncOffline,
        SyncError,
        SyncErrorCode;
export 'repo/summaries_repository.dart' show MonthTotals, CategoryTotal;
import '../core/dates.dart';
import 'db/database.dart';
import 'drive/drive_sync_engine.dart';
import 'repo/categories_repository.dart';
import 'repo/settings_repository.dart';
import 'repo/summaries_repository.dart';
import 'repo/transactions_repository.dart';

// ---- infrastructure --------------------------------------------------------

/// The app database. Overridden in tests with
/// `AppDatabase(NativeDatabase.memory())`.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});

/// The Google Drive sync engine. Initialized (token loaded from meta) on
/// creation; the status stream updates when the load finishes.
final syncEngineProvider = Provider<DriveSyncEngine>((ref) {
  final engine = DriveSyncEngine(ref.watch(databaseProvider));
  engine.init(); // fire-and-forget; syncNow() awaits the same memoized future
  ref.onDispose(engine.dispose);
  return engine;
});

/// Summary of the connected Drive folder + this device, or null in
/// standalone mode. Refreshed by invalidating this provider after connect /
/// disconnect.
final driveConnectionProvider = FutureProvider<DriveConnection?>(
  (ref) => ref.watch(syncEngineProvider).connectionInfo(),
);

/// notConfigured | idle | syncing | offline | error(message).
final syncStatusProvider = StreamProvider<SyncStatus>(
  (ref) => ref.watch(syncEngineProvider).statusStream,
);

/// Unix-ms of the last successful sync (null = never). Reactive.
final lastSyncMsProvider = StreamProvider<int?>(
  (ref) => ref.watch(syncEngineProvider).lastSyncMsStream,
);

// ---- repositories -----------------------------------------------------------

final transactionsRepoProvider = Provider<TransactionsRepository>((ref) {
  return TransactionsRepository(
    ref.watch(databaseProvider),
    onMutation: ref.watch(syncEngineProvider).scheduleSync,
  );
});

final categoriesRepoProvider = Provider<CategoriesRepository>((ref) {
  return CategoriesRepository(
    ref.watch(databaseProvider),
    onMutation: ref.watch(syncEngineProvider).scheduleSync,
  );
});

final settingsRepoProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(
    ref.watch(databaseProvider),
    onMutation: ref.watch(syncEngineProvider).scheduleSync,
  );
});

final summariesRepoProvider = Provider<SummariesRepository>(
  (ref) => SummariesRepository(ref.watch(databaseProvider)),
);

// ---- app state ---------------------------------------------------------------

/// Month currently shown on Home/Stats (always the first day of a local
/// month). Change it via `ref.read(selectedMonthProvider.notifier).state =
/// addMonths(current, -1)`.
final selectedMonthProvider = StateProvider<DateTime>(
  (ref) => monthStart(DateTime.now()),
);

/// Active ISO-4217 currency code from settings (default 'USD').
final currencyProvider = StreamProvider<String>(
  (ref) => ref.watch(settingsRepoProvider).watchCurrency(),
);

/// Chosen UI language from the SYNCED settings row: '' (follow the device
/// locale), 'en', 'ru' or 'uz'. The Telegram bot reads the same field.
final languageProvider = StreamProvider<String>(
  (ref) => ref.watch(settingsRepoProvider).watchLanguage(),
);

// ---- derived summaries (all follow selectedMonthProvider) --------------------

/// Income / expense / net for the selected month.
final monthTotalsProvider = StreamProvider<MonthTotals>((ref) {
  final month = ref.watch(selectedMonthProvider);
  return ref.watch(summariesRepoProvider).watchMonthTotals(month);
});

/// Per-category expense totals for the selected month, largest first.
final categoryTotalsProvider = StreamProvider<List<CategoryTotal>>((ref) {
  final month = ref.watch(selectedMonthProvider);
  return ref.watch(summariesRepoProvider).watchCategoryTotals(month);
});

/// Per-category totals for the selected month by kind
/// ('income' | 'expense').
final categoryTotalsByKindProvider =
    StreamProvider.family<List<CategoryTotal>, String>((ref, kind) {
  final month = ref.watch(selectedMonthProvider);
  return ref
      .watch(summariesRepoProvider)
      .watchCategoryTotals(month, kind: kind);
});

/// Six months of totals ending at the selected month (oldest first).
final lastSixMonthsProvider = StreamProvider<List<MonthTotals>>((ref) {
  final month = ref.watch(selectedMonthProvider);
  return ref.watch(summariesRepoProvider).watchLastSixMonths(month);
});

// ---- transaction lists ---------------------------------------------------------

/// The 5 most recent transactions (Home "Recent" list).
final recentTransactionsProvider = StreamProvider<List<Transaction>>(
  (ref) => ref.watch(transactionsRepoProvider).watchRecent(limit: 5),
);

/// All transactions in the selected month, newest first (History).
final monthTransactionsProvider = StreamProvider<List<Transaction>>((ref) {
  final month = ref.watch(selectedMonthProvider);
  return ref.watch(transactionsRepoProvider).watchMonth(month);
});

// ---- categories -----------------------------------------------------------------

/// Active categories of a kind ('income' | 'expense'), ordered.
final activeCategoriesProvider =
    StreamProvider.family<List<Category>, String>((ref, kind) {
  return ref.watch(categoriesRepoProvider).watchActive(kind: kind);
});

/// All active categories (both kinds), ordered. For pickers only.
final allActiveCategoriesProvider = StreamProvider<List<Category>>(
  (ref) => ref.watch(categoriesRepoProvider).watchActive(),
);

/// ALL categories, archived ones included (id lookups must keep resolving
/// categories that historical transactions still reference).
final allCategoriesProvider = StreamProvider<List<Category>>(
  (ref) => ref.watch(categoriesRepoProvider).watchAll(),
);

/// Fast id -> Category lookup for lists. Includes archived categories so
/// transactions referencing them keep their name/emoji/color.
final categoriesByIdProvider = Provider<Map<String, Category>>((ref) {
  final cats = ref.watch(allCategoriesProvider).value ?? const [];
  return {for (final c in cats) c.id: c};
});
