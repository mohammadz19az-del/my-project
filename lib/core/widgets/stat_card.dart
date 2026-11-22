import 'package:flutter/material.dart';

import '../utilities/formatters.dart';
import 'glow_card.dart';
import 'motion_scope.dart';

/// A single headline number with icon and label. The value counts up when
/// animations are enabled.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700);
    final animate = MotionScope.enabledOf(context);

    final Widget number = animate
        ? TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: value.toDouble()),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Text(formatNumber(context, v.round()), style: valueStyle),
          )
        : Text(formatNumber(context, value), style: valueStyle);

    return Semantics(
      container: true,
      label: '$label: ${formatNumber(context, value)}',
      excludeSemantics: true,
      child: GlowCard(
        accent: accent,
        onTap: onTap,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accent.withAlpha(36),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  number,
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
