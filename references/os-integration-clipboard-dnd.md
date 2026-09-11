# OS Integration: Clipboard & Drag-and-Drop

Native web apps feel connected to the user's Operating System. They allow seamless moving of files, rich text, and images between the OS desktop and the browser window. Flutter web needs specific packages and patterns to achieve this.

## 1. Drag and Drop (File System to Web)

By default, dropping a file onto a Flutter Web `<canvas>` does nothing, or the browser navigates away to view the file. To make Flutter feel native, you must intercept the HTML5 drag events and pipe them into Flutter.

**Best Practice Package**: `desktop_drop`

### Implementation Detail
Wrap your target areas (or the whole app shell) in a `DropTarget`.

```dart
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';

DropTarget(
  onDragEntered: (details) => setState(() => _isHovering = true),
  onDragExited: (details) => setState(() => _isHovering = false),
  onDragDone: (details) async {
    final List<XFile> files = details.files;
    for (final file in files) {
      final bytes = await file.readAsBytes();
      // Upload or process bytes
    }
  },
  child: Container(
    color: _isHovering ? Colors.blue.withOpacity(0.2) : Colors.transparent,
    child: Text('Drop files here'),
  ),
)
```

**Under the hood on Web**: This package registers HTML DOM event listeners for `dragenter`, `dragover`, `dragleave`, and `drop`, calling `preventDefault()` to stop the browser from opening the file, and then reads the `DataTransfer` object into memory.

## 2. Advanced Clipboard (Images and Rich Text)

Flutter's standard `Clipboard.setData()` only supports plain text. Native web apps (like Notion, Figma, Slack) allow copying and pasting images and HTML directly.

**Best Practice Package**: `super_clipboard`

### Reading Images from Clipboard
If a user takes a screenshot (Cmd+Ctrl+Shift+4 on Mac) and hits Cmd+V in your Flutter app, it should paste the image.

```dart
import 'package:super_clipboard/super_clipboard.dart';

void _handlePaste() async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return;
  
  final reader = await clipboard.read();
  
  if (reader.canProvide(Formats.png)) {
    reader.getFile(
      Formats.png,
      (file) async {
        final bytes = await file.readAll();
        // Render or upload the image bytes
      },
    );
  }
}
```

### Keyboard Shortcut Binding
You must bind the paste action to the OS-level shortcut using a `Shortcuts` and `Actions` mapping in your widget tree, specifically listening for `LogicalKeyboardKey.keyV` + Control/Meta.

## 3. Right-Click Native Menus vs Flutter Menus

When a user right-clicks an image in a native web app, they expect "Copy Image", "Save Image As...", etc.
Because Flutter renders to a canvas, the browser doesn't know there is an image there.

**Workaround for exact fidelity**:
If you need users to be able to right-click and save an image, you must inject an actual HTML `<img>` tag over the Flutter canvas using `HtmlElementView`.

```dart
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

void registerImageElement(String url, String viewType) {
  ui_web.platformViewRegistry.registerViewFactory(
    viewType,
    (int viewId) => html.ImageElement()
      ..src = url
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'contain', // Important for styling
  );
}
```
Using `HtmlElementView` delegates the rendering to the DOM, restoring native browser context menus for that specific visual element.
