import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'glass.dart';

/// Modal sheet floating above the bottom edge, on glass.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required double radius,
  bool useRootNavigator = false,
  bool isScrollControlled = false,
  BoxConstraints? constraints,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    clipBehavior: Clip.none,
    useRootNavigator: useRootNavigator,
    isScrollControlled: isScrollControlled,
    constraints: constraints,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _GlassSheet(radius: radius, child: builder(context)),
    ),
  );
}

/// A sheet floating above the bottom edge: a drag handle over [child], on
/// glass or, without it, a solid surface.
class _GlassSheet extends StatelessWidget {
  const _GlassSheet({required this.radius, required this.child});

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      10,
      0,
      10,
      math.max(10, MediaQuery.viewPaddingOf(context).bottom),
    ),
    child: GlassPanel(
      radius: radius,
      child: Material(
        color: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                child: Center(
                  child: Container(
                    width: 38,
                    height: 5,
                    decoration: BoxDecoration(
                      color: kOnGlass.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),
              ),
              if (constraints.hasBoundedHeight)
                Flexible(child: child)
              else
                child,
            ],
          ),
        ),
      ),
    ),
  );
}
