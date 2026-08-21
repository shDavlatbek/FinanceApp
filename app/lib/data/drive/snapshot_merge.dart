/// The one snapshot merge, and the one local-state read that feeds a snapshot.
///
/// Both the Drive sync engine and file import go through here, because both
/// consume the *same* format: a backup file IS a peer snapshot
/// (docs/ARCHITECTURE.md § Export and import). Keeping a single merge means
/// there is one last-write-wins rule to get right, not two that drift apart.
///
/// The rule, verbatim from the contract: a row in the incoming snapshot is
/// applied iff it is unknown locally **or** its `updated_at_ms` is strictly
/// newer. A tie keeps the local row. That is what makes importing the same
/// file twice a no-op and makes importing an old backup unable to clobber
/// newer work.
library;

import '../../core/constants.dart';
import '../db/database.dart';
import 'snapshot.dart';

/// One peer's full local state — exactly what gets serialized into its own
/// snapshot file, tombstones included.
class LocalSnapshotState {
  const LocalSnapshotState(
      this.accounts, this.categories, this.transactions, this.settings);

  final List<Account> accounts;
  final List<Category> categories;
  final List<Transaction> transactions;
  final SettingsRow? settings;

  bool get hasDirty =>
      accounts.any((Account a) => a.dirty) ||
      categories.any((Category c) => c.dirty) ||
      transactions.any((Transaction t) => t.dirty) ||
      (settings?.dirty ?? false);
}

/// Reads everything a snapshot carries. Tombstones are included on purpose:
/// a full dump with tombstones is what makes the merge self-healing.
Future<LocalSnapshotState> readLocalSnapshotState(AppDatabase db) async {
  final List<Account> accounts = await db.select(db.accounts).get();
  final List<Category> categories = await db.select(db.categories).get();
  final List<Transaction> transactions = await db.select(db.transactions).get();
  final SettingsRow? settings = await (db.select(db.settings)
        ..where((r) => r.id.equals(settingsRowId)))
      .getSingleOrNull();
  return LocalSnapshotState(accounts, categories, transactions, settings);
}

/// How many rows a merge actually applied, per table.
///
/// These count rows **written**, not rows seen: a row the file carries but
/// last-write-wins rejected is not counted. That is precisely the number worth
/// showing after an import — "nothing changed" is the honest answer when the
/// same backup is imported twice.
class SnapshotMergeResult {
  const SnapshotMergeResult({
    this.accounts = 0,
    this.categories = 0,
    this.transactions = 0,
    this.settings = false,
    this.skipped = const <String>[],
  });

  final int accounts;
  final int categories;
  final int transactions;

  /// Whether the settings singleton (currency / language / default account)
  /// was taken from the file.
  final bool settings;

  /// Rows the sanitizer dropped, with a reason each — surfaced, never silent.
  final List<String> skipped;

  int get rows => accounts + categories + transactions;

  bool get isEmpty => rows == 0 && !settings;
}

/// Merges peer snapshots into [db] under strict last-write-wins, atomically.
///
/// [markDirty] is the one difference between the two callers. A row arriving
/// over Drive is already published by the peer that wrote it, so it stays
/// clean. A row arriving from an imported FILE is published nowhere, so this
/// peer has to carry it to Drive on the next pass or the restore would live
/// only on this device. `updated_at_ms` is deliberately NOT bumped in either
/// case: republishing a row as-is keeps the peers' LWW race fair.
Future<SnapshotMergeResult> mergeSnapshots(
  AppDatabase db,
  List<TallySnapshot> snapshots, {
  bool markDirty = false,
}) async {
  int accountsApplied = 0;
  int categoriesApplied = 0;
  int transactionsApplied = 0;
  bool settingsApplied = false;
  final List<String> skipped = <String>[];

  await db.transaction(() async {
    for (final TallySnapshot s in snapshots) {
      skipped.addAll(s.skipped);
      // Accounts first: a transaction naming a brand-new account should not
      // be able to land in a pass where the account itself has not arrived.
      for (final Account incoming in s.accounts) {
        final Account? existing = await (db.select(db.accounts)
              ..where((a) => a.id.equals(incoming.id)))
            .getSingleOrNull();
        if (existing == null || incoming.updatedAtMs > existing.updatedAtMs) {
          await db
              .into(db.accounts)
              .insertOnConflictUpdate(incoming.copyWith(dirty: markDirty));
          accountsApplied++;
        }
      }
      for (final Category incoming in s.categories) {
        final Category? existing = await (db.select(db.categories)
              ..where((c) => c.id.equals(incoming.id)))
            .getSingleOrNull();
        if (existing == null || incoming.updatedAtMs > existing.updatedAtMs) {
          await db
              .into(db.categories)
              .insertOnConflictUpdate(incoming.copyWith(dirty: markDirty));
          categoriesApplied++;
        }
      }
      for (final Transaction incoming in s.transactions) {
        final Transaction? existing = await (db.select(db.transactions)
              ..where((t) => t.id.equals(incoming.id)))
            .getSingleOrNull();
        if (existing == null || incoming.updatedAtMs > existing.updatedAtMs) {
          await db
              .into(db.transactions)
              .insertOnConflictUpdate(incoming.copyWith(dirty: markDirty));
          transactionsApplied++;
        }
      }
      final SettingsRow? incomingSettings = s.settings;
      if (incomingSettings != null) {
        final SettingsRow? existing = await (db.select(db.settings)
              ..where((r) => r.id.equals(incomingSettings.id)))
            .getSingleOrNull();
        if (existing == null ||
            incomingSettings.updatedAtMs > existing.updatedAtMs) {
          // An empty default_account_id means "unchanged", never "cleared":
          // a peer predating accounts sends the field absent, and taking
          // that literally would strip an account the owner deliberately
          // picked in the app. Fall back to the seed account only when
          // there is no local value at all.
          final SettingsRow merged = incomingSettings.defaultAccountId.isEmpty
              ? incomingSettings.copyWith(
                  defaultAccountId:
                      (existing != null && existing.defaultAccountId.isNotEmpty)
                          ? existing.defaultAccountId
                          : defaultAccountId,
                )
              : incomingSettings;
          await db
              .into(db.settings)
              .insertOnConflictUpdate(merged.copyWith(dirty: markDirty));
          settingsApplied = true;
        }
      }
    }
  });

  return SnapshotMergeResult(
    accounts: accountsApplied,
    categories: categoriesApplied,
    transactions: transactionsApplied,
    settings: settingsApplied,
    skipped: skipped,
  );
}
