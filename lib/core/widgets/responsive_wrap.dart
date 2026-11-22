import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Number of equal-width columns that fit [width] given a minimum item width.
int responsiveColumns(double width, {required double minItemWidth, required double spacing}) =>
    math.max(1, ((width + spacing) / (minItemWidth + spacing)).floor());

/// Lays children out in equal-width columns that adapt to the available width
/// (1 column on phones, more on tablets/desktop).
class ResponsiveWrap extends StatelessWidget {
  const ResponsiveWrap({
    super.key,
    required this.children,
    this.minItemWidth = 220,
    this.spacing = 16,
    this.maxColumns = 6,
  });

  final List<Widget> children;
  final double minItemWidth;
  final double spacing;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final columns = math.min(
        responsiveColumns(constraints.maxWidth, minItemWidth: minItemWidth, spacing: spacing),
        maxColumns,
      );
      final itemWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final c in children) SizedBox(width: itemWidth, child: c)],
      );
    });
  }
}
