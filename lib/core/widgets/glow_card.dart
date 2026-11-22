import 'package:flutter/material.dart';

import 'motion_scope.dart';

/// Surface card with a subtle accent glow that intensifies on hover (desktop)
/// and an optional tap action.
class GlowCard extends StatefulWidget {
  const GlowCard({
    super.key,
    required this.child,
    this.onTap,
    this.accent,
    this.padding = const EdgeInsetsDirectional.all(16),
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? accent;
  final EdgeInsetsGeometry padding;

  @override
  State<GlowCard> createState() => _GlowCardState();
}

class _GlowCardState extends State<GlowCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.accent ?? theme.colorScheme.primary;
    final radius = BorderRadius.circular(16);
    final interactive = widget.onTap != null;
    final lit = _hover && interactive;

    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: MotionScope.duration(context, 160),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: radius,
          border: Border.all(color: accent.withAlpha(lit ? 180 : 70)),
          boxShadow: [
            BoxShadow(color: accent.withAlpha(lit ? 70 : 24), blurRadius: lit ? 22 : 12),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: widget.onTap,
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}
