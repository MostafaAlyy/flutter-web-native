import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// A [ScrollController] that smoothly animates discrete pointer scroll deltas
/// (such as mouse wheel ticks) using cubic momentum curves, matching the fluid
/// feel of native desktop browsers (Chrome, Safari, Firefox, Edge).
class SmoothScrollController extends ScrollController {
  SmoothScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
    this.duration = const Duration(milliseconds: 180),
    this.curve = Curves.easeOutCubic,
  });

  /// The duration of the smooth scroll easing animation.
  final Duration duration;

  /// The animation curve (defaults to easeOutCubic).
  final Curve curve;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return SmoothScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
      duration: duration,
      curve: curve,
    );
  }
}

/// A [ScrollPosition] subclass that intercepts [pointerScroll] and smoothly
/// interpolates to the target offset instead of jumping abruptly.
class SmoothScrollPosition extends ScrollPositionWithSingleContext {
  SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels = 0.0,
    super.keepScrollOffset = true,
    super.oldPosition,
    super.debugLabel,
    required this.duration,
    required this.curve,
  });

  final Duration duration;
  final Curve curve;
  double? _targetPixels;

  @override
  void pointerScroll(double delta) {
    if (delta == 0.0) {
      goBallistic(0.0);
      return;
    }

    // Respect reduced motion accessibility setting
    final mediaQuery = context.notificationContext != null
        ? MediaQuery.maybeOf(context.notificationContext!)
        : null;
    if (mediaQuery?.disableAnimations ?? false) {
      super.pointerScroll(delta);
      return;
    }

    final currentTarget = _targetPixels ?? pixels;
    final newTarget = math.min(
      math.max(currentTarget + delta, minScrollExtent),
      maxScrollExtent,
    );

    if (newTarget == pixels) {
      return;
    }

    _targetPixels = newTarget;

    animateTo(
      newTarget,
      duration: duration,
      curve: curve,
    ).whenComplete(() {
      if (_targetPixels == newTarget) {
        _targetPixels = null;
      }
    });
  }

  @override
  void jumpTo(double value) {
    _targetPixels = null;
    super.jumpTo(value);
  }

  @override
  void goIdle() {
    _targetPixels = null;
    super.goIdle();
  }
}
