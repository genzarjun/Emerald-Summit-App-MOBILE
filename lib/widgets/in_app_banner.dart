import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

/// One banner's content.
class BannerMessage {
  const BannerMessage({required this.title, required this.body, this.onTap});
  final String title;
  final String body;
  final VoidCallback? onTap;
}

/// Global controller for the Instagram-style in-app banner. When a new
/// announcement arrives via Realtime while the app is foregrounded, the app
/// calls [show]; the banner slides in over whatever tab is open, then
/// auto-dismisses.
class InAppBannerController extends ChangeNotifier {
  BannerMessage? _current;
  BannerMessage? get current => _current;

  Timer? _timer;

  void show(BannerMessage message,
      {Duration duration = const Duration(seconds: 4)}) {
    _current = message;
    notifyListeners();
    _timer?.cancel();
    _timer = Timer(duration, dismiss);
  }

  void dismiss() {
    _timer?.cancel();
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Global instance, driven by the announcements Realtime subscription.
final inAppBanner = InAppBannerController();

/// Wraps the app so a banner can float above any screen. Place it in the
/// MaterialApp `builder` around `child`.
class InAppBannerHost extends StatelessWidget {
  const InAppBannerHost({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: ListenableBuilder(
              listenable: inAppBanner,
              builder: (context, _) {
                final msg = inAppBanner.current;
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  transitionBuilder: (child, animation) => SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, -1),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                        parent: animation, curve: Curves.easeOutCubic)),
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: msg == null
                      ? const SizedBox.shrink(key: ValueKey('none'))
                      : _BannerCard(key: const ValueKey('banner'), message: msg),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({super.key, required this.message});
  final BannerMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.surface,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            inAppBanner.dismiss();
            message.onTap?.call();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: EmeraldTheme.mist,
                  child: Icon(Icons.campaign,
                      size: 20, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(message.title,
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(message.body,
                          style: theme.textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: inAppBanner.dismiss,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
