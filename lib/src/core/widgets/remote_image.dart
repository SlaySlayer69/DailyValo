import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Every image in the app goes through here.
///
/// Skin artwork is served from Riot's CDN as large transparent PNGs, so it is
/// worth caching on disk (the default for `cached_network_image`) and worth
/// having a placeholder that does not flash white on a black background.
class RemoteImage extends StatelessWidget {
  const RemoteImage({
    required this.url,
    super.key,
    this.fit = BoxFit.contain,
    this.height,
    this.width,
    this.alignment = Alignment.center,
    this.fallbackIcon = Icons.image_not_supported_outlined,
  });

  final String? url;
  final BoxFit fit;
  final double? height;
  final double? width;
  final Alignment alignment;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final String? src = url;
    if (src == null || src.isEmpty) {
      return _Placeholder(
        height: height,
        width: width,
        icon: fallbackIcon,
      );
    }

    return CachedNetworkImage(
      imageUrl: src,
      fit: fit,
      height: height,
      width: width,
      alignment: alignment,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (BuildContext _, String _) =>
          _Placeholder(height: height, width: width),
      errorWidget: (BuildContext _, String _, Object _) =>
          _Placeholder(height: height, width: width, icon: fallbackIcon),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.height, this.width, this.icon});

  final double? height;
  final double? width;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: width,
      child: Center(
        child: icon == null
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              )
            : Icon(icon, color: AppColors.textTertiary, size: 22),
      ),
    );
  }
}
