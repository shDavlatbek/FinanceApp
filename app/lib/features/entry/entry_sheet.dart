/// Full-height transaction entry sheet — springy slide-up, live-formatted
/// oversized amount, custom numpad, kind pill, emoji category grid, note and
/// date chips. Also used to edit an existing transaction.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../l10n/l10n.dart';
import '../common/buttons.dart';
import '../common/kind_pill.dart';
import 'numpad.dart';
import 'package:tally/data/providers.dart';

/// Opens the sheet as a custom route: springy slide-up (easeOutBack, 420 ms),
/// clean ease-in on the way down.
Future<void> showEntrySheet(BuildContext context, {Transaction? existing}) {
  final surface = context.tokens.surface;
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => EntrySheet(existing: existing),
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
  const EntrySheet({super.key, this.existing});

  final Transaction? existing;

  @override
  ConsumerState<EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends ConsumerState<EntrySheet> {
  late String _kind;
  late String _raw;
  String? _categoryId;
  late DateTime _date;
  late final TextEditingController _note;
  bool _saving = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final tx = widget.existing;
    final currency = ref.read(currencyProvider).value ?? defaultCurrency;
    _kind = tx?.kind ?? Kind.expense;
    _raw = tx == null ? '' : _minorToRaw(tx.amountMinor, currency);
    _categoryId = tx?.categoryId;
    _date = tx == null ? DateTime.now() : occurredAtToLocal(tx.occurredAt);
    _note = TextEditingController(text: tx?.note ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _minorToRaw(int minor, String code) {
    final d = decimalDigitsFor(code);
    if (d == 0) return '$minor';
    final per = minorUnitsPerMajor(code);
    final whole = minor ~/ per;
    final frac = minor % per;
    return frac == 0 ? '$whole' : '$whole.${frac.toString().padLeft(d, '0')}';
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
      _categoryId = null;
    });
  }

  void _setToday() {
    setState(() => _date = DateTime.now());
  }

  void _setYesterday() {
    final y = DateTime.now().subtract(const Duration(days: 1));
    setState(() => _date = DateTime(y.year, y.month, y.day, 12));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() =>
          _date = DateTime(picked.year, picked.month, picked.day, 12));
    }
  }

  Future<void> _save(int minor) async {
    if (_saving || _categoryId == null) return;
    setState(() => _saving = true);
    final repo = ref.read(transactionsRepoProvider);
    final note = _note.text.trim();
    if (_editing) {
      await repo.update(
        id: widget.existing!.id,
        kind: _kind,
        amountMinor: minor,
        categoryId: _categoryId,
        note: note,
        occurredAt: _date,
      );
    } else {
      await repo.insert(
        kind: _kind,
        amountMinor: minor,
        categoryId: _categoryId!,
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

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final currency = ref.watch(currencyProvider).value ?? defaultCurrency;
    final decimals = decimalDigitsFor(currency);
    final minor = parseAmountToMinor(_raw, currencyCode: currency);
    final canSave = minor != null && _categoryId != null && !_saving;
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
                        child:
                            KindPill(value: _kind, onChanged: _setKind),
                      ),
                      const SizedBox(height: 14),
                      _CategoryGrid(
                        kind: _kind,
                        selectedId: _categoryId,
                        onSelect: (id) {
                          HapticFeedback.selectionClick();
                          setState(() => _categoryId = id);
                        },
                      ),
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
                                hintText: l10n.entryNoteHint,
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
                                : _kind == Kind.income
                                    ? l10n.entryAddIncome
                                    : l10n.entryAddExpense,
                            busy: _saving,
                            onPressed:
                                canSave ? () => _save(minor) : null,
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
  });

  final DateTime date;
  final VoidCallback onToday;
  final VoidCallback onYesterday;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final now = DateTime.now();
    final isToday = dayKey(date) == dayKey(now);
    final isYesterday =
        dayKey(date) == dayKey(now.subtract(const Duration(days: 1)));
    final custom = !isToday && !isYesterday;

    return Row(
      children: [
        Expanded(
          child: _chip(context, l10n.commonToday, isToday, onToday),
        ),
        const SizedBox(width: 8),
        Expanded(
          child:
              _chip(context, l10n.commonYesterday, isYesterday, onYesterday),
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
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium!.copyWith(
                      color:
                          selected ? t.textPrimary : t.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
