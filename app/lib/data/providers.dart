/// Riverpod wiring: db -> repositories -> sync engine -> derived state.
///
/// Plain providers, no codegen. The UI consumes these; nothing below
/// `lib/data/` should be constructed manually by widgets.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

export '../core/constants.dart'
    show
        AccountKind,
        Kind,
        PeriodMode,
        TxSource,
        defaultAccountId,
        defaultCurrency,
        defaultLanguage,
        SeedAccount,
        seedAccounts,
        supportedLanguageCodes,
        driveFolderName;
export '../core/seed_names.dart'
    show
        accountDisplayName,
        canonicalSeedAccountName,
        canonicalSeedName,
        categoryDisplayName,
        isRenamedSeed,
        isSeedAccountId,
        isSeedId,
        isUnrenamedSeed,
        isUnrenamedSeedAccount,
        seedAccountNameKey,
        seedAccountNameKeys,
        seedCategoryNameKeys,
        seedNameKey;
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
export 'repo/accounts_repository.dart' show AccountBalance;
export 'repo/summaries_repository.dart' show PeriodTotals, CategoryTotal;
import '../core/constants.dart';
import '../core/dates.dart';
import 'db/database.dart';
import 'drive/drive_sync_engine.dart';
import 'repo/accounts_repository.dart';
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

final accountsRepoProvider = Provider<AccountsRepository>((ref) {
  return AccountsRepository(
    ref.watch(databaseProvider),
    onMutation: ref.watch(syncEngineProvider).scheduleSync,
  );
});

// ---- app state ---------------------------------------------------------------

/// Month currently shown on Home/Stats (always the first day of a local
/// month). Change it via `ref.read(selectedMonthProvider.notifier).state =
/// addMonths(current, -1)`.
final selectedMonthProvider = StateProvider<DateTime>(
  (ref) => monthStart(DateTime.now()),
);

/// Day currently shown on Home/Stats when the lens is [PeriodMode.day]
/// (always local midnight).
final selectedDayProvider = StateProvider<DateTime>(
  (ref) => dayStart(DateTime.now()),
);

/// The lens Home and Stats are showing: one day or one month. Persisted
/// per-device in the local meta table.
final periodModeProvider =
    StateNotifierProvider<PeriodModeController, PeriodMode>(
  (ref) => PeriodModeController(ref.watch(databaseProvider)),
);

class PeriodModeController extends StateNotifier<PeriodMode> {
  PeriodModeController(this._db) : super(PeriodMode.month) {
    _load();
  }

  final AppDatabase _db;

  Future<void> _load() async {
    final String? raw = await _db.getMeta(MetaKeys.uiPeriodMode);
    if (!mounted) return;
    state = PeriodMode.fromName(raw);
  }

  Future<void> setMode(PeriodMode mode) async {
    state = mode;
    await _db.setMeta(MetaKeys.uiPeriodMode, mode.name);
  }

  Future<void> toggle() => setMode(
      state == PeriodMode.month ? PeriodMode.day : PeriodMode.month);
}

/// First instant of whichever period is currently selected — the single value
/// every period-aware query below keys off, so the two lenses can never drift
/// apart.
final selectedPeriodStartProvider = Provider<DateTime>((ref) =>
    switch (ref.watch(periodModeProvider)) {
      PeriodMode.day => ref.watch(selectedDayProvider),
      PeriodMode.month => ref.watch(selectedMonthProvider),
    });

/// Active ISO-4217 currency code from settings (default 'USD').
final currencyProvider = StreamProvider<String>(
  (ref) => ref.watch(settingsRepoProvider).watchCurrency(),
);

/// Chosen UI language from the SYNCED settings row: '' (follow the device
/// locale), 'en', 'ru' or 'uz'. The Telegram bot reads the same field.
final languageProvider = StreamProvider<String>(
  (ref) => ref.watch(settingsRepoProvider).watchLanguage(),
);

// ---- derived summaries (all follow the selected period lens) ----------------

/// Income / expense / net for the selected period (day or month).
///
/// Transfers are excluded by the repository, so switching a purchase into a
/// "send to savings" moves the balance without touching these numbers.
final periodTotalsProvider = StreamProvider<PeriodTotals>((ref) {
  final repo = ref.watch(summariesRepoProvider);
  return switch (ref.watch(periodModeProvider)) {
    PeriodMode.day => repo.watchDayTotals(ref.watch(selectedDayProvider)),
    PeriodMode.month =>
      repo.watchMonthTotals(ref.watch(selectedMonthProvider)),
  };
});

/// Per-category expense totals for the selected period, largest first.
final periodCategoryTotalsProvider =
    StreamProvider<List<CategoryTotal>>((ref) {
  final repo = ref.watch(summariesRepoProvider);
  return switch (ref.watch(periodModeProvider)) {
    PeriodMode.day =>
      repo.watchDayCategoryTotals(ref.watch(selectedDayProvider)),
    PeriodMode.month =>
      repo.watchCategoryTotals(ref.watch(selectedMonthProvider)),
  };
});

/// Per-category totals for the selected period by kind
/// ('income' | 'expense').
final categoryTotalsByKindProvider =
    StreamProvider.family<List<CategoryTotal>, String>((ref, kind) {
  final repo = ref.watch(summariesRepoProvider);
  return switch (ref.watch(periodModeProvider)) {
    PeriodMode.day => repo.watchDayCategoryTotals(
        ref.watch(selectedDayProvider),
        kind: kind),
    PeriodMode.month =>
      repo.watchCategoryTotals(ref.watch(selectedMonthProvider), kind: kind),
  };
});

/// The trend series under the Stats donut: six months in the month lens,
/// fourteen days in the day lens.
final trendProvider = StreamProvider<List<PeriodTotals>>((ref) {
  final repo = ref.watch(summariesRepoProvider);
  return switch (ref.watch(periodModeProvider)) {
    PeriodMode.day => repo.watchLastDays(ref.watch(selectedDayProvider)),
    PeriodMode.month =>
      repo.watchLastSixMonths(ref.watch(selectedMonthProvider)),
  };
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

/// Transactions in the selected period, newest first. In the day lens this is
/// every entry for that day, not just the most recent handful — the point of
/// the lens is to see the whole day.
final periodTransactionsProvider = StreamProvider<List<Transaction>>((ref) {
  final repo = ref.watch(transactionsRepoProvider);
  return switch (ref.watch(periodModeProvider)) {
    PeriodMode.day => repo.watchDay(ref.watch(selectedDayProvider)),
    PeriodMode.month => repo.watchRecent(limit: 5),
  };
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

// ---- accounts -------------------------------------------------------------

/// Non-deleted accounts, ordered.
final activeAccountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountsRepoProvider).watchActive(),
);

/// ALL accounts, archived included — transactions booked to an archived
/// account must keep resolving their name/emoji/color.
final allAccountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountsRepoProvider).watchAll(),
);

/// Fast id -> Account lookup for lists.
final accountsByIdProvider = Provider<Map<String, Account>>((ref) {
  final accounts = ref.watch(allAccountsProvider).value ?? const [];
  return {for (final a in accounts) a.id: a};
});

/// Every live account with its derived balance, ordered.
final accountBalancesProvider = StreamProvider<List<AccountBalance>>(
  (ref) => ref.watch(accountsRepoProvider).watchBalances(),
);

/// Total across every live account — "how much do I actually have".
final netWorthMinorProvider = Provider<int>((ref) {
  final balances = ref.watch(accountBalancesProvider).value ?? const [];
  return balances.fold<int>(0, (sum, b) => sum + b.balanceMinor);
});

/// The synced id of the account the Telegram bot books its entries to.
final defaultAccountIdProvider = StreamProvider<String>(
  (ref) => ref.watch(settingsRepoProvider).watchDefaultAccountId(),
);
