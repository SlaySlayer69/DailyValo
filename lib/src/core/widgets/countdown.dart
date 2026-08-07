import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../utils/formatters.dart';

/// A self-ticking countdown to [target].
///
/// The timer lives inside this widget rather than in a provider on purpose: a
/// second-resolution clock in app state would rebuild the entire shop grid
/// sixty times a minute. Here, only the four characters that changed repaint.
class Countdown extends StatefulWidget {
  const Countdown({
    required this.target,
    super.key,
    this.style,
    this.builder,
    this.onElapsed,
  });

  final DateTime target;
  final TextStyle? style;

  /// Custom rendering of the remaining time. Defaults to `13h 24m 09s`.
  final Widget Function(BuildContext context, Duration remaining)? builder;

  /// Fired once, when the countdown reaches zero — the cue to refetch.
  final VoidCallback? onElapsed;

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  Timer? _timer;
  late Duration _remaining = _compute();
  bool _notified = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant Countdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) {
      _notified = false;
      _remaining = _compute();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Duration _compute() {
    final Duration d = widget.target.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  void _tick() {
    final Duration next = _compute();
    if (next == _remaining) return;
    if (mounted) setState(() => _remaining = next);

    if (next == Duration.zero && !_notified) {
      _notified = true;
      widget.onElapsed?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget Function(BuildContext, Duration)? builder = widget.builder;
    if (builder != null) return builder(context, _remaining);

    return Text(
      Formatters.duration(_remaining),
      style: widget.style ?? Theme.of(context).textTheme.titleMedium,
    );
  }
}

/// The pill shown next to "Daily Shop" and on the Night Market header.
class CountdownPill extends StatelessWidget {
  const CountdownPill({
    required this.target,
    required this.label,
    super.key,
    this.icon = Icons.schedule_rounded,
    this.accent = AppColors.accent,
    this.onElapsed,
  });

  final DateTime target;

  /// e.g. `Resets in`.
  final String label;

  final IconData icon;
  final Color accent;
  final VoidCallback? onElapsed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.sm)),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(width: AppSpacing.sm),
          Countdown(
            target: target,
            onElapsed: onElapsed,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.textPrimary,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
