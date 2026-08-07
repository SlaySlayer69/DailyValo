import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/presentation/pages/login_page.dart';
import '../features/home/presentation/pages/home_shell.dart';
import '../services/notifications/notification_service.dart';
import 'providers.dart';
import 'theme/app_theme.dart';

/// Root widget.
class DailyValoApp extends ConsumerWidget {
  const DailyValoApp({super.key, this.initialTab = 0});

  /// Tab to land on — set when the app was launched from a notification.
  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: _AuthGate(initialTab: initialTab),
    );
  }
}

/// Chooses between the sign-in screen and the tabbed shell.
///
/// Driven by [appModeProvider], which in turn watches the session manager — so
/// when the auth interceptor gives up on refreshing a dead session, the user is
/// returned to the login screen without any screen needing to handle it.
class _AuthGate extends ConsumerWidget {
  const _AuthGate({required this.initialTab});

  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppMode mode = ref.watch(appModeProvider);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: switch (mode) {
        AppMode.signedOut => const LoginPage(key: ValueKey<String>('login')),
        AppMode.demo || AppMode.live => HomeShell(
          key: const ValueKey<String>('home'),
          initialTab: initialTab,
        ),
      },
    );
  }
}
