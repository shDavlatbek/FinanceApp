/// Add/edit account sheet: name, emoji, colour from the seed palette, type,
/// opening balance, archive.
///
/// The type (`cash` / `bank` / `savings` / `investment`) is a **label**, not a
/// behaviour: every account holds money identically, which is exactly what
/// makes "send to savings" an ordinary transfer rather than a second
/// money-movement path (docs/ARCHITECTURE.md § account).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../l10n/l10n.dart';
import '../common/buttons.dart';
import '../common/cards.dart';
import '../common/palette.dart';
import 'package:tally/data/providers.dart';

Future<void> showAccountEditSheet(
  BuildContext context, {
  Account? existing,
}) {
  return showTallySheet<void>(
    context,
    builder: (_) => AccountEditSheet(existing: existing),
  );
}

class AccountEditSheet extends ConsumerStatefulWidget {
  const AccountEditSheet({super.key, this.existing});

  final Account? existing;

  @override
  ConsumerState<AccountEditSheet> createState() => _AccountEditSheetState();
}

class _AccountEditSheetState extends ConsumerState<AccountEditSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _opening = TextEditingController();
  late String _emoji;
  late String _color;
  late String _kind;
  bool _saving = false;

  /// The name the field was prefilled with — the *localized* display name of
  /// an unrenamed seed account. Used to tell "left untouched" apart from a
  /// real rename, so editing Savings' colour in Russian does not freeze its
  /// name to "Накопления" in every other language.
  String? _prefilled;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final Account? existing = widget.existing;
    _emoji = existing?.emoji ?? '👛';
    _color = existing?.color ?? kSeedPalette.first;
    _kind = existing?.kind ?? AccountKind.cash;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Needs a Localizations scope, so it cannot live in initState().
    if (_prefilled != null) return;
    final Account? existing = widget.existing;
    _prefilled = existing == null
        ? ''
        : localizedAccountName(
            context.l10n,
            id: existing.id,
            name: existing.name,
          );
    _name.text = _prefilled!;
    if (existing != null && existing.openingBalanceMinor != 0) {
      final String currency =
          ref.read(currencyProvider).value ?? defaultCurrency;
      _opening.text =
          minorToEditable(existing.openingBalanceMinor, currency);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    var name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    final String currency = ref.read(currencyProvider).value ?? defaultCurrency;
    final int? opening = parseSignedAmountToMinor(
      _opening.text,
      currencyCode: currency,
    );
    if (opening == null) return;
    final Account? existing = widget.existing;
    // Left the prefilled name alone: keep whatever the database holds. For an
    // unrenamed seed account that is the canonical English name, so it keeps
    // localizing (docs/ARCHITECTURE.md § Seed account naming).
    if (existing != null && name == _prefilled) name = existing.name;
    setState(() => _saving = true);
    final repo = ref.read(accountsRepoProvider);
    if (existing == null) {
      await repo.insert(
        name: name,
        kind: _kind,
        emoji: _emoji,
        color: _color,
        openingBalanceMinor: opening,
      );
    } else {
      await repo.update(
        id: existing.id,
        name: name,
        kind: _kind,
        emoji: _emoji,
        color: _color,
        openingBalanceMinor: opening,
      );
    }
    HapticFeedback.mediumImpact();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _archive() async {
    final t = context.tokens;
    final l10n = context.l10n;
    final Account existing = widget.existing!;
    final String label = _prefilled ?? existing.name;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.accountArchiveConfirmTitle),
        content: Text(l10n.accountArchiveConfirmMessage(name: label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: t.danger),
            child: Text(l10n.accountArchive),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final repo = ref.read(accountsRepoProvider);
    final messenger = ScaffoldMessenger.of(context);
    final String undoLabel = l10n.commonUndo;
    final String snack = l10n.accountArchivedSnack(name: label);
    await repo.archive(existing.id);
    if (mounted) Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(snack),
        action: SnackBarAction(
          label: undoLabel,
          // Lifts the tombstone off the same row, so every transaction booked
          // to the account stays attached to it.
          onPressed: () => repo.unarchive(existing.id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final locale = context.localeTag;
    final String currency = ref.watch(currencyProvider).value ?? defaultCurrency;
    final Color accentColor = colorFromHex(_color);
    final bool openingValid = parseSignedAmountToMinor(
          _opening.text,
          currencyCode: currency,
        ) !=
        null;
    final bool canSave = _name.text.trim().isNotEmpty && openingValid;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_editing ? l10n.accountEdit : l10n.accountNew,
              style: theme.titleMedium),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: accentColor),
                ),
                child: Center(
                  child: Text(_emoji, style: const TextStyle(fontSize: 26)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  style: theme.bodyLarge,
                  decoration: InputDecoration(hintText: l10n.accountNameHint),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(l10n.accountKindLabel, style: theme.labelSmall),
          const SizedBox(height: 10),
          _KindGrid(
            value: _kind,
            accent: accentColor,
            onSelect: (kind) {
              HapticFeedback.selectionClick();
              setState(() => _kind = kind);
            },
          ),
          const SizedBox(height: 18),
          Text(l10n.accountOpeningBalanceLabel, style: theme.labelSmall),
          const SizedBox(height: 10),
          TextField(
            controller: _opening,
            // `numberWithOptions(signed:)` on purpose: a card in debt opens
            // negative, and this is the one money field in the app where a
            // minus is a real value rather than a typo.
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            style: money(theme.bodyLarge!),
            decoration: InputDecoration(
              hintText: minorToEditable(0, currency),
              prefixText: '${currencySymbolFor(currency, locale: locale)} ',
              prefixStyle: theme.bodyMedium!.copyWith(color: t.textSecondary),
              errorText:
                  openingValid ? null : l10n.accountOpeningBalanceInvalid,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Text(l10n.accountOpeningBalanceHelp, style: theme.bodySmall),
          const SizedBox(height: 18),
          Text(l10n.accountEmojiLabel, style: theme.labelSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final String e in <String>{
                _emoji,
                ...kAccountEmojiSuggestions,
              })
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _emoji = e);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: e == _emoji
                          ? accentColor.withValues(alpha: 0.20)
                          : t.surfaceRaised,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: e == _emoji ? accentColor : t.border),
                    ),
                    child: Center(
                      child: Text(e, style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(l10n.accountColorLabel, style: theme.labelSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final String hex in kSeedPalette)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _color = hex);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: colorFromHex(hex),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: hex == _color ? t.textPrimary : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: hex == _color
                        ? const Icon(Icons.check_rounded,
                            size: 16, color: Colors.black54)
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          AccentButton(
            label: _editing ? l10n.commonSaveChanges : l10n.accountCreate,
            busy: _saving,
            onPressed: canSave ? _save : null,
          ),
          if (_editing) ...[
            const SizedBox(height: 10),
            GhostButton(
              label: l10n.accountArchive,
              icon: Icons.archive_outlined,
              destructive: true,
              onPressed: _archive,
            ),
          ],
        ],
      ),
    );
  }
}

/// The four account types as equal-width pills, two per row — Russian and
/// Uzbek labels do not survive a quarter of the screen width.
class _KindGrid extends StatelessWidget {
  const _KindGrid({
    required this.value,
    required this.accent,
    required this.onSelect,
  });

  static const double _gap = 8;

  final String value;
  final Color accent;
  final ValueChanged<String> onSelect;

  static const Map<String, IconData> _icons = <String, IconData>{
    AccountKind.cash: Icons.payments_outlined,
    AccountKind.bank: Icons.credit_card_rounded,
    AccountKind.savings: Icons.savings_outlined,
    AccountKind.investment: Icons.trending_up_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = (constraints.maxWidth - _gap) / 2;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final String kind in AccountKind.all)
              SizedBox(
                width: width,
                child: GestureDetector(
                  onTap: () => onSelect(kind),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: kind == value
                          ? accent.withValues(alpha: 0.16)
                          : t.surfaceRaised,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                          color: kind == value ? accent : t.border),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _icons[kind]!,
                          size: 16,
                          color: kind == value
                              ? t.textPrimary
                              : t.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            accountKindName(l10n, kind),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.labelMedium!.copyWith(
                              color: kind == value
                                  ? t.textPrimary
                                  : t.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
