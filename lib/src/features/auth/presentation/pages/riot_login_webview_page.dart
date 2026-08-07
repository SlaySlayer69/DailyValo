import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/constants/riot_constants.dart';
import '../../../../core/utils/logger.dart';

/// What the WebView handed back: the tokens from Riot's redirect fragment.
class WebLoginTokens {
  const WebLoginTokens({
    required this.accessToken,
    required this.idToken,
    required this.expiresIn,
  });

  final String accessToken;
  final String idToken;
  final int expiresIn;
}

/// The result of inspecting a URL the WebView navigated to.
///
/// Three outcomes have to stay distinguishable: this is not the redirect yet
/// (keep browsing), the redirect arrived with tokens (done), or Riot bounced us
/// back with an error (stop, and say so).
class RiotRedirectResult {
  const RiotRedirectResult._({this.tokens, this.error});

  final WebLoginTokens? tokens;

  /// Riot's error code, when it redirected without tokens.
  final String? error;

  bool get isSuccess => tokens != null;

  /// Parses a URL the WebView is navigating to.
  ///
  /// Returns null when [url] is not the final redirect at all — the common
  /// case, since every page of Riot's login flow passes through here.
  ///
  /// Extracted from the widget so the fragment handling is unit-testable: it
  /// is the one piece of this screen where a subtle mistake would produce a
  /// silent, unreproducible sign-in failure.
  static RiotRedirectResult? tryParse(String url) {
    if (!url.startsWith(RiotConstants.redirectUri)) return null;

    final Uri? parsed = Uri.tryParse(url);
    if (parsed == null) return null;

    final String fragment = parsed.fragment;
    if (fragment.isEmpty) return null;

    final Map<String, String> params = Uri.splitQueryString(fragment);
    final String? accessToken = params['access_token'];

    if (accessToken == null || accessToken.isEmpty) {
      return RiotRedirectResult._(error: params['error'] ?? 'unknown');
    }

    return RiotRedirectResult._(
      tokens: WebLoginTokens(
        accessToken: accessToken,
        idToken: params['id_token'] ?? '',
        expiresIn: int.tryParse(params['expires_in'] ?? '') ?? 3600,
      ),
    );
  }
}

/// Signs in against Riot's own hosted login page.
///
/// This replaced a direct username/password call to RSO, for two reasons:
///
/// 1. **It is the only flow that works.** Accounts protected by Riot's push
///    confirmation (approve-in-the-Riot-app) cannot complete the legacy
///    password endpoint — it answers `auth_failure` regardless of whether the
///    password was right. The same is true of accounts that get a captcha.
///    Riot's page handles push, captcha, e-mail codes and authenticator apps
///    natively, and we do not have to model any of them.
/// 2. **The app never sees the password.** It is typed into Riot's page inside
///    the WebView; all we ever receive is the redirect at the end.
///
/// The flow: load `/authorize`, let the user do whatever Riot asks, and watch
/// for the redirect to `playvalorant.com/opt_in#access_token=…`. That fragment
/// is the prize; the page behind it never renders.
class RiotLoginWebViewPage extends StatefulWidget {
  const RiotLoginWebViewPage({super.key});

  /// Returns the captured tokens, or null if the user backed out.
  static Future<WebLoginTokens?> show(BuildContext context) {
    return Navigator.of(context).push<WebLoginTokens>(
      MaterialPageRoute<WebLoginTokens>(
        fullscreenDialog: true,
        builder: (BuildContext _) => const RiotLoginWebViewPage(),
      ),
    );
  }

  @override
  State<RiotLoginWebViewPage> createState() => _RiotLoginWebViewPageState();
}

class _RiotLoginWebViewPageState extends State<RiotLoginWebViewPage> {
  late final WebViewController _controller;

  int _progress = 0;
  bool _captured = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.background)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onNavigationRequest: (NavigationRequest request) {
            return _handleUrl(request.url)
                ? NavigationDecision.prevent
                : NavigationDecision.navigate;
          },
          // Belt and braces: on some redirect chains the fragment only shows
          // up once the page has already begun loading.
          onPageStarted: (String url) => _handleUrl(url),
          onPageFinished: (String url) => _handleUrl(url),
          onWebResourceError: (WebResourceError error) {
            // Sub-resource failures (an ad script, a font) are noise; only a
            // failure of the main document is worth surfacing.
            if (error.isForMainFrame != true || _captured) return;
            Log.e('Login', 'WebView error: ${error.description}');
            if (mounted) {
              setState(
                () => _error = 'Riot\'s sign-in page could not be loaded. '
                    'Check your connection and try again.',
              );
            }
          },
        ),
      )
      ..loadRequest(_authorizeUri);
  }

  /// The same authorize URL the desktop client opens.
  static Uri get _authorizeUri =>
      Uri.parse(RiotConstants.authorizeUrl).replace(
        queryParameters: <String, String>{
          'redirect_uri': RiotConstants.redirectUri,
          'client_id': RiotConstants.clientId,
          'response_type': RiotConstants.responseType,
          'nonce': RiotConstants.nonce,
          'scope': RiotConstants.scope,
        },
      );

  /// Returns true when [url] was the final redirect and we are done.
  bool _handleUrl(String url) {
    if (_captured) return true;

    final RiotRedirectResult? result = RiotRedirectResult.tryParse(url);
    if (result == null) return false;

    _captured = true;

    if (!result.isSuccess) {
      Log.d('Login', 'Redirect carried no tokens (error=${result.error})');
      if (mounted) {
        setState(
          () => _error = 'Riot declined the sign-in (${result.error}). '
              'Please try again.',
        );
      }
      return true;
    }

    Log.d('Login', 'Captured tokens from the redirect');
    Navigator.of(context).pop(result.tokens);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Sign in with Riot'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: _progress >= 100 || _error != null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _progress / 100,
                  minHeight: 2,
                  backgroundColor: AppColors.surfaceVariant,
                ),
              ),
      ),
      body: _error != null
          ? _ErrorView(
              message: _error!,
              onRetry: () {
                setState(() {
                  _error = null;
                  _captured = false;
                });
                _controller.loadRequest(_authorizeUri);
              },
            )
          : WebViewWidget(controller: _controller),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.cloud_off_rounded,
              size: 34,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
