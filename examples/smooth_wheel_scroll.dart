import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A production-grade smooth wheel/trackpad scroller for Flutter web.
///
/// Why not subclass [ScrollPosition] and smooth `pointerScroll`? Because
/// `pointerScroll` is only re-entered 40–120×/second on a trackpad, and every
/// `animateTo` restarts the animation — dozens of competing animations fight
/// over one position. Instead, this class **coalesces** deltas into a single
/// target and eases one ticker toward it.
///
/// The ease is **time-based**, not tick-based: [smoothing] is the fraction of
/// the remaining distance consumed in one 60 Hz frame, and each tick scales it
/// by the real elapsed time. A naive per-tick `remaining *= smoothing`
/// converges in a fixed number of *ticks*, so a throttled low-end device firing
/// 10 ticks/sec would keep gliding for seconds after the user stopped.
///
/// See also [SmoothWheelScroll], the widget that wires this up.
class SmoothWheelScroller {
  SmoothWheelScroller({
    required ScrollController controller,
    required TickerProvider vsync,
    this.gain = 1.45,
    this.smoothing = 0.22,
  }) : _controller = controller {
    _ticker = vsync.createTicker(_tick);
  }

  final ScrollController _controller;

  /// Multiplier applied to incoming deltas. >1 compensates for the eased
  /// target lagging the finger; tune per app (1.2–1.6 is typical).
  final double gain;

  /// Fraction of the remaining distance consumed per 60 Hz frame.
  final double smoothing;

  late final Ticker _ticker;
  double? _target;
  Duration? _lastTick;

  bool get isActive => _ticker.isActive;

  /// Accumulate a wheel/trackpad delta; starts the ticker if idle.
  void addDelta(double dy) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final base = _target ?? position.pixels;
    _setTarget(base + dy * gain, position);
  }

  /// Programmatic target (e.g. nav links); animates the same way as wheel input.
  void retarget(double offset) {
    if (!_controller.hasClients) return;
    _setTarget(offset, _controller.position);
  }

  void _setTarget(double raw, ScrollPosition position) {
    _target = raw
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (!_ticker.isActive) _ticker.start();
  }

  void _tick(Duration elapsed) {
    final target = _target;
    if (target == null || !_controller.hasClients) {
      _stop();
      return;
    }
    final lastTick = _lastTick;
    // First tick after (re)start has no prior sample; assume one 60 Hz frame
    // rather than the ticker's elapsed-from-zero (which reads as a huge dt).
    final dt = lastTick == null
        ? 1 / 60
        : ((elapsed - lastTick).inMicroseconds / 1e6).clamp(1 / 240, 0.1);
    _lastTick = elapsed;

    final pixels = _controller.position.pixels;
    final remaining = target - pixels;
    if (remaining.abs() < 0.5) {
      _controller.jumpTo(target);
      _stop();
      return;
    }
    final factor = 1 - math.pow(1 - smoothing, dt * 60);
    _controller.jumpTo(pixels + remaining * factor);
  }

  /// Abandon the pending target — called when a real drag starts, so the ease
  /// does not fight the finger.
  void cancel() => _stop();

  void _stop() {
    _target = null;
    _lastTick = null;
    if (_ticker.isActive) _ticker.stop();
  }

  void dispose() {
    _stop();
    _ticker.dispose();
  }
}

/// Wraps a scroll view and smooths mouse-wheel/trackpad scroll on web.
///
/// ```dart
/// final _controller = ScrollController();
/// ...
/// SmoothWheelScroll(
///   controller: _controller,
///   child: ListView(controller: _controller, children: [...]),
/// )
/// ```
///
/// Behavior notes:
/// - Registers with [GestureBinding.pointerSignalResolver] so it wins over the
///   inner [Scrollable]'s default (instant) wheel handling.
/// - Respects reduced motion: when `MediaQuery.disableAnimations` is true
///   (mirrors `prefers-reduced-motion` on web) it lets the platform run.
/// - Touch gestures are never intercepted; this only affects wheel/pan-zoom
///   pointer signals.
class SmoothWheelScroll extends StatefulWidget {
  const SmoothWheelScroll({
    super.key,
    required this.controller,
    required this.child,
    this.gain = 1.45,
    this.smoothing = 0.22,
  });

  final ScrollController controller;
  final Widget child;
  final double gain;
  final double smoothing;

  @override
  State<SmoothWheelScroll> createState() => _SmoothWheelScrollState();
}

class _SmoothWheelScrollState extends State<SmoothWheelScroll>
    with SingleTickerProviderStateMixin {
  SmoothWheelScroller? _wheel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _wheel = SmoothWheelScroller(
        controller: widget.controller,
        vsync: this,
        gain: widget.gain,
        smoothing: widget.smoothing,
      );
    });
  }

  @override
  void dispose() {
    _wheel?.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final wheel = _wheel;
    if (wheel == null ||
        !widget.controller.hasClients ||
        event.scrollDelta.dy == 0) {
      return;
    }
    // Respect reduced motion: fall back to the platform's instant wheel.
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return;

    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      if (event is PointerScrollEvent) wheel.addDelta(event.scrollDelta.dy);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      // A user drag owns the position; stop any running ease.
      onPointerDown: (_) => _wheel?.cancel(),
      child: widget.child,
    );
  }
}
