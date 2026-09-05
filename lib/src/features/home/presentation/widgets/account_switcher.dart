import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../auth/data/models/account.dart';

/// The account picker, reached from the header and from the settings sheet.
///
/// One widget for both because they are the same question asked from two
/// places, and a second copy would be the one that drifts — the header's list
/// is the one people actually use, and it has to know about "add account" the
/// same way settings does.
class AccountSwitcher extends StatelessWidget {
  const AccountSwitcher({
    required this.accounts,
    required this.active,
    super.key,
  });

  final List<Account> accounts;
  final Account active;

  /// Shows the picker and returns the account chosen, or null if dismissed or
  /// the current one was tapped.
  static Future<Account?> open(
    BuildContext context, {
    required List<Account> accounts,
    required Account active,
  }) async {
    final Account? picked = await showModalBottomSheet<Account>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.backgroundElevated,
      builder: (BuildContext _) =>
          AccountSwitcher(accounts: accounts, active: active),
    );
    if (picked == null || picked.puuid == active.puuid) return null;
    return picked;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              'Switch account',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final Account account in accounts)
            ListTile(
              onTap: () => Navigator.of(context).pop(account),
              leading: Icon(
                account.puuid == active.puuid
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: account.puuid == active.puuid ? AppColors.accent : null,
              ),
              title: Text(account.gameName),
              subtitle: Text('#${account.tagLine}'),
            ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

/// Opens the picker and performs the switch.
///
/// The switch rebuilds the whole object graph, so it is deliberately awaited
/// before anything else runs: the caller's next frame has to be the new
/// account's, not a mix of both.
Future<void> switchAccount(BuildContext context, WidgetRef ref) async {
  final Account? picked = await AccountSwitcher.open(
    context,
    accounts: ref.read(accountRegistryProvider).all(),
    active: ref.read(activeAccountProvider),
  );
  if (picked == null) return;
  await ref.read(appModeProvider.notifier).switchTo(picked);
}
