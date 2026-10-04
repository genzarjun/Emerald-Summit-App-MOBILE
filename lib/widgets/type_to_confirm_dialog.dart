import 'package:flutter/material.dart';

/// Asks the user to type [name] exactly before a destructive action can go
/// ahead, so a big delete can't happen from a stray tap. Resolves to true only
/// when the name was typed and the destructive button pressed.
Future<bool> confirmByTypingName(
  BuildContext context, {
  required String title,
  required String message,
  required String name,
  String confirmLabel = 'Delete',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => _TypeToConfirmDialog(
      title: title,
      message: message,
      name: name,
      confirmLabel: confirmLabel,
    ),
  );
  return confirmed == true;
}

class _TypeToConfirmDialog extends StatefulWidget {
  const _TypeToConfirmDialog({
    required this.title,
    required this.message,
    required this.name,
    required this.confirmLabel,
  });

  final String title;
  final String message;
  final String name;
  final String confirmLabel;

  @override
  State<_TypeToConfirmDialog> createState() => _TypeToConfirmDialogState();
}

class _TypeToConfirmDialogState extends State<_TypeToConfirmDialog> {
  final _typed = TextEditingController();

  bool get _matches => _typed.text.trim() == widget.name.trim();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message),
            const SizedBox(height: 16),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Type '),
                TextSpan(
                  text: widget.name.trim(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(text: ' to confirm.'),
              ]),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _typed,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (_matches) Navigator.pop(context, true);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _matches ? () => Navigator.pop(context, true) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
