import 'package:flutter/material.dart';

import '../theme/zvelt_tokens.dart';
import '../utils/display_name.dart';
import 'zvelt_network_image.dart';

/// Standardized avatar size tokens — Wave 19 audit (#F1) found seven different
/// pixel sizes (32/36/38/40/42/44/56/64) used across feed / notifications /
/// comments / circle / race / DM. This enum collapses them to five tokens
/// covering every legitimate use case in the app.
enum AvatarSize {
  /// 28dp — compact rows (notifications cell, conversations list).
  xs,

  /// 36dp — comment rows, friend rows in dense lists.
  sm,

  /// 44dp — feed posts main author avatar; also meets min touch target
  /// (44pt iOS / 48dp Android).
  md,

  /// 56dp — matched tribe cards, race participants, story bubbles.
  lg,

  /// 96dp — large profile hero / full-bleed avatars.
  xl,
}

extension AvatarSizeExt on AvatarSize {
  double get px => switch (this) {
        AvatarSize.xs => 28,
        AvatarSize.sm => 36,
        AvatarSize.md => 44,
        AvatarSize.lg => 56,
        AvatarSize.xl => 96,
      };

  /// Initials font size scaled to bubble diameter (~38% of width).
  double get initialsFontSize => switch (this) {
        AvatarSize.xs => 11,
        AvatarSize.sm => 13,
        AvatarSize.md => 15,
        AvatarSize.lg => 18,
        AvatarSize.xl => 30,
      };
}

/// Single avatar widget for every social/profile surface. Renders:
/// 1. `imageUrl` via [ZveltNetworkImage] (with sized disk cache) when supplied
/// 2. otherwise a brand-gradient circle with 1–2 letter initials derived from
///    [resolveDisplayName] (Wave 20a — never exposes raw userId).
///
/// Optional `ring` (orange brand glow) marks "active" avatars (story rings,
/// matched tribes). Optional `online` dot renders a small green badge in the
/// bottom-right.
class ZveltAvatar extends StatelessWidget {
  const ZveltAvatar({
    super.key,
    required this.size,
    this.imageUrl,
    this.displayName,
    this.username,
    this.userId,
    this.ring = false,
    this.online = false,
    this.onTap,
  });

  final AvatarSize size;
  final String? imageUrl;
  final String? displayName;
  final String? username;
  final String? userId;
  final bool ring;
  final bool online;
  final VoidCallback? onTap;

  String get _label => resolveDisplayName(
        displayName: displayName,
        username: username,
        userId: userId,
      );

  String get _initials {
    final cleaned = _label.startsWith('@') ? _label.substring(1) : _label;
    if (cleaned.isEmpty) return '?';
    if (cleaned.length >= 2) return cleaned.substring(0, 2).toUpperCase();
    return cleaned.toUpperCase();
  }

  /// Deterministic two-tone gradient derived from userId hash so the same user
  /// always gets the same fallback bubble color (helps recognition in lists).
  LinearGradient _gradientFromId() {
    if (userId == null || userId!.isEmpty) return ZveltTokens.gradBrand;
    final h = userId!.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0xFFFFFF);
    final hue = (h % 360).toDouble();
    final c1 = HSLColor.fromAHSL(1, hue, 0.55, 0.45).toColor();
    final c2 = HSLColor.fromAHSL(1, (hue + 40) % 360, 0.60, 0.55).toColor();
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [c1, c2],
    );
  }

  @override
  Widget build(BuildContext context) {
    final px = size.px;
    final pr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3.0;
    final cacheW = (px * pr).round();

    Widget body;
    if (imageUrl != null && imageUrl!.trim().isNotEmpty) {
      body = ClipOval(
        child: ZveltNetworkImage(
          url: imageUrl,
          width: px,
          height: px,
          cacheWidth: cacheW,
          cacheHeight: cacheW,
        ),
      );
    } else {
      body = Container(
        width: px,
        height: px,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: _gradientFromId(),
        ),
        alignment: Alignment.center,
        child: Text(
          _initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: size.initialsFontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      );
    }

    Widget framed = body;
    if (ring) {
      framed = Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: ZveltTokens.gradBrand,
        ),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ZveltTokens.bg,
          ),
          child: body,
        ),
      );
    }

    if (online) {
      final dot = (px * 0.27).clamp(8.0, 16.0);
      framed = Stack(
        clipBehavior: Clip.none,
        children: [
          framed,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ZveltTokens.success,
                border: Border.all(color: ZveltTokens.bg, width: 1.5),
              ),
            ),
          ),
        ],
      );
    }

    if (onTap == null) return framed;
    return Semantics(
      label: 'Avatar of $_label',
      button: true,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: framed,
      ),
    );
  }
}
