import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/utils/logger.dart';

/// Plays one of Riot's skin preview clips.
///
/// The clips are short, silent-ish MP4s on `valorant.dyn.riotcdn.net` — they
/// are what actually shows you what a VFX or finisher level does, which a still
/// image cannot. They loop, because they are two to five seconds long and a
/// single play is over before you have focused on it.
class SkinVideoSheet extends StatefulWidget {
  const SkinVideoSheet({
    required this.videoUrl,
    required this.title,
    super.key,
    this.subtitle,
  });

  final String videoUrl;

  /// e.g. `Level 3` or `Variant 2 Blue`.
  final String title;

  /// e.g. `Animation` or the skin name.
  final String? subtitle;

  static Future<void> open(
    BuildContext context, {
    required String videoUrl,
    required String title,
    String? subtitle,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.backgroundElevated,
      builder: (BuildContext _) => SkinVideoSheet(
        videoUrl: videoUrl,
        title: title,
        subtitle: subtitle,
      ),
    );
  }

  @override
  State<SkinVideoSheet> createState() => _SkinVideoSheetState();
}

class _SkinVideoSheetState extends State<SkinVideoSheet> {
  VideoPlayerController? _controller;
  bool _initialising = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // Releasing the platform texture matters here: leaking an ExoPlayer keeps
    // decoding in the background and holds a wakelock.
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final Uri? uri = Uri.tryParse(widget.videoUrl);
    if (uri == null) {
      setState(() {
        _initialising = false;
        _error = 'That preview link is malformed.';
      });
      return;
    }

    final VideoPlayerController controller = VideoPlayerController.networkUrl(
      uri,
    );
    _controller = controller;

    try {
      await controller.initialize();
      if (!mounted) return;
      await controller.setLooping(true);
      await controller.play();
      setState(() => _initialising = false);
    } on Object catch (e, st) {
      Log.e('Video', 'Could not load ${widget.videoUrl}', e, st);
      if (!mounted) return;
      setState(() {
        _initialising = false;
        _error = 'This preview could not be loaded. It may not be available '
            'for this skin yet.';
      });
    }
  }

  void _togglePlayback() {
    final VideoPlayerController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      controller.value.isPlaying ? controller.pause() : controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        widget.title.toUpperCase(),
                        style: text.labelSmall,
                      ),
                      if (widget.subtitle != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleLarge,
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  color: AppColors.textSecondary,
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: AppRadius.card,
              child: ColoredBox(
                color: Colors.black,
                child: AspectRatio(
                  aspectRatio: _aspectRatio,
                  child: _buildBody(),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _buildFooter(text),
          ],
        ),
      ),
    );
  }

  /// Riot's clips are 16:9, but fall back to the real ratio once known so a
  /// non-standard one is not letterboxed wrongly.
  double get _aspectRatio {
    final VideoPlayerController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) return 16 / 9;
    final double ratio = controller.value.aspectRatio;
    return ratio > 0 ? ratio : 16 / 9;
  }

  Widget _buildBody() {
    if (_initialising) {
      return const Center(
        child: SizedBox(
          height: 26,
          width: 26,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      );
    }

    final String? error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.videocam_off_outlined,
                color: AppColors.textTertiary,
                size: 28,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                error,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    final VideoPlayerController controller = _controller!;
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        VideoPlayer(controller),
        // Tap anywhere to pause — no chrome over the artwork while playing.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _togglePlayback,
            child: AnimatedOpacity(
              opacity: controller.value.isPlaying ? 0 : 1,
              duration: const Duration(milliseconds: 150),
              child: Container(
                color: Colors.black38,
                child: const Center(
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 56,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: VideoProgressIndicator(
            controller,
            allowScrubbing: true,
            colors: const VideoProgressColors(
              playedColor: AppColors.accent,
              bufferedColor: AppColors.borderStrong,
              backgroundColor: AppColors.surfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(TextTheme text) {
    if (_error != null) {
      return Text(
        'Preview clips are hosted by Riot and are not available for every '
        'skin or level.',
        textAlign: TextAlign.center,
        style: text.bodySmall,
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const Icon(Icons.repeat_rounded, size: 14, color: AppColors.textTertiary),
        const SizedBox(width: 6),
        Text('Looping · tap the video to pause', style: text.bodySmall),
      ],
    );
  }
}
