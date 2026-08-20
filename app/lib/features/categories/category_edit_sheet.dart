/// Add/edit category sheet: name, emoji, color from the seed palette, archive.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../l10n/l10n.dart';
import '../common/buttons.dart';
import '../common/cards.dart';
import 'package:tally/data/providers.dart';

/// The 11 distinct colors used by the ARCHITECTURE.md seed categories.
const List<String> kSeedPalette = [
  '#4CAF7D',
  '#E8935A',
  '#5A9BE8',
  '#9B7DE8',
  '#E8C95A',
  '#E85A7A',
  '#D45AE8',
  '#5AE8D4',
  '#7A8BE8',
  '#5AC8E8',
  '#8E8E93',
];

const List<String> _emojiSuggestions = [
  '🛒', '☕', '🚕', '🏠', '💡', '💊', '🛍️', '🎮', '📱', '✈️', '📦',
  '💼', '💻', '🎁', '➕', '🍔', '🍕', '🍺', '🎬', '🎵', '📚', '🐾',
  '👶', '💪', '🚗', '⛽', '🎨', '⚽', '🧾', '💳', '🎓', '🌐',
];

Future<void> showCategoryEditSheet(
  BuildContext context, {
  Category? existing,
  String kind = 'expense',
}) {
  return showTallySheet<void>(
    context,
    builder: (_) => CategoryEditSheet(existing: existing, kind: kind),
  );
}

class CategoryEditSheet extends ConsumerStatefulWidget {
  const CategoryEditSheet({super.key, this.existing, required this.kind});

  final Category? existing;
  final String kind;

  @override
  ConsumerState<CategoryEditSheet> createState() => _CategoryEditSheetState();
}

class _CategoryEditSheetState extends ConsumerState<CategoryEditSheet> {
  final TextEditingController _name = TextEditingController();
  late String _emoji;
  late String _color;
  bool _saving = false;

  /// The name the field was prefilled with — the *localized* display name for
  /// an unrenamed seed category. Used to tell "left untouched" apart from a
  /// real rename.
  String? _prefilled;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _emoji = widget.existing?.emoji ?? '📦';
    _color = widget.existing?.color ?? kSeedPalette.first;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Needs a Localizations scope, so it cannot live in initState().
    if (_prefilled != null) return;
    final Category? existing = widget.existing;
    _prefilled = existing == null
        ? ''
        : localizedCategoryName(
            context.l10n,
            id: existing.id,
            name: existing.name,
          );
    _name.text = _prefilled!;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    var name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    final Category? existing = widget.existing;
    // The user left the prefilled name alone: keep whatever is in the
    // database. For an unrenamed seed that is the canonical English name, so
    // the category keeps localizing in every language instead of freezing
    // into the language it happened to be edited in
    // (docs/ARCHITECTURE.md § Seed category naming).
    if (existing != null && name == _prefilled) name = existing.name;
    setState(() => _saving = true);
    await ref.read(categoriesRepoProvider).upsert(
          id: existing?.id,
          name: name,
          emoji: _emoji,
          color: _color,
          kind: existing?.kind ?? widget.kind,
        );
    HapticFeedback.mediumImpact();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _archive() async {
    final t = context.tokens;
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.categoryArchiveConfirmTitle),
        content: Text(l10n.categoryArchiveConfirmMessage(
          name: _prefilled ?? widget.existing!.name,
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: t.danger),
            child: Text(l10n.categoryArchive),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(categoriesRepoProvider).archive(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final accentColor = colorFromHex(_color);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_editing ? l10n.categoryEdit : l10n.categoryNew,
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
                  child:
                      Text(_emoji, style: const TextStyle(fontSize: 26)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  style: theme.bodyLarge,
                  decoration:
                      InputDecoration(hintText: l10n.categoryNameHint),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(l10n.categoryEmojiLabel, style: theme.labelSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in {
                _emoji,
                ..._emojiSuggestions,
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
                        child: Text(e,
                            style: const TextStyle(fontSize: 18))),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(l10n.categoryColorLabel, style: theme.labelSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final hex in kSeedPalette)
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
                        color: hex == _color
                            ? t.textPrimary
                            : Colors.transparent,
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
            label: _editing ? l10n.commonSaveChanges : l10n.categoryCreate,
            busy: _saving,
            onPressed: _name.text.trim().isEmpty ? null : _save,
          ),
          if (_editing) ...[
            const SizedBox(height: 10),
            GhostButton(
              label: l10n.categoryArchive,
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
