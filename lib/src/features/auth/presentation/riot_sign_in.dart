import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/riot_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/network/webview_cookie_reader.dart';
import '../../../core/storage/secure_token_store.dart';
import '../data/datasources/riot_auth_api.dart';
import '../data/models/riot_session.dart';
import 'pages/riot_login_webview_page.dart';

/// The sign-in, from the WebView to a registered account.
///
/// Shared by the login screen and by *Add account* in settings, because from
/// the app's side those are the same operation: a Riot sign-in that ends with
/// an account in the registry and the graph rebuilt around it. The only thing
/// that differs is whether one was already there.
abstract final class RiotSignIn {
  /// Runs the whole flow. Returns null on success, or a message to show.
  ///
  /// `null` is also returned when the user simply closed the WebView, which is
  /// not an error and must not put a red banner on screen.
  static Future<String?> run(BuildContext context, WidgetRef ref) async {
    // Riot's jar may still hold the last account's session. Adding a second
    // account otherwise sails straight past the login page and signs in as the
    // first one again — which looks like the button doing nothing.
    await const WebViewCookieReader().clear();
    if (!context.mounted) return null;

    final WebLoginTokens? tokens = await RiotLoginWebViewPage.show(context);
    if (tokens == null) return null;

    try {
      // The durable half of the session. Read *before* anything else touches
      // the jar, and flushed so a process death right now does not lose it.
      const WebViewCookieReader cookies = WebViewCookieReader();
      await cookies.flush();
      final Map<String, String> jar = await cookies.cookiesFor(
        RiotConstants.authBase,
      );

      // Unscoped on purpose: this sign-in may be for an account that does not
      // exist on the device yet, so there is no scoped store to use. The API
      // files the session under the puuid Riot returns.
      final RiotAuthApi api = RiotAuthApi(
        secureStore: SecureTokenStore.unscoped(),
      );
      final RiotSession session = await api.completeWebLogin(
        accessToken: tokens.accessToken,
        idToken: tokens.idToken,
        expiresInSeconds: tokens.expiresIn,
        ssidCookie: jar[RiotConstants.sessionCookieName],
      );

      // No `adopt` here. The credentials are already on disk under the new
      // account's key, and rebuilding the graph is what restores them — going
      // through the *current* graph's session manager would file them under
      // the account being replaced.
      await ref.read(appModeProvider.notifier).onSignedIn(session);
      return null;
    } on AppException catch (e) {
      return e.message;
    } on Object catch (e) {
      return 'Sign-in failed: $e';
    }
  }
}
