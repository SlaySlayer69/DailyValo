import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../app/theme/app_colors.dart';
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
    try {
      await ShopSyncService(ref.read(appDependenciesProvider)).sync();
      if (mounted) ref.invalidate(shopControllerProvider);
    } on Object {
      // Silent: the tab's own error state covers a failed foreground fetch.
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
