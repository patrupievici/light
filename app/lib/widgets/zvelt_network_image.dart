// Drop-in replacement for Image.network that disk-caches via
// cached_network_image. Default Flutter ImageCache is RAM-only and gets
// flushed under memory pressure — every screen revisit re-downloads on
// cellular. This wrapper stores decoded bytes on disk keyed by URL hash;
// survives app restarts.
//
// Memory cache hints (memCacheWidth / maxWidthDiskCache) honor target size so
// we don't decode 4000px JPEGs to render 120dp thumbnails (OOM on low-RAM
// Androids). Pass `cacheWidth` = logical px × pixelRatio (or one of the
// constants in [ZveltImageCacheWidth]).

import 'package:cached_network_image/cached_network_image.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import '../theme/zvelt_tokens.dart';

/// Conventional decode widths per surface (logical dp × pixelRatio).
class ZveltImageCacheWidth {
  static const int storyThumb = 200; // 64dp bubble @ 3x
  static const int galleryGrid = 360; // 120dp @ 3x
  static const int feedFull = 1080; // typical phone width
  static const int avatarSmall = 144; // 48dp @ 3x
}

class ZveltNetworkImage extends StatelessWidget {
  const ZveltNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.cacheHeight,
    this.placeholder,
    this.errorWidget,
  });

  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? cacheWidth;
  final int? cacheHeight;
  final WidgetBuilder? placeholder;
  final WidgetBuilder? errorWidget;

  @override
  Widget build(BuildContext context) {
    final raw = url;
    if (raw == null || raw.isEmpty) {
      return _defaultError(context);
    }
    return CachedNetworkImage(
      imageUrl: raw,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      maxWidthDiskCache: cacheWidth,
      maxHeightDiskCache: cacheHeight,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (ctx, _) =>
          (placeholder ?? _defaultPlaceholder).call(ctx),
      errorWidget: (ctx, _, __) =>
          (errorWidget ?? _defaultError).call(ctx),
    );
  }

  static Widget _defaultPlaceholder(BuildContext _) =>
      Container(color: ZveltTokens.surface);

  static Widget _defaultError(BuildContext _) => Container(
        color: ZveltTokens.surface2,
        alignment: Alignment.center,
        child: Icon(AppIcons.picture,
            color: ZveltTokens.text2, size: 28),
      );
}
