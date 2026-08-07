import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';

/// Collects the 2FA code Riot mailed the user.
///
/// Returns the code, or `null` if the user backed out — which the caller must
/// treat as "abandon the pending RSO flow", not "retry", because the server
/// side of that flow is tied to a cookie that is now stale.
class MultifactorDialog extends StatefulWidget {
  const MultifactorDialog({
    required this.email,
    required this.codeLength,
    super.key,
  });

  /// Obfuscated destination Riot reports, e.g. `k****@g****.com`.
  final String email;
  final int codeLength;

  static Future<String?> show(
    BuildContext context, {
    required String email,
    required int codeLength,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext _) =>
          MultifactorDialog(email: email, codeLength: codeLength),
    );
  }

  @override
  State<MultifactorDialog> createState() => _MultifactorDialogState();
}

class _MultifactorDialogState extends State<MultifactorDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final bool complete = _controller.text.length == widget.codeLength;
      if (complete != _isComplete) setState(() => _isComplete = complete);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Two-factor code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Riot sent a ${widget.codeLength}-digit code to ${widget.email}.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: widget.codeLength,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              letterSpacing: 10,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: const InputDecoration(
              counterText: '',
              hintText: '••••••',
            ),
            onSubmitted: (String value) {
              if (value.length == widget.codeLength) _submit();
            },
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
          ),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isComplete ? _submit : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size(96, 44),
          ),
          child: const Text('Verify'),
        ),
      ],
    );
  }

  void _submit() => Navigator.of(context).pop(_controller.text);
}
