# Forms, Autofill, & Input Fidelity

Text input on the web has deep OS integrations: Password managers (1Password, Chrome Autofill), spellcheck, grammar extensions (Grammarly), and hardware vs software keyboards.

## 1. Autofill Integration

To allow browsers and password managers to understand your Flutter forms, you must group them and tag them with `AutofillHints`.

```dart
AutofillGroup(
  child: Column(
    children: [
      TextField(
        autofillHints: const [AutofillHints.email],
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(labelText: 'Email'),
      ),
      TextField(
        autofillHints: const [AutofillHints.password],
        obscureText: true,
        decoration: InputDecoration(labelText: 'Password'),
      ),
      // Crucial: A button to commit the autofill context
      ElevatedButton(
        onPressed: () {
          TextInput.finishAutofillContext();
          // submit form
        },
        child: Text('Log In'),
      )
    ],
  ),
)
```
**Why `finishAutofillContext`?** Password managers need to be told when the form is submitted successfully so they can prompt the user to "Save this password?".

## 2. Browser Extensions (Grammarly)

Because Flutter draws text to a Canvas, extensions like Grammarly cannot easily read or highlight the text. 
Flutter mitigates this by overlaying an invisible DOM `<textarea>` or `<input>` exactly over the Flutter `TextField` when it has focus.

To maximize compatibility:
- Avoid extremely complex text field styling that changes size rapidly.
- Do not obscure the text field with other Flutter widgets, as it might confuse the DOM overlay coordinates.

## 3. Keyboard Submission (The "Enter" Key)

Native web users expect to hit `Enter` to submit a form. In Flutter, you must explicitly listen for this using `onSubmitted` on the final text field, or by wrapping the form in a `Shortcuts` widget.

```dart
TextField(
  textInputAction: TextInputAction.go,
  onSubmitted: (value) {
    _submitForm();
  },
)
```

For broader keyboard shortcuts (like `Cmd+Enter` to send a message):
```dart
CallbackShortcuts(
  bindings: <ShortcutActivator, VoidCallback>{
    LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.enter): () {
      _sendMessage();
    },
    LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.enter): () {
      _sendMessage();
    },
  },
  child: Focus(
    autofocus: true,
    child: MyMessageComposer(),
  ),
)
```
