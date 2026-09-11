import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Selection controls for [SelectionArea] that match native web/desktop
/// expectations.
///
/// Flutter's default [SelectionArea] controls render mobile teardrop pin
/// handles, which look out of place under a mouse cursor. On web and desktop
/// this returns [desktopTextSelectionHandleControls] (thin desktop bars); on
/// touch platforms it returns `null` so Flutter keeps the platform-correct
/// touch handles.
///
/// ```dart
/// SelectionArea(
///   selectionControls: appTextSelectionHandleControls,
///   child: content,
/// )
/// ```
///
/// Pair this with:
/// - `textSelectionTheme` in `ThemeData` for brand-colored highlights/handles.
/// - Excluding `PointerDeviceKind.mouse` from `ScrollBehavior.dragDevices`, so
///   dragging selects text instead of panning.
/// - `SelectionContainer.disabled` around nav rails, toolbars, and buttons.
TextSelectionControls? get appTextSelectionHandleControls {
  final isDesktop = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);
  if (!kIsWeb && !isDesktop) return null;
  return desktopTextSelectionHandleControls;
}
