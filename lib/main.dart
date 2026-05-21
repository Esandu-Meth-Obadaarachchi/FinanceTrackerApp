import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/home_shell.dart';
import 'services/auth_service.dart';
import 'state/app_state.dart';
import 'theme/app_text.dart';
import 'theme/palette.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeController = ThemeController();
  await themeController.load();

  // Initialise Firebase. Stays gracefully degraded until
  // `flutterfire configure` injects the real project keys.
  bool firebaseReady = false;
  final configured =
      DefaultFirebaseOptions.currentPlatform.apiKey != 'PLACEHOLDER';
  if (configured) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      firebaseReady = true;
    } catch (_) {
      firebaseReady = false;
    }
  }

  runApp(FinTrackApp(
    themeController: themeController,
    firebaseReady: firebaseReady,
  ));
}

class FinTrackApp extends StatelessWidget {
  const FinTrackApp({
    super.key,
    required this.themeController,
    required this.firebaseReady,
  });

  final ThemeController themeController;
  final bool firebaseReady;

  ThemeData _theme(bool dark) {
    final colors = Palette.of(dark);
    final base = dark ? ThemeData.dark() : ThemeData.light();
    return base.copyWith(
      scaffoldBackgroundColor: colors.bg,
      colorScheme: (dark
              ? const ColorScheme.dark(primary: Color(0xFF3DEBA8))
              : const ColorScheme.light(primary: Color(0xFF3DEBA8)))
          .copyWith(surface: colors.card),
      textTheme: GoogleFonts.dmSansTextTheme(base.textTheme)
          .apply(bodyColor: colors.text, displayColor: colors.text),
      splashColor: const Color(0xFF3DEBA8).withValues(alpha: 0.08),
      highlightColor: const Color(0xFF3DEBA8).withValues(alpha: 0.05),
      datePickerTheme: DatePickerThemeData(backgroundColor: colors.card),
      dialogTheme: DialogThemeData(backgroundColor: colors.card),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            dark ? const Color(0xFF232B3E) : const Color(0xFF1A2030),
        contentTextStyle: sans(size: 13, color: Colors.white),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: themeController,
      child: Consumer<ThemeController>(
        builder: (context, theme, _) {
          return MaterialApp(
            title: 'FinTrack',
            debugShowCheckedModeBanner: false,
            theme: _theme(false),
            darkTheme: _theme(true),
            themeMode: theme.isDark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) {
              // Centre the app inside a phone-width frame on wide screens.
              return ColoredBox(
                color: Brand.backdrop,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              );
            },
            home: firebaseReady
                ? const AuthGate()
                : const _FirebaseNotConfigured(),
          );
        },
      ),
    );
  }
}

/// Routes between the auth screen and the app based on sign-in state.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    return StreamBuilder(
      stream: auth.authState,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF3DEBA8)),
            ),
          );
        }
        final user = snapshot.data;
        if (user == null) return const AuthScreen();

        // Scope a fresh AppState to the signed-in user.
        return ChangeNotifierProvider<AppState>(
          key: ValueKey(user.uid),
          create: (_) => AppState(user.uid),
          child: const HomeShell(),
        );
      },
    );
  }
}

/// Shown until `flutterfire configure` injects real Firebase keys.
class _FirebaseNotConfigured extends StatelessWidget {
  const _FirebaseNotConfigured();

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    return Scaffold(
      backgroundColor: colors.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: Color(0xFFFFB547)),
              const SizedBox(height: 16),
              Text('Firebase not configured yet',
                  textAlign: TextAlign.center,
                  style: sans(
                      size: 18,
                      weight: FontWeight.w700,
                      color: colors.text)),
              const SizedBox(height: 8),
              Text(
                'Run "flutterfire configure" to connect this app '
                'to your Firebase project, then restart.',
                textAlign: TextAlign.center,
                style: sans(size: 13.5, color: colors.sub),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
