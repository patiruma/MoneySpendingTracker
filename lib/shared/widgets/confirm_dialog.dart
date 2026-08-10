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
Future<String?> promptForName(
  BuildContext context, {
  required String title,
  String? initialValue,
  String label = 'Name',
  String confirmLabel = 'Next',
}) async {
  final TextEditingController controller = TextEditingController(text: initialValue);
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  try {
    return await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        void submit() {
          if (formKey.currentState?.validate() ?? false) {
            Navigator.of(dialogContext).pop(controller.text.trim());
          }
        }

        return AlertDialog(
          title: Text(title),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: label),
              validator: (String? value) =>
                  (value == null || value.trim().isEmpty) ? 'Enter a name' : null,
              onFieldSubmitted: (_) => submit(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(onPressed: submit, child: Text(confirmLabel)),
          ],
        );
      },
    );
  } finally {
    controller.dispose();
  }
}
