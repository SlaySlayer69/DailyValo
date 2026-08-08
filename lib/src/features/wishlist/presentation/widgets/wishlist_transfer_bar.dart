import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/providers.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/utils/logger.dart';
import '../../data/models/wishlist_entry.dart';
import '../../data/wishlist_transfer.dart';

/// Export and import, side by side.
///
/// Sits at the bottom of a populated list and in the middle of an empty one,
/// because on an empty wishlist importing is the most useful thing on screen —
/// a fresh install after a reinstall is exactly when someone needs it.
class WishlistTransferBar extends ConsumerStatefulWidget {
  const WishlistTransferBar({super.key});

  @override
  ConsumerState<WishlistTransferBar> createState() =>
      _WishlistTransferBarState();
}

class _WishlistTransferBarState extends ConsumerState<WishlistTransferBar> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final int count = ref.watch(wishlistControllerProvider).length;

    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy || count == 0 ? null : _export,
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            label: const Text('Export'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 46),
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.file_download_outlined, size: 18),
            label: const Text('Import'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 46),
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _export() async {
    final List<WishlistEntry> entries = ref.read(wishlistControllerProvider);
    if (entries.isEmpty) return;

    setState(() => _busy = true);
    try {
      final WishlistTransfer transfer = WishlistTransfer(
        entries: entries,
        exportedAt: DateTime.now(),
      );

      // Written to the cache directory and handed to the share sheet rather
      // than saved somewhere fixed: the user picks where it goes — Drive, a
      // chat, their own files — and Android cleans up after us.
      final Directory dir = await getTemporaryDirectory();
      final File file = File('${dir.path}/${transfer.fileName}');
      await file.writeAsString(transfer.encode());

      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: 'application/json')],
          subject: 'DailyValo wishlist',
          text: '${entries.length} skins from my DailyValo wishlist.',
        ),
      );
    } on Object catch (e, st) {
      Log.e('Wishlist', 'Export failed', e, st);
      _toast('Could not export your wishlist: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      // Deliberately unfiltered: an export that came back from Drive or a chat
      // app often arrives as application/octet-stream, and a JSON-only filter
      // would grey out the very file the user is looking for.
      final XFile? picked = await openFile();
      if (picked == null) return;

      // Read through XFile rather than a path: a content:// URI from Drive has
      // no filesystem path to open.
      final String source = await picked.readAsString();

      final WishlistTransfer transfer = WishlistTransfer.decode(source);
      final ImportResult result = await ref
          .read(wishlistControllerProvider.notifier)
          .import(transfer.entries);

      if (mounted) _toast(result.summary);
    } on ParseException catch (e) {
      // Already phrased for a person — pass it through rather than wrapping it
      // in "an error occurred".
      if (mounted) _toast(e.message);
    } on Object catch (e, st) {
      Log.e('Wishlist', 'Import failed', e, st);
      if (mounted) _toast('Could not read that file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
