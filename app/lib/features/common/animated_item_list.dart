/// Implicitly-animated list: diffs consecutive item lists by key and drives an
/// [AnimatedList] so inserts grow/fade in and removals collapse out
/// (DESIGN.md: "implicit animations on insert/remove").
library;

import 'package:flutter/material.dart';

class AnimatedItemList<T> extends StatefulWidget {
  const AnimatedItemList({
    super.key,
    required this.items,
    required this.keyOf,
    required this.itemBuilder,
    this.shrinkWrap = false,
    this.physics,
    this.padding = EdgeInsets.zero,
    this.skipRemoveAnimation,
  });

  final List<T> items;
  final Object Function(T item) keyOf;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry padding;

  /// Keys whose removal should be instant (already animated by a Dismissible).
  final Set<Object>? skipRemoveAnimation;

  @override
  State<AnimatedItemList<T>> createState() => _AnimatedItemListState<T>();
}

class _AnimatedItemListState<T> extends State<AnimatedItemList<T>> {
  final _listKey = GlobalKey<AnimatedListState>();
  late List<T> _items = List.of(widget.items);

  static const _insertDuration = Duration(milliseconds: 320);
  static const _removeDuration = Duration(milliseconds: 260);

  @override
  void didUpdateWidget(covariant AnimatedItemList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _diff(widget.items);
  }

  void _diff(List<T> next) {
    final nextKeys = next.map(widget.keyOf).toSet();

    // Removals (walk backwards so indices stay valid).
    for (var i = _items.length - 1; i >= 0; i--) {
      final key = widget.keyOf(_items[i]);
      if (!nextKeys.contains(key)) {
        final removed = _items.removeAt(i);
        final skip = widget.skipRemoveAnimation?.remove(key) ?? false;
        _listKey.currentState?.removeItem(
          i,
          (context, animation) => skip
              ? const SizedBox.shrink()
              : _transition(animation, widget.itemBuilder(context, removed)),
          duration: skip ? Duration.zero : _removeDuration,
        );
      }
    }

    // Insertions.
    final currentKeys = _items.map(widget.keyOf).toList();
    for (var j = 0; j < next.length; j++) {
      final key = widget.keyOf(next[j]);
      if (!currentKeys.contains(key)) {
        final index = j.clamp(0, _items.length);
        _items.insert(index, next[j]);
        currentKeys.insert(index, key);
        _listKey.currentState?.insertItem(index, duration: _insertDuration);
      }
    }

    // Contents/order refresh (counts already match).
    setState(() => _items = List.of(next));
  }

  Widget _transition(Animation<double> animation, Widget child) {
    final curved =
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return SizeTransition(
      sizeFactor: curved,
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.12),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedList(
      key: _listKey,
      initialItemCount: _items.length,
      shrinkWrap: widget.shrinkWrap,
      physics: widget.physics,
      padding: widget.padding,
      itemBuilder: (context, index, animation) =>
          _transition(animation, widget.itemBuilder(context, _items[index])),
    );
  }
}
