import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_state.dart';
import '../backend/service_locator.dart';
import '../models/models.dart';
import '../theme.dart';

/// The signed-in user's front-desk check-in pass on the Profile tab: a QR code
/// of their user id (what the front-desk scanner reads) plus whether they've
/// been checked in yet. Tapping the code opens a full-screen copy that's
/// easier to scan.
class CheckinPassCard extends StatefulWidget {
  const CheckinPassCard({super.key, required this.userId});

  final String userId;

  @override
  State<CheckinPassCard> createState() => _CheckinPassCardState();
}

class _CheckinPassCardState extends State<CheckinPassCard>
    with WidgetsBindingObserver {
  /// Null until loaded, and stays null if the status can't be read (offline,
  /// or the QR SQL hasn't been run) — the code itself still works.
  MyCheckinStatus? _status;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back to the app after being scanned shows the new status.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final status = await attendanceRepository.fetchMyCheckin();
      if (mounted) setState(() => _status = status);
    } catch (_) {
      // Leave the last known status in place.
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _openFullScreen() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => _FullScreenPass(
              userId: widget.userId, status: _status),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Semantics(
              button: true,
              label: 'Your check-in QR code. Tap to enlarge.',
              child: InkWell(
                onTap: _openFullScreen,
                borderRadius: BorderRadius.circular(12),
                child: _PassQr(data: widget.userId, size: 112),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Check-in pass',
                            style: theme.textTheme.titleMedium),
                      ),
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: _refreshing
                            ? const Padding(
                                padding: EdgeInsets.all(8),
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : IconButton(
                                tooltip: 'Refresh check-in status',
                                padding: EdgeInsets.zero,
                                iconSize: 20,
                                icon: const Icon(Icons.refresh),
                                onPressed: _refresh,
                              ),
                      ),
                    ],
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: 4),
                    _StatusLine(status: _status!),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    'Show this at the front desk when you arrive on summit day.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _openFullScreen,
                    icon: const Icon(Icons.open_in_full, size: 18),
                    label: const Text('Show full screen'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The QR itself, always dark-on-white (in both themes) so phone cameras read
/// it reliably.
class _PassQr extends StatelessWidget {
  const _PassQr({required this.data, required this.size});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(size * .06),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: QrImageView(
        data: data,
        size: size,
        padding: EdgeInsets.zero,
        backgroundColor: Colors.white,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
        eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square, color: EmeraldTheme.deepEmerald),
        dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: EmeraldTheme.deepEmerald),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status});

  final MyCheckinStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final at = status.checkedInAt;
    final text = status.present
        ? (at == null
            ? 'Checked in'
            : 'Checked in · ${TimeOfDay.fromDateTime(at).format(context)}')
        : 'Not checked in yet';
    final color = status.present
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(status.present ? Icons.check_circle : Icons.schedule,
            size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text,
              style: theme.textTheme.labelLarge?.copyWith(color: color)),
        ),
      ],
    );
  }
}

class _FullScreenPass extends StatelessWidget {
  const _FullScreenPass({required this.userId, required this.status});

  final String userId;
  final MyCheckinStatus? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final side = (MediaQuery.sizeOf(context).shortestSide - 96).clamp(180.0, 360.0);
    return Scaffold(
      appBar: AppBar(title: const Text('Check-in pass')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(appState.userName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(appState.userRole,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: theme.colorScheme.primary)),
                const SizedBox(height: 24),
                _PassQr(data: userId, size: side),
                if (status != null) ...[
                  const SizedBox(height: 20),
                  _StatusLine(status: status!),
                ],
                const SizedBox(height: 16),
                Text(
                  'Hold your phone up to the front-desk volunteer. '
                  'Turning up your screen brightness helps it scan.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
