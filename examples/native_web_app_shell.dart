import 'package:flutter/material.dart';

/// A production-grade web application shell pattern that delivers:
/// 1. Desktop selection handles (no mobile teardrop pins).
/// 2. Protected chrome (navigation, headers, and action buttons are not selected).
/// 3. Crisp selectable content.
class NativeWebAppShell extends StatelessWidget {
  const NativeWebAppShell({
    super.key,
    required this.navigation,
    required this.header,
    required this.content,
  });

  final Widget navigation;
  final Widget header;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Navigation rail / sidebar: shield from accidental selection during drag
          SelectionContainer.disabled(
            child: navigation,
          ),
          // Main content column
          Expanded(
            child: Column(
              children: [
                // Top app bar / header chrome: shield from selection
                SelectionContainer.disabled(
                  child: header,
                ),
                // Main scrollable content body: fully selectable with desktop handle controls
                Expanded(
                  child: SelectionArea(
                    selectionControls: desktopTextSelectionHandleControls,
                    child: content,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
