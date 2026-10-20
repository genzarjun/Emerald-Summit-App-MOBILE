import 'package:flutter/material.dart';

import '../models/schools.dart';
import '../models/user_profile.dart';

/// The school question on sign-up and Edit profile: a dropdown of
/// [triValleySchools] plus "Other", which opens a text box for a school that
/// isn't listed.
///
/// [controller] always holds the answer that gets saved: the picked school's
/// name, the typed name under "Other", or empty. A saved answer that matches a
/// listed school (e.g. an older typed "Dublin High") opens on that school.
class SchoolPicker extends StatefulWidget {
  const SchoolPicker({
    super.key,
    required this.field,
    required this.controller,
    this.enabled = true,
  });

  final ProfileField field;
  final TextEditingController controller;
  final bool enabled;

  @override
  State<SchoolPicker> createState() => _SchoolPickerState();
}

class _SchoolPickerState extends State<SchoolPicker> {
  static const _other = '__other__';
  static const _none = '__none__';

  String? _choice;

  @override
  void initState() {
    super.initState();
    final saved = widget.controller.text.trim();
    final listed = matchTriValleySchool(saved);
    if (listed != null) {
      _choice = listed.name;
      widget.controller.text = listed.name;
    } else if (saved.isNotEmpty) {
      _choice = _other;
    }
  }

  void _pick(String? value) {
    setState(() => _choice = value);
    if (value == _other) {
      // Start the box empty unless they had already typed a school.
      if (matchTriValleySchool(widget.controller.text) != null) {
        widget.controller.clear();
      }
    } else if (value == null || value == _none) {
      widget.controller.clear();
    } else {
      widget.controller.text = value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final values = [
      if (!widget.field.required) _none,
      for (final s in triValleySchools) s.name,
      _other,
    ];
    String labelOf(String v) => switch (v) {
      _none => 'None',
      _other => 'Other (not listed)',
      _ => v,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _choice,
          isExpanded: true,
          menuMaxHeight: 420,
          onChanged: widget.enabled ? _pick : null,
          decoration: InputDecoration(
            labelText: widget.field.label,
            helperText: widget.field.helper,
            helperMaxLines: 3,
            border: const OutlineInputBorder(),
          ),
          selectedItemBuilder: (_) => [
            for (final v in values)
              Text(labelOf(v), overflow: TextOverflow.ellipsis),
          ],
          items: [
            for (final v in values)
              DropdownMenuItem(
                value: v,
                child: switch (v) {
                  _none || _other => Text(labelOf(v)),
                  _ => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v, overflow: TextOverflow.ellipsis),
                      Text(
                        triValleySchools.firstWhere((s) => s.name == v).city,
                        style: muted,
                      ),
                    ],
                  ),
                },
              ),
          ],
        ),
        if (_choice == _other) ...[
          const SizedBox(height: 12),
          TextField(
            controller: widget.controller,
            enabled: widget.enabled,
            autofocus: widget.controller.text.isEmpty,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'School name',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }
}
