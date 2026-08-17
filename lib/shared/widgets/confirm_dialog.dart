import 'package:flutter/material.dart';

/// The single confirmation primitive (§3.1). Every create, rename, move, and
/// delete routes through here — never wire a structural mutation straight to an
/// `onPressed`.
///
/// [message] should state the impact in plain language, including the counts
/// from the matching `preview*` repository call.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      final ColorScheme colors = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                  )
                : null,
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// A blocking dialog explaining why an action can't proceed — used when a
/// `preview*` call comes back invalid (e.g. a move that would cycle).
Future<void> blockedDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Prompts for a single line of text (new name, new label name).
/// Returns null when cancelled. Confirmation of the *impact* happens separately
/// — this only collects the input.
///
/// The controller is owned by [_NamePromptDialog], **not** by this function.
/// Disposing it here — in a `finally` after the `await` — tears it down while
/// the dialog route's exit transition is still animating the field, which
/// rebuilds a `TextFormField` around a dead controller and trips
/// `_dependents.isEmpty` / "used after being disposed". Tying the controller's
/// lifetime to the widget's `State` is what makes the teardown ordering correct.
Future<String?> promptForName(
  BuildContext context, {
  required String title,
  String? initialValue,
  String label = 'Name',
  String confirmLabel = 'Next',
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => _NamePromptDialog(
      title: title,
      initialValue: initialValue,
      label: label,
      confirmLabel: confirmLabel,
    ),
  );
}

class _NamePromptDialog extends StatefulWidget {
  const _NamePromptDialog({
    required this.title,
    required this.initialValue,
    required this.label,
    required this.confirmLabel,
  });

  final String title;
  final String? initialValue;
  final String label;
  final String confirmLabel;

  @override
  State<_NamePromptDialog> createState() => _NamePromptDialogState();
}

class _NamePromptDialogState extends State<_NamePromptDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: widget.label),
          validator: (String? value) =>
              (value == null || value.trim().isEmpty) ? 'Enter a name' : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
