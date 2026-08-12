import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../../app/providers.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/constants/storage_keys.dart';
import '../../../../core/platform/battery_optimisation.dart';
import '../../../../core/storage/local_store.dart';
import '../../../../features/store/data/models/shop.dart';
import '../../../../services/background/shop_sync_service.dart';
import '../../../../services/diagnostics/connection_diagnostics.dart';
import '../../../../services/notifications/notification_schedule.dart';
import '../../../../services/notifications/notification_service.dart';

/// Account and notification settings, reached from the header.
///
/// Kept as a sheet rather than a fifth tab — these are things you touch once.
class AccountSheet extends ConsumerStatefulWidget {
  const AccountSheet({super.key});

  static Future<void> open(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: AppColors.backgroundElevated,
      // Without this the sheet is capped at half the screen height, which cut
      // off the last two rows — "Send a test notification" was clipped and
      // "Sign out" was unreachable entirely.
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext _) => const AccountSheet(),
    );
  }

  @override
  ConsumerState<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends ConsumerState<AccountSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final LocalStore store = ref.watch(localStoreProvider);
    final AppMode mode = ref.watch(appModeProvider);

    final bool shopNotifications = store.setting<bool>(
      SettingKeys.shopNotificationsEnabled,
      true,
    );
    final bool wishlistNotifications = store.setting<bool>(
      SettingKeys.wishlistNotificationsEnabled,
      true,
    );
    final NotificationSchedule schedule = NotificationSchedule.read(store);

    return SafeArea(
      // The sheet sizes itself to the content, but a small screen or a large
      // system font can still make the list taller than the viewport — so the
      // body scrolls instead of overflowing.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Settings',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.lg),

            SwitchListTile.adaptive(
              value: shopNotifications,
              onChanged: (bool value) => _setSetting(
                SettingKeys.shopNotificationsEnabled,
                value,
              ),
              title: const Text('Daily shop notification'),
              subtitle: const Text(
                'Summary of your four offers at reset',
              ),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile.adaptive(
              value: wishlistNotifications,
              onChanged: (bool value) => _setSetting(
                SettingKeys.wishlistNotificationsEnabled,
                value,
              ),
              title: const Text('Wishlist alert'),
              subtitle: const Text(
                'Alerts you when a wishlisted skin is in your shop',
              ),
              contentPadding: EdgeInsets.zero,
            ),

            SwitchListTile.adaptive(
              value: schedule.enabled,
              onChanged: _setFixedTime,
              title: const Text('Notification time'),
              subtitle: Text(
                schedule.enabled
                    ? 'Both notifications arrive at ${schedule.label}'
                    : 'Both notifications arrive at shop reset (00:00 UTC)',
              ),
              contentPadding: EdgeInsets.zero,
            ),
            // Only meaningful while the toggle is on, so it appears with it
            // rather than sitting there greyed out.
            if (schedule.enabled)
              ListTile(
                onTap: () => _pickTime(schedule),
                contentPadding: const EdgeInsets.only(left: AppSpacing.xl),
                leading: const Icon(Icons.schedule_rounded, size: 20),
                title: const Text('Deliver at'),
                trailing: Text(
                  schedule.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),

            const Divider(height: AppSpacing.xl),

            ListTile(
              onTap: _busy ? null : _runSyncNow,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sync_rounded),
              title: const Text('Check my shop now'),
              subtitle: const Text(
                'Runs the same check the background worker does',
              ),
              trailing: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
            ListTile(
              onTap: _busy ? null : _openBatterySettings,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.battery_saver_outlined),
              title: const Text('Allow background checks'),
              subtitle: const Text(
                'Set DailyValo to Unrestricted so the shop check can run '
                'overnight',
              ),
            ),
            ListTile(
              onTap: _busy ? null : _runDiagnostics,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.monitor_heart_outlined),
              title: const Text('Diagnostics'),
              subtitle: const Text(
                'Checks each Riot endpoint and shows what it returned',
              ),
            ),
            ListTile(
              onTap: _busy ? null : _sendTestNotification,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Test the shop notification'),
              subtitle: const Text(
                'Queues your real digest a minute from now, the same way the '
                'shop reset does',
              ),
            ),

            const Divider(height: AppSpacing.xl),

            ListTile(
              onTap: _busy ? null : _signOut,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.logout_rounded,
                color: AppColors.danger,
              ),
              title: Text(
                mode == AppMode.demo ? 'Leave demo mode' : 'Sign out',
                style: const TextStyle(color: AppColors.danger),
              ),
              subtitle: Text(
                mode == AppMode.demo
                    ? 'Return to the sign-in screen'
                    : 'Clears your saved Riot session from this device',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setSetting(String key, bool value) async {
    await ref.read(localStoreProvider).putSetting(key, value);
    if (mounted) setState(() {});
  }

  /// Turning the delivery time on is the first moment the app has a time to be
  /// punctual about, so it is the right moment — and the only honest one — to
  /// ask for the permission that makes it punctual.
  ///
  /// A refusal is not an error: the notification still arrives, batched into
  /// the next window Android is willing to wake for, which can be twenty
  /// minutes late. Say so once instead of letting it look broken.
  Future<void> _setFixedTime(bool value) async {
    await _setSetting(SettingKeys.notifyAtFixedTime, value);
    if (!value) return;

    final NotificationService notifications = ref.read(
      notificationServiceProvider,
    );
    if (await notifications.canScheduleExactly()) return;
    await notifications.requestExactScheduling();

    if (!mounted) return;
    if (!await notifications.canScheduleExactly() && mounted) {
      _toast(
        'Without the alarms & reminders permission your notification can '
        'arrive up to about 20 minutes late.',
      );
    }
  }

  Future<void> _pickTime(NotificationSchedule schedule) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: schedule.hour, minute: schedule.minute),
      helpText: 'Deliver notifications at',
    );
    if (picked == null) return;

    await ref
        .read(localStoreProvider)
        .putSetting(
          SettingKeys.notifyTimeOfDay,
          picked.hour * 60 + picked.minute,
        );
    if (!mounted) return;
    setState(() {});

    // The change only reaches Android on the next detected rotation, which
    // could be tomorrow. Say so rather than letting it look broken tonight.
    _toast('Your next shop notification will arrive at ${picked.format(context)}.');
  }

  Future<void> _runSyncNow() async {
    setState(() => _busy = true);
    try {
      final ShopSyncOutcome outcome = await ShopSyncService(
        ref.read(appDependenciesProvider),
      ).sync();
      ref.invalidate(shopControllerProvider);
      if (!mounted) return;
      _toast(
        outcome.shopChanged
            ? 'Your shop rotated — notifications sent.'
            : 'Your shop is already up to date.',
      );
    } on Object catch (e) {
      if (mounted) _toast('Check failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sends the user to the system screen that lifts battery optimisation.
  ///
  /// The app cannot grant this itself, and it is the one setting that can stop
  /// the nightly check without anything in the app looking wrong.
  Future<void> _openBatterySettings() async {
    const BatteryOptimisation power = BatteryOptimisation();
    if (await power.isExempt() == true) {
      if (mounted) _toast('Already unrestricted — background checks can run.');
      return;
    }
    if (!await power.openSettings() && mounted) {
      _toast('Could not open the settings screen on this device.');
    }
  }

  Future<void> _runDiagnostics() async {
    setState(() => _busy = true);
    try {
      final List<DiagnosticResult> results = await ConnectionDiagnostics(
        ref.read(appDependenciesProvider),
      ).run();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (BuildContext _) => _DiagnosticsDialog(results: results),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendTestNotification() async {
    final NotificationService notifications = ref.read(
      notificationServiceProvider,
    );
    final bool granted = await notifications.requestPermission();
    if (!granted) {
      if (mounted) {
        _toast('Notifications are blocked for DailyValo in system settings.');
      }
      return;
    }
    // The real offers, so the test shows exactly what the morning would.
    final Shop? shop = ref.read(shopControllerProvider).valueOrNull;
    final List<String> labels =
        shop?.dailyOffers
            .map((ShopOffer o) => o.skin.notificationLabel)
            .toList(growable: false) ??
        const <String>[];

    final tz.TZDateTime at = tz.TZDateTime.now(
      tz.local,
    ).add(const Duration(minutes: 1));

    try {
      await notifications.scheduleTest(at: at, offerLabels: labels);
    } on Object catch (e) {
      if (mounted) _toast('Could not queue the test: $e');
      return;
    }

    if (!mounted) return;
    // Says to close the app because that is the interesting part: a digest that
    // only arrives while you are looking at the app proves nothing about a
    // phone asleep at 09:30.
    _toast(
      'Queued for ${TimeOfDay.fromDateTime(at).format(context)}. '
      'Close the app to see it arrive the way it will in the morning.',
    );
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    await ref.read(appModeProvider.notifier).signOut();
    if (mounted) Navigator.of(context).pop();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Shows one line per probed endpoint, so an unhealthy account can be reported
/// precisely rather than as "it doesn't work".
class _DiagnosticsDialog extends StatelessWidget {
  const _DiagnosticsDialog({required this.results});

  final List<DiagnosticResult> results;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Diagnostics'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final DiagnosticResult r in results)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      r.ok
                          ? Icons.check_circle_outline_rounded
                          : Icons.cancel_outlined,
                      size: 17,
                      color: r.ok ? AppColors.success : AppColors.danger,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            r.label,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(color: AppColors.textPrimary),
                          ),
                          if (r.detail != null)
                            Text(
                              r.detail!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
