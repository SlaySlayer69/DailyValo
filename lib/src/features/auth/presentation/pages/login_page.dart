import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/constants/riot_constants.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/network/webview_cookie_reader.dart';
import '../../data/datasources/riot_auth_api.dart';
import '../../data/models/riot_session.dart';
import 'riot_login_webview_page.dart';

/// Sign-in entry point.
///
/// There is no password field here by design: credentials are typed into
/// Riot's own hosted login page inside a WebView, so this app never sees them.
/// That is both the safer arrangement and the only one that works — the legacy
/// password endpoint cannot complete a sign-in for accounts protected by Riot's
/// push confirmation or a captcha.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const _Wordmark(),
                  const SizedBox(height: AppSpacing.xxl),

                  Text('Sign in', style: text.headlineMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'You will sign in on Riot\'s own page. Two-factor codes '
                    'and Riot Mobile confirmations are handled there, exactly '
                    'as they are on the website.',
                    style: text.bodyMedium,
                  ),

                  if (_error != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.lg),
                    _ErrorBanner(message: _error!),
                  ],

                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    onPressed: _busy ? null : _signIn,
                    icon: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.login_rounded, size: 20),
                    label: Text(
                      _busy ? 'Finishing sign-in…' : 'Sign in with Riot',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _enterDemoMode,
                    icon: const Icon(Icons.play_circle_outline, size: 19),
                    label: const Text('Explore in demo mode'),
                  ),

                  const SizedBox(height: AppSpacing.xl),
                  const _PrivacyNote(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    setState(() => _error = null);

    final WebLoginTokens? tokens = await RiotLoginWebViewPage.show(context);
    // Null means the user closed the WebView; that is not an error.
    if (tokens == null || !mounted) return;

    setState(() => _busy = true);
    try {
      // The durable half of the session. Read *before* anything else touches
      // the jar, and flushed so a process death right now does not lose it.
      const WebViewCookieReader cookies = WebViewCookieReader();
      await cookies.flush();
      final Map<String, String> jar = await cookies.cookiesFor(
        RiotConstants.authBase,
      );

      final RiotAuthApi api = ref.read(authApiProvider);
      final RiotSession session = await api.completeWebLogin(
        accessToken: tokens.accessToken,
        idToken: tokens.idToken,
        expiresInSeconds: tokens.expiresIn,
        ssidCookie: jar[RiotConstants.sessionCookieName],
      );

      await ref.read(sessionManagerProvider).adopt(session);
      await ref.read(appModeProvider.notifier).onSignedIn();
      // The mode change swaps the root widget out; nothing left to do.
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enterDemoMode() async {
    setState(() => _busy = true);
    await ref.read(appModeProvider.notifier).enterDemoMode();
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          height: 62,
          width: 62,
          decoration: BoxDecoration(
            color: AppColors.accentSubtle,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: AppColors.accent.withValues(alpha: 0.45),
            ),
          ),
          child: const Icon(
            Icons.storefront_rounded,
            color: AppColors.accent,
            size: 30,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'DAILYVALO',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            letterSpacing: 4,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'SHOP · NIGHT MARKET · COLLECTION',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.sm)),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.danger,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.sm)),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.shield_outlined,
            size: 18,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Your password is typed on Riot\'s own page and is never seen by '
              'DailyValo. Only a session cookie is kept, in the Android '
              'Keystore, so your shop can refresh; signing out deletes it. '
              'This is an unofficial app and is not endorsed by Riot Games.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
