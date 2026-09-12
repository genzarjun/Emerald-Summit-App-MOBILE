import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models/models.dart';

/// Admin-only manager for the rooms catalog. Sessions are tied to these rooms
/// (in the session editor), and volunteers are assigned to those sessions. RLS
/// enforces admin-only writes; this screen just gates the UI.
class RoomsManagerScreen extends StatefulWidget {
  const RoomsManagerScreen({super.key});

  @override
  State<RoomsManagerScreen> createState() => _RoomsManagerScreenState();
}

class _RoomsManagerScreenState extends State<RoomsManagerScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await appState.loadRooms();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addOrRename({Room? room}) async {
    final controller = TextEditingController(text: room?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(room == null ? 'Add room' : 'Rename room'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Room name',
            hintText: 'e.g. Room 204, Gym A',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(room == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (room == null) {
        await appState.createRoom({'name': name});
      } else {
        await appState.updateRoom(room.id, {'name': name});
      }
      if (mounted) setState(() {});
    } catch (e) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Could not save. A room with that name may exist.')));
    }
  }

  Future<void> _delete(Room room) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete room?'),
        content: Text(
            '“${room.name}” will be removed. Sessions in it become "Unassigned" '
            '— they are not deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await appState.deleteRoom(room.id);
      if (mounted) setState(() {});
    } catch (e) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Could not delete the room.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rooms = appState.rooms;
    return Scaffold(
      appBar: AppBar(title: const Text('Manage rooms')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrRename(),
        icon: const Icon(Icons.add),
        label: const Text('Add room'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : rooms.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No rooms yet. Add the rooms your sessions will use — '
                        'then pick one when creating a session.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: rooms.length,
                    itemBuilder: (context, i) {
                      final room = rooms[i];
                      return ListTile(
                        leading: const Icon(Icons.meeting_room_outlined),
                        title: Text(room.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Rename',
                              onPressed: () => _addOrRename(room: room),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Delete',
                              onPressed: () => _delete(room),
                            ),
                          ],
                        ),
                      );
                    },
                    separatorBuilder: (_, _) => const Divider(height: 1),
                  ),
      ),
    );
  }
}
