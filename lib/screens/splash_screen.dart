import 'dart:async';

import 'package:flutter/material.dart';

/// A short brand introduction, followed by the real first screen.
/// The background matches the native launch screen to avoid a cold-start flash.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.next});

  final Widget next;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;
  bool _handedOff = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1200), _handOff);
  }

  void _handOff() {
    if (_handedOff || !mounted) return;
    _handedOff = true;
    _timer?.cancel();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: Duration(milliseconds: reduceMotion ? 0 : 200),
        pageBuilder: (_, _, _) => widget.next,
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const muted = Color(0xFFAEC7BA);
    return Scaffold(
      backgroundColor: const Color(0xFF02100B),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handOff,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth < 360 || constraints.maxHeight < 640;
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 20 : 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'EMERALD HIGH SCHOOL · DUBLIN, CA',
                            style: TextStyle(
                              color: muted,
                              fontSize: 11,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          SizedBox(height: compact ? 24 : 48),
                          ClipOval(
                            child: Image.asset(
                              'assets/branding/logo.png',
                              width: compact ? 64 : 88,
                              height: compact ? 64 : 88,
                              semanticLabel: 'Emerald Summit logo',
                            ),
                          ),
                          SizedBox(height: compact ? 20 : 28),
                          Text(
                            'Emerald\nSummit ’27',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: compact ? 36 : 46,
                              height: 1.06,
                              letterSpacing: -1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: compact ? 16 : 20),
                          Text(
                            'Student ideas. Shared in person.',
                            style: TextStyle(
                              color: muted,
                              fontSize: compact ? 14 : 16,
                              height: 1.5,
                            ),
                          ),
                          SizedBox(height: compact ? 24 : 48),
                          const Spacer(),
                          const Divider(color: Color(0xFF294437)),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              onPressed: _handOff,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Continue'),
                                  Icon(Icons.arrow_forward, size: 20),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
