/// Categories — list by kind, add/edit (name, emoji, seed-palette color),
/// archive, drag-to-reorder.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../l10n/l10n.dart';
import '../common/buttons.dart';
import '../common/empty_state.dart';
import '../common/kind_pill.dart';
import 'category_edit_sheet.dart';
import 'package:tally/data/providers.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  String _kind = Kind.expense;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final categories =
        ref.watch(activeCategoriesProvider(_kind)).value ?? const <Category>[];

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.arrow_back_rounded,
                        color: t.textPrimary),
                  ),
                  const SizedBox(width: 4),
                  Text(l10n.categoriesTitle, style: theme.titleLarge),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: KindPill(
                value: _kind,
                onChanged: (k) => setState(() => _kind = k),
              ),
            ),
            Expanded(
              child: categories.isEmpty
                  ? EmptyState(
                      emoji: '🗂️',
                      title: l10n.categoriesEmptyTitle,
                      message: l10n.categoriesEmptyMessage,
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                      buildDefaultDragHandles: false,
                      itemCount: categories.length,
                      proxyDecorator: (child, index, animation) =>
                          AnimatedBuilder(
                        animation: animation,
                        builder: (context, _) => Transform.scale(
                          scale: 1.02,
                          child: Material(
                            color: Colors.transparent,
                            child: child,
                          ),
                        ),
                      ),
                      onReorderItem: (oldIndex, newIndex) {
                        final ids =
                            categories.map((c) => c.id).toList();
                        final id = ids.removeAt(oldIndex);
                        ids.insert(newIndex, id);
                        HapticFeedback.mediumImpact();
                        ref
                            .read(categoriesRepoProvider)
                            .reorder(kind: _kind, orderedIds: ids);
                      },
                      itemBuilder: (context, index) {
                        final c = categories[index];
                        return _CategoryRow(
                          key: ValueKey(c.id),
                          category: c,
                          index: index,
                          onTap: () => showCategoryEditSheet(context,
                              existing: c),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: AccentButton(
            label: l10n.categoryNew,
            icon: Icons.add_rounded,
            onPressed: () =>
                showCategoryEditSheet(context, kind: _kind),
          ),
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    super.key,
    required this.category,
    required this.index,
    required this.onTap,
  });

  final Category category;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context).textTheme;
    final color = colorFromHex(category.color);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Center(
                    child: Text(category.emoji,
                        style: const TextStyle(fontSize: 19)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.categoryName(
                      id: category.id,
                      name: category.name,
                    ),
                    style: theme.bodyLarge!
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(Icons.edit_outlined,
                    size: 17, color: t.textSecondary),
                const SizedBox(width: 14),
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(Icons.drag_handle_rounded,
                      size: 20, color: t.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
