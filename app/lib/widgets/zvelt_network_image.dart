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
import '../config/api_config.dart';
import '../services/auth_service.dart';
import '../theme/zvelt_tokens.dart';

/// Conventional decode widths per surface (logical dp × pixelRatio).
class ZveltImageCacheWidth {
  static const int storyThumb = 200; // 64dp bubble @ 3x
  static const int galleryGrid = 360; // 120dp @ 3x
  static const int feedFull = 1080; // typical phone width
  static const int avatarSmall = 144; // 48dp @ 3x
}

class ZveltNetworkImage extends StatefulWidget {
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
  State<ZveltNetworkImage> createState() => _ZveltNetworkImageState();
}

class _ZveltNetworkImageState extends State<ZveltNetworkImage> {
  Future<String?>? _tokenFuture;

  bool get _isProtectedMedia {
    final raw = widget.url?.trim() ?? '';
    if (raw.startsWith('/uploads/')) return true;
    final uri = Uri.tryParse(raw);
    final api = Uri.tryParse(apiBaseUrl);
    return uri != null &&
        api != null &&
        uri.host == api.host &&
        uri.port == api.port &&
        uri.path.startsWith('/uploads/');
  }

  @override
  void initState() {
    super.initState();
    if (_isProtectedMedia) _tokenFuture = AuthService().getAccessToken();
  }

  @override
  void didUpdateWidget(covariant ZveltNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url && _isProtectedMedia) {
      _tokenFuture = AuthService().getAccessToken();
    }
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.url;
    if (raw == null || raw.isEmpty) {
      return _defaultError(context);
    }
    if (_isProtectedMedia) {
      final tokenFuture = _tokenFuture ??= AuthService().getAccessToken();
      return FutureBuilder<String?>(
        future: tokenFuture,
        builder: (context, snapshot) {
          final token = snapshot.data;
          if (snapshot.connectionState != ConnectionState.done) {
            return (widget.placeholder ?? _defaultPlaceholder).call(context);
          }
          if (token == null || token.isEmpty) {
            return (widget.errorWidget ?? _defaultError).call(context);
          }
          return Image.network(
            raw,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            cacheWidth: widget.cacheWidth,
            cacheHeight: widget.cacheHeight,
            gaplessPlayback: true,
            headers: {
              'Authorization': 'Bearer $token',
              'Cache-Control': 'no-store',
            },
            loadingBuilder: (ctx, child, progress) => progress == null
                ? child
                : (widget.placeholder ?? _defaultPlaceholder).call(ctx),
            errorBuilder: (ctx, _, __) =>
                (widget.errorWidget ?? _defaultError).call(ctx),
          );
        },
      );
    }
    return CachedNetworkImage(
      imageUrl: raw,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      memCacheWidth: widget.cacheWidth,
      memCacheHeight: widget.cacheHeight,
      maxWidthDiskCache: widget.cacheWidth,
      maxHeightDiskCache: widget.cacheHeight,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (ctx, _) =>
          (widget.placeholder ?? _defaultPlaceholder).call(ctx),
      errorWidget: (ctx, _, __) =>
          (widget.errorWidget ?? _defaultError).call(ctx),
    );
  }
}

Widget _defaultPlaceholder(BuildContext _) =>
    Container(color: ZveltTokens.surface);

Widget _defaultError(BuildContext _) => Container(
      color: ZveltTokens.surface2,
      alignment: Alignment.center,
      child: Icon(AppIcons.picture, color: ZveltTokens.text2, size: 28),
    );
