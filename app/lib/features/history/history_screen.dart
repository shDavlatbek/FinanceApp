/// History — every transaction grouped by day with day subtotals, note
/// search, kind/category filters, tap-to-edit, swipe-to-delete with undo.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../l10n/l10n.dart';
import '../common/cards.dart';
import '../common/empty_state.dart';
import '../common/format.dart';
import '../common/transaction_tile.dart';
import '../entry/entry_sheet.dart';
import 'package:tally/data/providers.dart';

// ---- filter state -------------------------------------------------------------

final historyQueryProvider = StateProvider<String>((_) => '');
final historyKindProvider = StateProvider<String?>((_) => null);
final historyCategoryProvider = StateProvider<String?>((_) => null);

final historyTransactionsProvider = StreamProvider<List<Transaction>>((ref) {
  final query = ref.watch(historyQueryProvider).trim();
  final kind = ref.watch(historyKindProvider);
  final categoryId = ref.watch(historyCategoryProvider);
  return ref.watch(transactionsRepoProvider).watchFiltered(
        noteQuery: query.isEmpty ? null : query,
        kind: kind,
        categoryId: categoryId,
      );
});

// ---- screen ----------------------------------------------------------------------

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late final TextEditingController _search;
  Timer? _debounce;

  /// Rows swiped away but not yet gone from the stream.
  final Set<String> _pendingDeletes = {};

  /// Keys the AnimatedItemList should drop without re-animating.
  final Set<Object> _dismissed = {};

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: ref.read(historyQueryProvider));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        ref.read(historyQueryProvider.notifier).state = value;
      }
    });
  }

  Future<void> _delete(Transaction tx) async {
    HapticFeedback.mediumImpact();
    _dismissed.add(tx.id);
    setState(() => _pendingDeletes.add(tx.id));
    final repo = ref.read(transactionsRepoProvider);
    final currency = ref.read(currencyProvider).value ?? defaultCurrency;
    final l10n = context.l10n;
    final locale = context.localeTag;
    // Notes identify a row better than anything else; fall back to the
    // formatted amount when the row has none.
    final label = tx.note.isEmpty
        ? formatSignedMinor(tx.amountMinor, tx.kind, currency, locale: locale)
        : tx.note;
    await repo.softDelete(tx.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.historyDeletedItem(label: label)),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: l10n.commonUndo,
            onPressed: () => repo.insert(
              kind: tx.kind,
              amountMinor: tx.amountMinor,
              categoryId: tx.categoryId,
              note: tx.note,
              occurredAt: occurredAtToLocal(tx.occurredAt),
              source: tx.source,
            ),
          ),
        ),
      );
  }

  /// Places a dragged entry and persists the whole day's new order.
  ///
  /// Reordering is per-day: the ids handed to the repository are exactly the
  /// rows of one local day, numbered 1..N in the order shown.
  Future<void> _reorder(
    List<Transaction> dayTxs,
    int oldIndex,
    int newIndex,
  ) async {
    // onReorderItem (unlike the deprecated onReorder) already accounts for the
    // dragged row being lifted out, so newIndex needs no adjustment here.
    if (newIndex == oldIndex) return;

    final List<Transaction> next = <Transaction>[...dayTxs];
    next.insert(newIndex, next.removeAt(oldIndex));
    HapticFeedback.selectionClick();
    await ref
        .read(transactionsRepoProvider)
        .reorderDay(<String>[for (final Transaction t in next) t.id]);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final currency = ref.watch(currencyProvider).value ?? defaultCurrency;
    final kindFilter = ref.watch(historyKindProvider);
    final categoryFilter = ref.watch(historyCategoryProvider);
    final query = ref.watch(historyQueryProvider);
    final all = ref.watch(historyTransactionsProvider).value ??
        const <Transaction>[];
    final txs =
        all.where((tx) => !_pendingDeletes.contains(tx.id)).toList();
    final hasFilters = query.trim().isNotEmpty ||
        kindFilter != null ||
        categoryFilter != null;

    // Group by local day, preserving newest-first order.
    final groups = <String, List<Transaction>>{};
    for (final tx in txs) {
      groups.putIfAbsent(dayKeyFromOccurredAt(tx.occurredAt), () => []).add(tx);
    }
    final dayKeys = groups.keys.toList();

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.historyTitle, style: theme.titleLarge),
                const SizedBox(height: 14),
                TextField(
                  controller: _search,
                  onChanged: _onQueryChanged,
                  style: theme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: l10n.historySearchHint,
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 20, color: t.textSecondary),
                    suffixIcon: query.isEmpty
                        ? null
                        : GestureDetector(
                            onTap: () {
                              _search.clear();
                              ref
                                  .read(historyQueryProvider.notifier)
                                  .state = '';
                            },
                            child: Icon(Icons.close_rounded,
                                size: 18, color: t.textSecondary),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                _FilterRow(
                  kind: kindFilter,
                  categoryId: categoryFilter,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(syncEngineProvider).syncNow(),
              child: txs.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 60),
                        hasFilters
                            ? EmptyState(
                                emoji: '🔍',
                                title: l10n.historyNoMatchesTitle,
                                message: l10n.historyNoMatchesMessage,
                              )
                            : EmptyState(
                                emoji: '🧾',
                                title: l10n.historyEmptyTitle,
                                message: l10n.historyEmptyMessage,
                                actionLabel: l10n.commonAddEntry,
                                onAction: () => showEntrySheet(context),
                              ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics()),
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                      itemCount: dayKeys.length,
                      itemBuilder: (context, index) {
                        final key = dayKeys[index];
                        final dayTxs = groups[key]!;
                        return _DayGroup(
                          key: ValueKey(key),
                          dayKeyStr: key,
                          txs: dayTxs,
                          currency: currency,
                          dismissed: _dismissed,
                          onDelete: _delete,
                          onReorder: _reorder,
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- day group ------------------------------------------------------------------

class _DayGroup extends StatelessWidget {
  const _DayGroup({
    super.key,
    required this.dayKeyStr,
    required this.txs,
    required this.currency,
    required this.dismissed,
    required this.onDelete,
    required this.onReorder,
  });

  final String dayKeyStr;
  final List<Transaction> txs;
  final String currency;
  final Set<Object> dismissed;
  final Future<void> Function(Transaction) onDelete;
  final Future<void> Function(List<Transaction>, int, int) onReorder;

  String _title(BuildContext context) {
    final now = DateTime.now();
    if (dayKeyStr == dayKey(now)) return context.l10n.commonToday;
    if (dayKeyStr == dayKey(now.subtract(const Duration(days: 1)))) {
      return context.l10n.commonYesterday;
    }
    final parts = dayKeyStr.split('-').map(int.parse).toList();
    return dayLabel(
      DateTime(parts[0], parts[1], parts[2]),
      locale: context.localeTag,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    var net = 0;
    for (final tx in txs) {
      // Transfers move money between the owner's own accounts, so they are
      // neither a gain nor a loss for the day and must not move this subtotal.
      if (tx.kind == Kind.transfer) continue;
      net += tx.kind == Kind.income ? tx.amountMinor : -tx.amountMinor;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(
              children: [
                Text(_title(context).toUpperCase(), style: theme.labelSmall),
                const Spacer(),
                Text(
                  signedNetMoney(net, currency, locale: context.localeTag),
                  style: money(theme.labelMedium!).copyWith(
                    color: net >= 0 ? t.income : t.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Long-press to drag, swipe to delete. ReorderableListView replaces
          // AnimatedItemList here — it cannot animate inserts, but placing an
          // entry by hand is what this screen is for, and Dismissible still
          // animates its own dismissal.
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: txs.length,
            onReorderItem: (int oldIndex, int newIndex) =>
                onReorder(txs, oldIndex, newIndex),
            proxyDecorator: _liftedTile,
            itemBuilder: (BuildContext context, int i) {
              final Transaction tx = txs[i];
              return ReorderableDelayedDragStartListener(
                key: ValueKey<String>('reorder-${tx.id}'),
                index: i,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SwipeableTile(tx: tx, onDelete: onDelete),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The dragged row while it is in the air: lifted slightly, no Material
/// elevation shadow (DESIGN.md: hairline borders, never drop-shadow soup).
Widget _liftedTile(Widget child, int index, Animation<double> animation) {
  return AnimatedBuilder(
    animation: animation,
    builder: (BuildContext context, Widget? inner) {
      final double lift = Curves.easeOutCubic.transform(animation.value);
      return Transform.scale(
        scale: 1 + 0.03 * lift,
        child: Material(
          color: Colors.transparent,
          child: Opacity(opacity: 1 - 0.12 * lift, child: inner),
        ),
      );
    },
    child: child,
  );
}

class _SwipeableTile extends StatelessWidget {
  const _SwipeableTile({required this.tx, required this.onDelete});

  final Transaction tx;
  final Future<void> Function(Transaction) onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Dismissible(
        key: ValueKey('dismiss-${tx.id}'),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onDelete(tx),
        background: Container(
          color: t.danger,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: const Icon(Icons.delete_outline_rounded,
              color: Colors.white, size: 22),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.border),
          ),
          child: TransactionTile(
            tx: tx,
            onTap: () => showEntrySheet(context, existing: tx),
          ),
        ),
      ),
    );
  }
}

// ---- filters ---------------------------------------------------------------------

class _FilterRow extends ConsumerWidget {
  const _FilterRow({required this.kind, required this.categoryId});

  final String? kind;
  final String? categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l10n = context.l10n;
    final categories = ref.watch(categoriesByIdProvider);
    final selectedCategory =
        categoryId == null ? null : categories[categoryId];

    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
      IconData? icon,
      VoidCallback? onClear,
    }) {
      return GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? t.accent.withValues(alpha: 0.16)
                : t.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? t.accent : t.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 14,
                    color: selected ? t.textPrimary : t.textSecondary),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium!.copyWith(
                      color: selected ? t.textPrimary : t.textSecondary,
                    ),
              ),
              if (onClear != null) ...[
                const SizedBox(width: 5),
                GestureDetector(
                  onTap: onClear,
                  child: Icon(Icons.close_rounded,
                      size: 14, color: t.textSecondary),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(
            label: l10n.commonAll,
            selected: kind == null,
            onTap: () =>
                ref.read(historyKindProvider.notifier).state = null,
          ),
          const SizedBox(width: 8),
          chip(
            label: l10n.commonExpenses,
            selected: kind == Kind.expense,
            onTap: () =>
                ref.read(historyKindProvider.notifier).state = Kind.expense,
          ),
          const SizedBox(width: 8),
          chip(
            label: l10n.commonIncome,
            selected: kind == Kind.income,
            onTap: () =>
                ref.read(historyKindProvider.notifier).state = Kind.income,
          ),
          const SizedBox(width: 8),
          chip(
            label: selectedCategory == null
                ? l10n.historyCategoryFilter
                : '${selectedCategory.emoji} '
                    '${context.categoryName(id: selectedCategory.id, name: selectedCategory.name)}',
            icon: selectedCategory == null
                ? Icons.filter_list_rounded
                : null,
            selected: selectedCategory != null,
            onTap: () => _pickCategory(context, ref),
            onClear: selectedCategory == null
                ? null
                : () =>
                    ref.read(historyCategoryProvider.notifier).state = null,
          ),
        ],
      ),
    );
  }

  void _pickCategory(BuildContext context, WidgetRef ref) {
    showTallySheet<void>(
      context,
      builder: (sheetContext) => Consumer(
        builder: (context, ref2, _) {
          final cats = ref2.watch(allActiveCategoriesProvider).value ??
              const <Category>[];
          final theme = Theme.of(context).textTheme;
          final t = context.tokens;
          final l10n = context.l10n;
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                child: Text(l10n.historyFilterByCategoryTitle,
                    style: theme.titleMedium),
              ),
              for (final c in cats)
                ListTile(
                  onTap: () {
                    ref.read(historyCategoryProvider.notifier).state = c.id;
                    Navigator.of(sheetContext).pop();
                  },
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color:
                          colorFromHex(c.color).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                        child: Text(c.emoji,
                            style: const TextStyle(fontSize: 17))),
                  ),
                  title: Text(
                      context.categoryName(id: c.id, name: c.name),
                      style: theme.bodyLarge!
                          .copyWith(fontWeight: FontWeight.w600)),
                  trailing: c.id == categoryId
                      ? Icon(Icons.check_rounded, color: t.accent)
                      : Text(
                          c.kind == Kind.income
                              ? l10n.commonIncome
                              : l10n.commonExpense,
                          style: theme.bodySmall,
                        ),
                ),
            ],
          );
        },
      ),
    );
  }
}
