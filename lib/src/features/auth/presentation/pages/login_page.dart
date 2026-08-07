import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_exception.dart';
import '../../data/datasources/riot_auth_api.dart';
import '../../data/models/auth_result.dart';
import '../widgets/multifactor_dialog.dart';

/// Riot sign-in.
///
/// The password field is bound to a controller that is disposed with the page
/// and never copied anywhere else — the credential goes straight into the RSO
/// request and what gets persisted afterwards is the `ssid` cookie, not the
/// password. The screen says so, because a third-party app asking for game
/// credentials should be explicit about what it keeps.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

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
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const _Wordmark(),
                    const SizedBox(height: AppSpacing.xxl),

                    Text('Sign in', style: text.headlineMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Use your Riot account to load your shop, wallet and '
                      'collection.',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    TextFormField(
                      controller: _username,
                      enabled: !_busy,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Riot username',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      validator: (String? value) =>
                          (value == null || value.trim().isEmpty)
                          ? 'Enter your Riot username'
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.md),

                    TextFormField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: _obscure,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                        ),
                      ),
                      validator: (String? value) =>
                          (value == null || value.isEmpty)
                          ? 'Enter your password'
                          : null,
                    ),

                    if (_error != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.md),
                      _ErrorBanner(message: _error!),
                    ],

                    const SizedBox(height: AppSpacing.xl),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Sign in'),
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
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final RiotAuthApi api = ref.read(authApiProvider);
    try {
      AuthResult result = await api.login(
        username: _username.text.trim(),
        password: _password.text,
      );

      // Riot may interrupt with a 2FA challenge; loop until it stops asking.
      while (result is AuthMultifactorRequired) {
        if (!mounted) {
          api.abandonPendingLogin();
          return;
        }
        final String? code = await MultifactorDialog.show(
          context,
          email: result.email,
          codeLength: result.codeLength,
        );
        if (code == null) {
          api.abandonPendingLogin();
          if (mounted) setState(() => _busy = false);
          return;
        }
        result = await api.submitMultifactorCode(code);
      }

      switch (result) {
        case AuthSuccess(:final session):
          await ref.read(sessionManagerProvider).adopt(session);
          await ref.read(appModeProvider.notifier).onSignedIn();
          // The mode change swaps the root widget; nothing more to do here.
          return;
        case AuthFailure(:final message):
          if (mounted) setState(() => _error = message);
        case AuthMultifactorRequired():
          break; // unreachable — the loop above exits on any other shape
      }
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
              'Your password is sent only to Riot and is never stored on this '
              'device. DailyValo keeps a session cookie in the Android '
              'Keystore so it can refresh your shop; signing out deletes it. '
              'This is an unofficial app and is not endorsed by Riot Games.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
