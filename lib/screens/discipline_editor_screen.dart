import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/models.dart';

/// Admin-only creator for a new discipline. RLS enforces admin-only writes.
class DisciplineEditorScreen extends StatefulWidget {
  const DisciplineEditorScreen({super.key});

  @override
  State<DisciplineEditorScreen> createState() => _DisciplineEditorScreenState();
}

class _DisciplineEditorScreenState extends State<DisciplineEditorScreen> {
  final _id = TextEditingController();
  final _name = TextEditingController();
  final _tagline = TextEditingController();
  String _icon = 'category';
  bool _busy = false;
  String? _error;

  /// Icon keys the app knows how to render (see disciplineIcon()).
  static const _iconKeys = [
    'terminal', 'precision_manufacturing', 'biotech', 'rocket_launch',
    'palette', 'functions', 'science', 'public', 'psychology', 'music_note',
    'engineering', 'calculate', 'category',
  ];

  static final _slugRe = RegExp(r'^[a-z0-9_]+$');

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _tagline.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = _id.text.trim().toLowerCase();
    final name = _name.text.trim();
    if (!_slugRe.hasMatch(id)) {
      setState(() => _error = 'Id must be lowercase letters, numbers, or _.');
      return;
    }
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await appState.createDiscipline({
        'id': id,
        'name': name,
        'tagline': _tagline.text.trim(),
        'icon': _icon,
        'sort_order': appState.disciplines.length + 1,
      });
      if (!mounted) return;
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Discipline created')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not create. The id may already be taken.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('New discipline')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _id,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Id (slug)',
                    hintText: 'e.g. civicverse',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _name,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. CivicVerse',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _tagline,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Tagline',
                    hintText: 'e.g. Government & society',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _icon,
                  decoration: const InputDecoration(
                    labelText: 'Icon',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final k in _iconKeys)
                      DropdownMenuItem(
                        value: k,
                        child: Row(
                          children: [
                            Icon(disciplineIcon(k),
                                size: 20, color: theme.colorScheme.primary),
                            const SizedBox(width: 10),
                            Text(k),
                          ],
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _icon = v ?? 'category'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.add),
                  label: const Text('Create discipline'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
