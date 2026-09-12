import 'dart:async';

import 'package:flutter/material.dart';

import '../backend/service_locator.dart';
import '../models/models.dart';

/// Front-desk (summit-wide) check-in. A volunteer with the front-desk capability
/// can search every attendee and mark them as arrived. Independent of session
/// assignments; the capability is enforced server-side by every RPC here.
class FrontDeskScreen extends StatefulWidget {
  const FrontDeskScreen({super.key});

  @override
  State<FrontDeskScreen> createState() => _FrontDeskScreenState();
}

class _FrontDeskScreenState extends State<FrontDeskScreen> {
  bool _loading = true;
  String? _error;
  List<Attendee> _attendees = const [];
  String _query = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await attendanceRepository.fetchAttendeeDirectory(_query);
      if (!mounted) return;
      setState(() {
        _attendees = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't load attendees. You may not have front-desk access.";
        _loading = false;
      });
    }
  }

  void _onQueryChanged(String value) {
    _query = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _toggle(Attendee a, bool value) async {
    final i = _attendees.indexWhere((x) => x.id == a.id);
    if (i < 0) return;
    setState(() => _attendees[i] = _attendees[i].copyWith(present: value));
    try {
      await attendanceRepository.markSummitCheckin(a.id, value);
    } catch (e) {
      if (!mounted) return;
      setState(() => _attendees[i] = _attendees[i].copyWith(present: !value));
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save check-in.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final present = _attendees.where((a) => a.present).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Front desk check-in')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search by name or email',
                  border: OutlineInputBorder(),
                ),
                onChanged: _onQueryChanged,
              ),
            ),
            if (!_loading && _error == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('$present checked in of ${_attendees.length} shown',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(_error!,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium),
                          ),
                        )
                      : _attendees.isEmpty
                          ? Center(
                              child: Text('No matching attendees.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant)),
                            )
                          : ListView.separated(
                              itemCount: _attendees.length,
                              itemBuilder: (context, i) {
                                final a = _attendees[i];
                                return SwitchListTile(
                                  value: a.present,
                                  onChanged: (v) => _toggle(a, v),
                                  title:
                                      Text(a.name.isEmpty ? a.email : a.name),
                                  subtitle: Text(a.present
                                      ? 'Checked in'
                                      : 'Not arrived'),
                                  secondary: CircleAvatar(
                                    backgroundColor: a.present
                                        ? theme.colorScheme.primaryContainer
                                        : theme
                                            .colorScheme.surfaceContainerHighest,
                                    child: Icon(
                                      a.present
                                          ? Icons.how_to_reg
                                          : Icons.person_outline,
                                      color: a.present
                                          ? theme.colorScheme.onPrimaryContainer
                                          : theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                );
                              },
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
