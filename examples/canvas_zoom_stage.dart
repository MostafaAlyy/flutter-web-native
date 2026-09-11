import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// An interactive canvas stage that natively supports:
/// 1. Trackpad two-finger pinch-to-zoom & pan.
/// 2. Mouse [Ctrl + Wheel] or [Cmd + Wheel] zooming with focal point tracking.
/// 3. Smooth exponential zoom curves.
class CanvasZoomStage extends StatefulWidget {
  const CanvasZoomStage({
    super.key,
    required this.child,
    this.minScale = 0.2,
    this.maxScale = 8.0,
    this.initialScale = 1.0,
  });

  final Widget child;
  final double minScale;
  final double maxScale;
  final double initialScale;

  @override
  State<CanvasZoomStage> createState() => _CanvasZoomStageState();
}

class _CanvasZoomStageState extends State<CanvasZoomStage> {
  late double _scale;
  Offset _pan = Offset.zero;

  @override
  void initState() {
    super.initState();
    _scale = widget.initialScale;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final isZoomModifier = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;

      if (isZoomModifier) {
        // Continuous exponential zoom
        const sensitivity = 0.0025;
        final zoomFactor = math.exp(-event.scrollDelta.dy * sensitivity);
        final targetScale = (_scale * zoomFactor).clamp(widget.minScale, widget.maxScale);

        if (targetScale == _scale) return;

        // Zoom relative to pointer focal position
        final focalPoint = event.localPosition;
        final focalOffset = focalPoint - _pan;
        final targetPan = focalPoint - focalOffset * (targetScale / _scale);

        setState(() {
          _scale = targetScale;
          _pan = targetPan;
        });
      }
    }
  }

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final targetScale = (_scale * event.scale).clamp(widget.minScale, widget.maxScale);
    final focalPoint = event.localPosition;
    final focalOffset = focalPoint - _pan;
    final targetPan = focalPoint - focalOffset * (targetScale / _scale) + event.panDelta;

    setState(() {
      _scale = targetScale;
      _pan = targetPan;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
      child: ClipRect(
        child: Transform(
          transform: Matrix4.identity()
            ..translate(_pan.dx, _pan.dy)
            ..scale(_scale),
          child: widget.child,
        ),
      ),
    );
  }
}
