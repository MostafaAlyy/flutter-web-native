import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A production-grade [ScrollBehavior] configured for native web fidelity.
///
/// Key characteristics:
/// 1. **Preserves text selection**: Excludes [PointerDeviceKind.mouse] from
///    [dragDevices] so dragging a mouse highlights text instead of panning the page.
/// 2. **Desktop physics**: Uses [ClampingScrollPhysics] across all platforms to
///    eliminate inappropriate mobile rubber-band bouncing on desktop viewports.
/// 3. **Controlled scrollbars**: Builds scrollbars cleanly without triggering
///    unattached controller assertion crashes.
class NativeWebScrollBehavior extends MaterialScrollBehavior {
  const NativeWebScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
    // Note: PointerDeviceKind.mouse is intentionally EXCLUDED on desktop web!
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (details.controller == null) {
      return child;
    }
    return Scrollbar(
      controller: details.controller,
      child: child,
    );
  }
}
