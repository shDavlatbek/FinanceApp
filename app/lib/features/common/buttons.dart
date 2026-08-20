/// Buttons: press-scale wrapper + the two Tally button styles.
library;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Scales its child down slightly while pressed (110 ms, ease-out) — the
/// baseline tactile feel for every custom tappable surface.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.96,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null
          ? null
          : (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Primary action: full accent pill.
class AccentButton extends StatelessWidget {
  const AccentButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.height = 54,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = onPressed != null && !busy;
    return Pressable(
      onTap: enabled ? onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        height: height,
        decoration: BoxDecoration(
          color: enabled ? t.accent : t.surfaceRaised,
          borderRadius: BorderRadius.circular(18),
          border: enabled ? null : Border.all(color: t.border),
        ),
        child: Center(
          child: busy
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: t.textSecondary,
                  ),
                )
              : Padding(
                  // Translations run longer than English; keep the label off
                  // the pill's edge and let it ellipsize instead of
                  // overflowing.
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon,
                            size: 20,
                            color: enabled ? t.onAccent : t.textSecondary),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.labelLarge!.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color:
                                        enabled ? t.onAccent : t.textSecondary,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// Secondary action: hairline-outlined quiet pill.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.height = 48,
    this.busy = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final bool busy;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = destructive ? t.danger : t.textPrimary;
    return Pressable(
      onTap: busy ? null : onPressed,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.border),
        ),
        child: Center(
          child: busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2, color: t.textSecondary),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 18, color: fg),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelLarge!
                              .copyWith(
                                  fontWeight: FontWeight.w600, color: fg),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
