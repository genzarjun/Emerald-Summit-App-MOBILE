import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend/service_locator.dart';
import '../models/models.dart';
import '../models/user_profile.dart';

/// Front-desk QR scanner. Reads an attendee's check-in pass (the QR on their
/// Profile tab) and checks them in instantly; the result card offers Undo.
/// The camera stays live, so the volunteer can scan the next person straight
/// away. Reached only from [FrontDeskScreen], so only front-desk volunteers and
/// admins are ever asked for camera access — and the server re-checks the
/// capability on every scan.
class FrontDeskScannerScreen extends StatefulWidget {
  const FrontDeskScannerScreen({super.key});

  @override
  State<FrontDeskScannerScreen> createState() => _FrontDeskScannerScreenState();
}

/// What the result card shows.
sealed class _Card {
  const _Card();
}

class _Working extends _Card {
  const _Working();
}

class _Scanned extends _Card {
  const _Scanned(this.result, {this.undone = false});
  final ScanCheckinResult result;
  final bool undone;
}

class _Problem extends _Card {
  const _Problem(this.title, this.message);
  final String title;
  final String message;
}

class _FrontDeskScannerScreenState extends State<FrontDeskScannerScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  _Card? _card;

  /// The raw value behind [_card]. The camera keeps reporting a code for as
  /// long as it's in view, so the same one is ignored until the card is
  /// dismissed — a different code is handled right away.
  String? _lastCode;
  bool _busy = false;
  int _checkedInHere = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (raw == null || raw == _lastCode) return;
    _lastCode = raw;

    final id = parseCheckinPass(raw);
    if (id == null) {
      HapticFeedback.vibrate();
      setState(() => _card = const _Problem('Not a check-in pass',
          "This QR code isn't an Emerald Summit pass. Ask the attendee to open "
              'Profile in the app.'));
      return;
    }

    _busy = true;
    setState(() => _card = const _Working());
    try {
      final result = await attendanceRepository.scanSummitCheckin(id);
      if (!mounted) return;
      switch (result.outcome) {
        case ScanCheckinOutcome.checkedIn:
          HapticFeedback.mediumImpact();
          _checkedInHere++;
        case ScanCheckinOutcome.alreadyCheckedIn:
          HapticFeedback.heavyImpact();
        case ScanCheckinOutcome.notFound:
          HapticFeedback.vibrate();
      }
      setState(() => _card = _Scanned(result));
    } catch (_) {
      if (!mounted) return;
      HapticFeedback.vibrate();
      // Let the same pass be retried.
      _lastCode = null;
      setState(() => _card = const _Problem("Couldn't check in",
          'Check your connection and scan again. If it keeps failing, you may '
              'not have front-desk access.'));
    } finally {
      _busy = false;
    }
  }

  Future<void> _undo(ScanCheckinResult result) async {
    setState(() => _busy = true);
    try {
      await attendanceRepository.markSummitCheckin(result.attendeeId, false);
      if (!mounted) return;
      _checkedInHere--;
      setState(() => _card = _Scanned(result, undone: true));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't undo. Try again.")));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _dismiss() => setState(() {
        _card = null;
        _lastCode = null;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan check-in pass'),
        actions: [
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (context, state, _) {
              if (state.torchState == TorchState.unavailable) {
                return const SizedBox.shrink();
              }
              final on = state.torchState == TorchState.on;
              return IconButton(
                tooltip: on ? 'Turn off flashlight' : 'Turn on flashlight',
                icon: Icon(on ? Icons.flash_on : Icons.flash_off),
                onPressed: _controller.toggleTorch,
              );
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) =>
                _CameraError(error: error, controller: _controller),
          ),
          const IgnorePointer(child: _Viewfinder()),
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: Center(
              child: _Pill(
                text: _checkedInHere == 0
                    ? "Point at an attendee's QR pass"
                    : '$_checkedInHere checked in on this device',
              ),
            ),
          ),
          if (_card != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: SafeArea(
                top: false,
                child: _ResultCard(
                  card: _card!,
                  busy: _busy,
                  onUndo: _undo,
                  onDismiss: _dismiss,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A square frame showing where to hold the code (decorative — the whole
/// camera frame is scanned).
class _Viewfinder extends StatelessWidget {
  const _Viewfinder();

  @override
  Widget build(BuildContext context) {
    final side = MediaQuery.sizeOf(context).shortestSide * .65;
    return Center(
      child: Container(
        width: side,
        height: side,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 3),
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: Colors.white)),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.card,
    required this.busy,
    required this.onUndo,
    required this.onDismiss,
  });

  final _Card card;
  final bool busy;
  final ValueChanged<ScanCheckinResult> onUndo;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = theme.colorScheme;

    if (card is _Working) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            children: [
              SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 3)),
              SizedBox(width: 16),
              Text('Checking in…'),
            ],
          ),
        ),
      );
    }

    final (IconData icon, Color color, String title, String body,
        ScanCheckinResult? undoable) = switch (card) {
      _Problem(:final title, :final message) =>
        (Icons.error_outline, s.error, title, message, null),
      _Scanned(:final result, undone: true) => (
          Icons.undo,
          s.onSurfaceVariant,
          'Check-in undone',
          _who(result),
          null,
        ),
      _Scanned(:final result) => switch (result.outcome) {
          ScanCheckinOutcome.checkedIn => (
              Icons.check_circle,
              s.primary,
              'Checked in',
              _who(result),
              result,
            ),
          ScanCheckinOutcome.alreadyCheckedIn => (
              Icons.info_outline,
              s.tertiary,
              'Already checked in',
              [
                _who(result),
                if (result.checkedInAt != null)
                  'Arrived at '
                      '${TimeOfDay.fromDateTime(result.checkedInAt!).format(context)}',
              ].join('\n'),
              null,
            ),
          ScanCheckinOutcome.notFound => (
              Icons.person_off_outlined,
              s.error,
              'No account found',
              "This pass doesn't match anyone registered for the summit. "
                  'Try searching the attendee list instead.',
              null,
            ),
        },
      _Working() => throw StateError('handled above'),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 32),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(color: color)),
                      const SizedBox(height: 4),
                      Text(body, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (undoable != null)
                  TextButton(
                    onPressed: busy ? null : () => onUndo(undoable),
                    child: const Text('Undo'),
                  ),
                TextButton(
                  onPressed: busy ? null : onDismiss,
                  child: const Text('Scan next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// "Name · Role", falling back to the email when there's no name.
  static String _who(ScanCheckinResult r) {
    final name = r.name.isNotEmpty ? r.name : r.email;
    final role = r.role.isEmpty
        ? ''
        : ' · ${SummitRoleX.fromId(r.role).label}';
    return '$name$role';
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error, required this.controller});

  final MobileScannerException error;
  final MobileScannerController controller;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    final unsupported = error.errorCode == MobileScannerErrorCode.unsupported;
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    final theme = Theme.of(context);
    const white = Colors.white;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(denied ? Icons.no_photography_outlined : Icons.videocam_off,
                  color: white, size: 48),
              const SizedBox(height: 16),
              Text(
                denied
                    ? 'Camera access is off'
                    : unsupported
                        ? 'No camera available'
                        : "Couldn't start the camera",
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(color: white),
              ),
              const SizedBox(height: 8),
              Text(
                denied
                    ? 'Scanning check-in passes needs the camera. '
                        '${isIOS ? 'Turn on Camera for Emerald Summit in Settings.' : 'Allow camera access when asked, or turn it on in Settings › Apps › Emerald Summit › Permissions.'}'
                    : unsupported
                        ? "This device can't scan. Use the attendee list to "
                            'check people in by name.'
                        : 'Try again, or use the attendee list to check people '
                            'in by name.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: white.withValues(alpha: .8)),
              ),
              const SizedBox(height: 20),
              if (denied && isIOS)
                FilledButton(
                  onPressed: () => launchUrl(Uri.parse('app-settings:')),
                  child: const Text('Open Settings'),
                )
              else if (!unsupported)
                FilledButton(
                  onPressed: () => controller.start(),
                  child: const Text('Try again'),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(foregroundColor: white),
                child: const Text('Back to attendee list'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
