import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../errors/app_exception.dart';

/// Shown when a tab has nothing to display — and, crucially, says what to do
/// about it rather than just "No data".
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              height: 72,
              width: 72,
              decoration: const BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 30, color: AppColors.textTertiary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Renders a failure in terms the user can act on.
///
/// Anything that reached the UI has already been mapped to an [AppException],
/// so the message is human-readable by construction; the raw error is only
/// shown for the unmapped case.
class ErrorState extends StatelessWidget {
  const ErrorState({required this.error, super.key, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final (String title, String message, IconData icon) = _describe(error);

    return EmptyState(
      icon: icon,
      title: title,
      message: message,
      action: onRetry == null
          ? null
          : OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
    );
  }

  static (String, String, IconData) _describe(Object error) {
    if (error is NetworkException) {
      return ('Offline', error.message, Icons.wifi_off_rounded);
    }
    if (error is NotAuthenticatedException) {
      return ('Not signed in', error.message, Icons.lock_outline_rounded);
    }
    if (error is AuthException) {
      return ('Session expired', error.message, Icons.key_off_rounded);
    }
    if (error is AppException) {
      return (
        'Something went wrong',
        error.message,
        Icons.error_outline_rounded,
      );
    }
    return (
      'Something went wrong',
      'An unexpected error occurred. Pull down to retry.',
      Icons.error_outline_rounded,
    );
  }
}

/// Full-tab loading indicator.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(
            height: 26,
            width: 26,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          if (message != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Text(message!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// A wide-tracked uppercase heading with an optional trailing widget.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    super.key,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title.toUpperCase(), style: text.labelSmall),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(subtitle!, style: text.titleLarge),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}
