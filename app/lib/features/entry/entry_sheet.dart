/// Full-height transaction entry sheet — springy slide-up, live-formatted
/// oversized amount, custom numpad, kind pill, emoji category grid, note and
/// date chips. Also used to edit an existing transaction.
///
/// Three kinds share the sheet. An expense or an income picks a category and
/// the account the money moves through; a **transfer** picks two accounts and
/// no category at all, because moving your own money between your own pockets
/// is not spending and must stay out of every total
/// (docs/ARCHITECTURE.md § transaction).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../l10n/l10n.dart';
import '../common/account_chip.dart';
import '../common/buttons.dart';
import '../common/kind_pill.dart';
import 'numpad.dart';
import 'package:tally/data/providers.dart';

/// Opens the sheet as a custom route: springy slide-up (easeOutBack, 420 ms),
/// clean ease-in on the way down.
///
/// [initialKind] and [initialToAccountId] are what make "send to savings" one
/// tap: the Accounts screen opens the sheet already in transfer mode with the
/// destination chosen, leaving only the amount to type. Both are ignored when
/// [existing] is given — an edit always starts from the row on screen.
Future<void> showEntrySheet(
  BuildContext context, {
  Transaction? existing,
  String? initialKind,
  String? initialToAccountId,
}) {
  final surface = context.tokens.surface;
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => EntrySheet(
        existing: existing,
        initialKind: initialKind,
        initialToAccountId: initialToAccountId,
      ),
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          // Bleed below the sheet so the spring overshoot never shows a gap.
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: -80,
                height: 80,
                child: ColoredBox(color: surface),
              ),
              child,
            ],
          ),
        );
      },
    ),
  );
}

class EntrySheet extends ConsumerStatefulWidget {
  const EntrySheet({
    super.key,
    this.existing,
    this.initialKind,
    this.initialToAccountId,
  });

  final Transaction? existing;

  /// `Kind.expense` (the default), `Kind.income` or `Kind.transfer`.
  final String? initialKind;

  /// Pre-chosen transfer destination, for the Accounts screen's one-tap
  /// "send to savings".
  final String? initialToAccountId;

  @override
  ConsumerState<EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends ConsumerState<EntrySheet> {
  late String _kind;
  late String _raw;
  String? _categoryId;

  /// The account money moves through — where an expense leaves from, where an
  /// income arrives, and the SOURCE of a transfer. Null means "not chosen by
  /// hand", which resolves to the synced default account at save time.
  String? _accountId;

  /// The DESTINATION of a transfer, and empty for every other kind.
  String? _toAccountId;
  late DateTime _date;
  late final TextEditingController _note;
  bool _saving = false;

  bool get _editing => widget.existing != null;
  bool get _isTransfer => _kind == Kind.transfer;

  @override
  void initState() {
    super.initState();
    final tx = widget.existing;
    final currency = ref.read(currencyProvider).value ?? defaultCurrency;
    _kind = tx?.kind ??
        (Kind.isValidTransaction(widget.initialKind ?? '')
            ? widget.initialKind!
            : Kind.expense);
    _raw = tx == null ? '' : minorToEditable(tx.amountMinor, currency);
    // A transfer stores an EMPTY category by contract; carrying that through
    // as `''` would look like a chosen category and let Save through with a
    // row no peer would accept.
    _categoryId = (tx == null || tx.categoryId.isEmpty) ? null : tx.categoryId;
    _accountId = tx?.accountId;
    _toAccountId = tx == null
        ? widget.initialToAccountId
        : (tx.toAccountId.isEmpty ? null : tx.toAccountId);
    _date = tx == null ? DateTime.now() : occurredAtToLocal(tx.occurredAt);
    _note = TextEditingController(text: tx?.note ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// The source account this sheet will actually write, given the live account
  /// list and the synced default.
  ///
  /// Falling back to the default account is what keeps the sheet a one-tap
  /// flow: most entries come out of the same pocket, so the picker is there to
  /// override the default, not to be answered every time.
  String? _resolveFrom(List<Account> accounts, String settingsDefault) {
    if (_accountId != null) return _accountId;
    // A transfer whose destination is already the default account would open
    // on an invalid self-transfer, so the source steps aside to another one.
    final String? avoid = _isTransfer ? _toAccountId : null;
    if (settingsDefault != avoid &&
        accounts.any((Account a) => a.id == settingsDefault)) {
      return settingsDefault;
    }
    // The default names an archived account (or none has loaded yet). Fall
    // back to the first live one, never to an archived id — writes must not go
    // into a hole. Same rule as `AccountsRepository.resolveDefault`.
    for (final Account a in accounts) {
      if (a.id != avoid) return a.id;
    }
    return null;
  }

  void _onDigit(String d, int decimals) {
    setState(() {
      final dot = _raw.indexOf('.');
      if (dot >= 0) {
        if (_raw.length - dot - 1 >= decimals) return;
        _raw += d;
      } else {
        if (_raw.length >= 9) return;
        _raw = _raw == '0' ? d : _raw + d;
      }
    });
  }

  void _onDecimal() {
    if (_raw.contains('.')) return;
    setState(() => _raw = _raw.isEmpty ? '0.' : '$_raw.');
  }

  void _onBackspace() {
    if (_raw.isEmpty) return;
    setState(() => _raw = _raw.substring(0, _raw.length - 1));
  }

  void _setKind(String kind) {
    if (kind == _kind) return;
    setState(() {
      _kind = kind;
      // Categories are per-kind, so the old pick is meaningless under the new
      // one. The two account choices survive the switch: they are still the
      // same pockets, and re-picking them would be busywork.
      _categoryId = null;
    });
  }

  void _setToday() {
    // Keep the time the user set; only the DAY is being changed.
    setState(() => _date = _withDay(DateTime.now()));
  }

  void _setYesterday() {
    final y = DateTime.now().subtract(const Duration(days: 1));
    setState(() => _date = _withDay(y));
  }

  /// [day]'s calendar date carrying the time already chosen. Changing the day
  /// must never silently move an entry to noon.
  DateTime _withDay(DateTime day) =>
      DateTime(day.year, day.month, day.day, _date.hour, _date.minute);

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = DateTime(
          _date.year,
          _date.month,
          _date.day,
          picked.hour,
          picked.minute,
        ));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => _date = _withDay(picked));
    }
  }

  Future<void> _save(int minor, String fromId) async {
    if (_saving) return;
    final String? toId = _toAccountId;
    if (_isTransfer) {
      // Guarded here as well as in the disabled button: a self-transfer is a
      // no-op that would still show in history as money moving, and the
      // repository throws on it.
      if (toId == null || toId == fromId) return;
    } else if (_categoryId == null) {
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(transactionsRepoProvider);
    final note = _note.text.trim();
    if (_editing) {
      await repo.update(
        id: widget.existing!.id,
        kind: _kind,
        amountMinor: minor,
        // Switching an expense INTO a transfer has to clear the category, and
        // switching back has to clear the destination. Leaving either behind
        // would keep a field the row's kind forbids, which the peers' sanitizer
        // then rewrites underneath us.
        categoryId: _isTransfer ? '' : _categoryId,
        accountId: fromId,
        toAccountId: _isTransfer ? toId : '',
        note: note,
        occurredAt: _date,
      );
    } else if (_isTransfer) {
      // One row with two account ids — never a matched expense/income pair,
      // which could half-arrive or be half-deleted under last-write-wins.
      await repo.insertTransfer(
        amountMinor: minor,
        fromAccountId: fromId,
        toAccountId: toId!,
        note: note,
        occurredAt: _date,
      );
    } else {
      await repo.insert(
        kind: _kind,
        amountMinor: minor,
        categoryId: _categoryId!,
        accountId: fromId,
        note: note,
        occurredAt: _date,
      );
    }
    HapticFeedback.mediumImpact();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final tx = widget.existing!;
    final repo = ref.read(transactionsRepoProvider);
    final messenger = ScaffoldMessenger.of(context);
    final currency = ref.read(currencyProvider).value ?? defaultCurrency;
    final l10n = context.l10n;
    final locale = context.localeTag;
    await repo.softDelete(tx.id);
    if (mounted) Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.entryDeleted(
          amount: formatSignedMinor(
            tx.amountMinor,
            tx.kind,
            currency,
            locale: locale,
          ),
        )),
        action: SnackBarAction(
          label: l10n.commonUndo,
          // Lifts the tombstone off the SAME row. Re-inserting minted a new id
          // and rebuilt the row from the fields this call remembered to pass,
          // which silently dropped account_id, to_account_id and sort_order —
          // an undone transfer came back with no destination, i.e. a row the
          // peers throw away.
          onPressed: () => repo.restore(tx.id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final currency = ref.watch(currencyProvider).value ?? defaultCurrency;
    final decimals = decimalDigitsFor(currency);
    final minor = parseAmountToMinor(_raw, currencyCode: currency);
    final List<Account> accounts =
        ref.watch(activeAccountsProvider).value ?? const <Account>[];
    final String settingsDefault =
        ref.watch(defaultAccountIdProvider).value ?? defaultAccountId;
    final String? fromId = _resolveFrom(accounts, settingsDefault);
    final bool transferReady = _toAccountId != null &&
        fromId != null &&
        _toAccountId != fromId;
    final canSave = minor != null &&
        fromId != null &&
        !_saving &&
        (_isTransfer ? transferReady : _categoryId != null);
    final topGap = MediaQuery.paddingOf(context).top + 14;

    return Column(
      children: [
        // Tap the exposed strip above the sheet to dismiss.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pop(),
          child: SizedBox(height: topGap),
        ),
        Expanded(
          child: GestureDetector(
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) > 700) {
                Navigator.of(context).pop();
              }
            },
            child: Container(
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: t.border),
              ),
              child: Scaffold(
                backgroundColor: Colors.transparent,
                resizeToAvoidBottomInset: true,
                body: SafeArea(
                  top: false,
                  // Scrolls only when the screen is too short for the fixed
                  // numpad + grid stack; otherwise the amount area flexes.
                  child: LayoutBuilder(
                    builder: (context, viewport) => SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: viewport.maxHeight),
                        child: IntrinsicHeight(
                          child: Column(
                            children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: t.textSecondary.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                        child: Row(
                          children: [
                            Text(
                                _editing
                                    ? l10n.entryEditTitle
                                    : l10n.entryNewTitle,
                                style: theme.titleMedium),
                            const Spacer(),
                            if (_editing)
                              IconButton(
                                onPressed: _delete,
                                icon: Icon(Icons.delete_outline_rounded,
                                    color: t.danger, size: 22),
                              ),
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: Icon(Icons.close_rounded,
                                  color: t.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: _AmountDisplay(
                            raw: _raw,
                            currency: currency,
                            kind: _kind,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: KindPill(
                          value: _kind,
                          onChanged: _setKind,
                          options: kTransactionKindOptions,
                        ),
                      ),
                      const SizedBox(height: 14),
                      // A transfer has no category by contract, so the grid is
                      // replaced rather than disabled: the two pickers ARE the
                      // choice being made.
                      if (_isTransfer)
                        _TransferPickers(
                          accounts: accounts,
                          fromId: fromId,
                          toId: _toAccountId,
                          onFrom: (id) {
                            HapticFeedback.selectionClick();
                            setState(() => _accountId = id);
                          },
                          onTo: (id) {
                            HapticFeedback.selectionClick();
                            setState(() => _toAccountId = id);
                          },
                        )
                      else ...[
                        _CategoryGrid(
                          kind: _kind,
                          selectedId: _categoryId,
                          onSelect: (id) {
                            HapticFeedback.selectionClick();
                            setState(() => _categoryId = id);
                          },
                        ),
                        const SizedBox(height: 10),
                        AccountStrip(
                          label: l10n.entryAccountLabel,
                          accounts: accounts,
                          selectedId: fromId,
                          onSelect: (id) {
                            HapticFeedback.selectionClick();
                            setState(() => _accountId = id);
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [
                            TextField(
                              controller: _note,
                              textInputAction: TextInputAction.done,
                              style: theme.bodyLarge,
                              decoration: InputDecoration(
                                hintText: _isTransfer
                                    ? l10n.entryTransferNoteHint
                                    : l10n.entryNoteHint,
                                isDense: true,
                                fillColor: t.surfaceRaised,
                                prefixIcon: Icon(Icons.notes_rounded,
                                    size: 18, color: t.textSecondary),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _DateChips(
                              date: _date,
                              onToday: _setToday,
                              onYesterday: _setYesterday,
                              onPick: _pickDate,
                              onPickTime: _pickTime,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Numpad(
                          decimalEnabled: decimals > 0,
                          decimalLabel: decimalSeparatorFor(
                              locale: context.localeTag),
                          onDigit: (d) => _onDigit(d, decimals),
                          onDecimal: _onDecimal,
                          onBackspace: _onBackspace,
                          onClear: () => setState(() => _raw = ''),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: AccentButton(
                            label: _editing
                                ? l10n.commonSaveChanges
                                : switch (_kind) {
                                    Kind.income => l10n.entryAddIncome,
                                    Kind.transfer => l10n.entryAddTransfer,
                                    _ => l10n.entryAddExpense,
                                  },
                            busy: _saving,
                            onPressed: canSave
                                ? () => _save(minor, fromId)
                                : null,
                          ),
                        ),
                      ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---- pieces -----------------------------------------------------------------

class _AmountDisplay extends StatelessWidget {
  const _AmountDisplay({
    required this.raw,
    required this.currency,
    required this.kind,
  });

  final String raw;
  final String currency;
  final String kind;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final locale = context.localeTag;
    final symbol = currencySymbolFor(currency, locale: locale);

    final parts = raw.split('.');
    final whole = parts[0].isEmpty ? 0 : int.parse(parts[0]);
    final grouped = formatWholeGrouped(whole, locale: locale);
    // `raw` is canonical (dot); show the locale's separator.
    final separator = decimalSeparatorFor(locale: locale);
    final display = raw.isEmpty
        ? '0'
        : raw.contains('.')
            ? '$grouped$separator${parts.length > 1 ? parts[1] : ''}'
            : grouped;
    final empty = raw.isEmpty;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                kind == Kind.income ? '+$symbol' : symbol,
                style: money(theme.headlineMedium!).copyWith(
                  color:
                      kind == Kind.income ? t.income : t.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            AnimatedSize(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              alignment: Alignment.centerLeft,
              child: Text(
                display,
                style: money(theme.displayLarge!).copyWith(
                  fontSize: 58,
                  color: empty
                      ? t.textSecondary.withValues(alpha: 0.5)
                      : t.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryGrid extends ConsumerWidget {
  const _CategoryGrid({
    required this.kind,
    required this.selectedId,
    required this.onSelect,
  });

  final String kind;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final categories = ref.watch(activeCategoriesProvider(kind)).value ??
        const <Category>[];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
                  begin: const Offset(0, 0.06), end: Offset.zero)
              .animate(animation),
          child: child,
        ),
      ),
      child: ConstrainedBox(
        key: ValueKey(kind),
        constraints: const BoxConstraints(maxHeight: 118),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in categories)
                _CategoryChip(
                  category: c,
                  selected: c.id == selectedId,
                  onTap: () => onSelect(c.id),
                  textTheme: theme,
                  tokens: t,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
    required this.textTheme,
    required this.tokens,
  });

  final Category category;
  final bool selected;
  final VoidCallback onTap;
  final TextTheme textTheme;
  final TallyTokens tokens;

  @override
  Widget build(BuildContext context) {
    final color = colorFromHex(category.color);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.20)
              : tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? color : tokens.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(category.emoji, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 6),
            Text(
              context.categoryName(id: category.id, name: category.name),
              style: textTheme.labelMedium!.copyWith(
                fontWeight: FontWeight.w600,
                color:
                    selected ? tokens.textPrimary : tokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateChips extends StatelessWidget {
  const _DateChips({
    required this.date,
    required this.onToday,
    required this.onYesterday,
    required this.onPick,
    required this.onPickTime,
  });

  final DateTime date;
  final VoidCallback onToday;
  final VoidCallback onYesterday;
  final VoidCallback onPick;
  final VoidCallback onPickTime;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final now = DateTime.now();
    final isToday = dayKey(date) == dayKey(now);
    final isYesterday =
        dayKey(date) == dayKey(now.subtract(const Duration(days: 1)));
    final custom = !isToday && !isYesterday;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _chip(context, l10n.commonToday, isToday, onToday),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _chip(
                  context, l10n.commonYesterday, isYesterday, onYesterday),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _chip(
                context,
                custom
                    ? dayMonthLabel(date, locale: context.localeTag)
                    : l10n.entryPickDate,
                custom,
                onPick,
                icon: Icons.calendar_today_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // The time sits on its own line rather than as a fourth chip: four
        // chips leave no room for "Yesterday" in any of the three languages.
        _chip(
          context,
          timeLabel(date, locale: context.localeTag),
          // Never rendered as "selected": a time is always set, so a filled
          // pill here would read as a state you cannot turn off.
          false,
          onPickTime,
          icon: Icons.schedule_rounded,
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, bool selected,
      VoidCallback onTap,
      {IconData? icon}) {
    final t = context.tokens;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        height: 38,
        decoration: BoxDecoration(
          color: selected
              ? t.accent.withValues(alpha: 0.16)
              : t.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? t.accent : t.border),
        ),
        // Padded and flexible: three chips share one row, so on a narrow phone
        // in Russian or Uzbek the label has to give way rather than overflow.
        // A date is one of the few labels that may ellipsize — money never is.
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 13,
                    color: selected ? t.textPrimary : t.textSecondary),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium!.copyWith(
                        color: selected ? t.textPrimary : t.textSecondary,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The two account pickers a transfer is made of, plus the hint that appears
/// while it is not yet a legal transfer.
///
/// Each side excludes the other's choice, so the "same account" case cannot be
/// selected at all rather than being selectable and then rejected.
class _TransferPickers extends StatelessWidget {
  const _TransferPickers({
    required this.accounts,
    required this.fromId,
    required this.toId,
    required this.onFrom,
    required this.onTo,
  });

  final List<Account> accounts;
  final String? fromId;
  final String? toId;
  final ValueChanged<String> onFrom;
  final ValueChanged<String> onTo;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final bool ready = fromId != null && toId != null && fromId != toId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AccountStrip(
          label: l10n.entryFromAccount,
          accounts: accounts,
          selectedId: fromId,
          onSelect: onFrom,
          excludeId: toId,
        ),
        const SizedBox(height: 10),
        AccountStrip(
          label: l10n.entryToAccount,
          accounts: accounts,
          selectedId: toId,
          onSelect: onTo,
          excludeId: fromId,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: ready
              ? const SizedBox(width: double.infinity, height: 0)
              : Padding(
                  padding: const EdgeInsets.only(left: 20, top: 8),
                  child: Text(
                    l10n.entryTransferPickTwo,
                    style: theme.bodySmall!.copyWith(color: t.textSecondary),
                  ),
                ),
        ),
      ],
    );
  }
}
