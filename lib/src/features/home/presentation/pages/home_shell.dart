import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/constants/riot_constants.dart';
import '../../../../core/network/webview_cookie_reader.dart';
import '../../../../core/utils/logger.dart';
import '../../../../services/background/background_scheduler.dart';
import '../../../../services/background/shop_sync_service.dart';
import '../../../collection/presentation/pages/collection_page.dart';
import '../../../player/presentation/widgets/player_header.dart';
import '../../../store/presentation/pages/daily_shop_page.dart';
import '../../../store/presentation/pages/night_market_page.dart';
import '../../../wishlist/presentation/pages/wishlist_page.dart';
import '../widgets/account_sheet.dart';

/// The signed-in shell: persistent header, four tabs, bottom navigation.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  late int _index = widget.initialTab;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // A cold start never produces a lifecycle callback: the app is already
    // `resumed` by the time this observer is registered, so nothing is
    // dispatched. Without this, launching the app fresh — which is exactly what
    // opening it at 02:00 to look at the new shop is — ran no sync at all, and
    // the rotation went unnoticed while the Daily Shop tab happily displayed it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOnResume());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app is the most likely moment for the shop to have
    // rotated while we were not running, and it is the one check that costs the
    // user nothing — the background worker may well have been deferred.
    if (state == AppLifecycleState.resumed) {
      _syncOnResume();
    }
  }

  Future<void> _syncOnResume() async {
    // Before the sync, because the sync is what needs a working session.
    await _refreshSessionCookie();

    // You are looking at the app, so any digest already in the shade has served
    // its purpose. Deliberately not `cancelScheduled` — see `dismissDelivered`.
    await ref.read(notificationServiceProvider).dismissDelivered();

    try {
      final ShopSyncOutcome outcome = await ShopSyncService(
        ref.read(appDependenciesProvider),
      ).sync();
      if (mounted) ref.invalidate(shopControllerProvider);

      // Aim the targeted background check at the reset we now know about.
      // Previously only the worker did this, which left a hole: on a phone
      // where the periodic check had not yet run, nothing was ever pointed at
      // the rotation, and the first notification waited on a six-hourly sweep.
      final DateTime? next = outcome.nextResetAt;
      if (next != null) await BackgroundScheduler.scheduleResetCheck(next);
    } on Object {
      // Silent: the tab's own error state covers a failed foreground fetch.
    }
  }

  /// Copies the current `ssid` out of the WebView jar into secure storage.
  ///
  /// Our copy is taken once at sign-in. If that capture came back empty, or
  /// Riot has rotated the cookie since, silent refresh fails — and the only
  /// symptom is the app asking you to sign in again every time you open it,
  /// while the background worker quietly stops scheduling notifications
  /// altogether. Re-reading it on every resume repairs both, and costs a
  /// method channel call.
  ///
  /// Foreground only: the jar is read through the Activity, which does not
  /// exist in the WorkManager isolate.
  Future<void> _refreshSessionCookie() async {
    if (ref.read(appModeProvider) != AppMode.live) return;
    try {
      const WebViewCookieReader cookies = WebViewCookieReader();
      final Map<String, String> jar = await cookies.cookiesFor(
        RiotConstants.authBase,
      );
      await ref.read(authApiProvider).captureSessionCookie(jar);
    } on Object catch (e) {
      Log.d('Session', 'Could not refresh the stored cookie: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            PlayerHeader(
              onTapProfile: () => AccountSheet.open(context),
            ),
            Expanded(
              // IndexedStack, not a PageView: switching tabs must not discard
              // scroll position or re-trigger the shop fetch.
              child: IndexedStack(
                index: _index,
                children: const <Widget>[
                  DailyShopPage(),
                  NightMarketPage(),
                  WishlistPage(),
                  CollectionPage(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (int index) =>
              setState(() => _index = index),
          destinations: const <NavigationDestination>[
            NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront_rounded),
              label: 'Daily Shop',
            ),
            NavigationDestination(
              icon: Icon(Icons.nightlight_outlined),
              selectedIcon: Icon(Icons.nightlight_round),
              label: 'Night Market',
            ),
            NavigationDestination(
              icon: Icon(Icons.favorite_border_rounded),
              selectedIcon: Icon(Icons.favorite_rounded),
              label: 'Wishlist',
            ),
            NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2_rounded),
              label: 'Collection',
            ),
          ],
        ),
      ),
    );
  }
}
