import 'package:flutter/widgets.dart';

/// Tells descendants whether decorative animation is allowed (user setting AND
/// OS reduced-motion). Widgets use [duration] so a disabled state yields zero.
class MotionScope extends InheritedWidget {
  const MotionScope({super.key, required this.enabled, required super.child});

  final bool enabled;

  static bool enabledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MotionScope>()?.enabled ??
      !MediaQuery.disableAnimationsOf(context);

  static Duration duration(BuildContext context, [int milliseconds = 200]) =>
      enabledOf(context) ? Duration(milliseconds: milliseconds) : Duration.zero;

  @override
  bool updateShouldNotify(MotionScope oldWidget) => enabled != oldWidget.enabled;
}
