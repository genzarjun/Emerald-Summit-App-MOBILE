import 'package:flutter/material.dart';

import 'app_state.dart';
import 'backend/service_locator.dart';
import 'theme.dart';
import 'widgets/in_app_banner.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/root_nav.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pick and initialize the backend (live if configured, else in-memory sample).
  // This is the whole app's single backend touch-point.
  await configureBackend();

  if (!backendInfo.isLive) {
    // Sample mode goes straight to the app (no auth gate), so prime the catalog
    // and feed here. With a live backend the auth gate loads them after the
    // profile.
    await appState.loadCatalog();
    await appState.loadAnnouncements();
    await appState.loadReadAnnouncements();
    await appState.loadGallery();
  }

  runApp(const EmeraldSummitApp());
}

/// Root application widget for the Emerald Summit companion app.
class EmeraldSummitApp extends StatelessWidget {
  const EmeraldSummitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emerald Summit',
      debugShowCheckedModeBanner: false,
      theme: EmeraldTheme.light(),
      darkTheme: EmeraldTheme.dark(),
      themeMode: ThemeMode.light,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            // iOS honors the system-wide "Bold Text" accessibility toggle
            // (Settings → Display & Brightness). When it's on, Flutter renders
            // every label heavy — which is why the iPhone 14 test build looked
            // bold while Android, which has no equivalent global setting, did
            // not. Reset it so text renders at the weights the design intends.
            boldText: false,
            // iOS Dynamic Type can scale text well beyond the layout's
            // headroom, pushing labels onto a second line ("Resourc es") or
            // off-screen. Clamp the scale factor so accessibility text sizing
            // still works, but can't break the layout.
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 1.0,
              maxScaleFactor: 1.3,
            ),
          ),
          // Host the Instagram-style in-app banner above every screen.
          child: InAppBannerHost(child: child!),
        );
      },
      // The animated splash runs first, then hands off to the real first
      // screen: with a live backend, gate the app behind sign-in; in sample
      // mode (no backend) go straight to the app on demo data.
      home: SplashScreen(
        next: backendInfo.isLive ? const AuthGate() : const RootNav(),
      ),
    );
  }
}
