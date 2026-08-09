import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/utils/widget_capture.dart';
import 'share_card.dart';

/// Turns a shop section into an image and opens the system share sheet.
///
/// The share sheet rather than a fixed target: which app people send a shop to
/// is entirely personal — WhatsApp, Discord, a group chat, their own gallery —
/// and Android already knows their list.
class ShareButton extends StatefulWidget {
  const ShareButton({
    required this.title,
    required this.entries,
    super.key,
    this.shareText,
  });

  /// Only used to name the file — the card itself carries no title, so the
  /// image is all skins and no chrome.
  final String title;

  final List<ShareEntry> entries;

  /// Accompanies the image where the target app supports it.
  final String? shareText;

  @override
  State<ShareButton> createState() => _ShareButtonState();
}

class _ShareButtonState extends State<ShareButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _busy || widget.entries.isEmpty ? null : _share,
      tooltip: 'Share as image',
      color: AppColors.textSecondary,
      icon: _busy
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.ios_share_rounded, size: 20),
    );
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final Uint8List png = await WidgetCapture.toPng(
        context: context,
        imageUrls: widget.entries
            .map((ShareEntry e) => e.artwork ?? '')
            .toList(growable: false),
        build: (BuildContext _) => ShareCard(entries: widget.entries),
      );

      final Directory dir = await getTemporaryDirectory();
      final String stamp = DateTime.now().toIso8601String().split('T').first;
      final File file = File(
        '${dir.path}/dailyvalo-${_slug(widget.title)}-$stamp.png',
      );
      await file.writeAsBytes(png);

      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: 'image/png')],
          text: widget.shareText,
        ),
      );
    } on Object catch (e, st) {
      Log.e('Share', 'Could not build the share image', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(content: Text('Could not create the image.')),
          );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _slug(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
}
