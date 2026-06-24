import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../theme/zvelt_tokens.dart';
import 'zvelt_empty_state.dart';

/// Severity / cause classification — drives default icon, copy, and
/// icon color so callers don't need to hand-roll the same mapping in
/// every screen.
enum ZveltErrorTier { network, auth, server, generic }

/// Shared "something went wrong" surface used across the Feed / Social
/// area (consolidates Wave 19 audit finding #F3 — 5 different error
/// styles folded into one).
///
/// Pass a [tier] that matches the underlying cause (network drop,
/// auth/permission failure, server 5xx, or anything else). Titles
/// and messages have sensible tier-based defaults but can be
/// overridden when a screen wants more specific copy.
class ZveltErrorState extends StatelessWidget {
  const ZveltErrorState({
    super.key,
    this.tier = ZveltErrorTier.generic,
    this.title,
    this.message,
    required this.onRetry,
    this.compact = false,
    this.retryLabel = 'Try again',
  });

  final ZveltErrorTier tier;
  final String? title;
  final String? message;
  final VoidCallback onRetry;
  final bool compact;
  final String retryLabel;

  IconData get _icon {
    switch (tier) {
      case ZveltErrorTier.network:
        return AppIcons.cloud_disabled;
      case ZveltErrorTier.auth:
        return AppIcons.lock;
      case ZveltErrorTier.server:
        return AppIcons.cloud_disabled;
      case ZveltErrorTier.generic:
        return AppIcons.exclamation;
    }
  }

  Color get _iconColor {
    switch (tier) {
      case ZveltErrorTier.network:
        return ZveltTokens.strain;
      case ZveltErrorTier.auth:
      case ZveltErrorTier.server:
        return ZveltTokens.error;
      case ZveltErrorTier.generic:
        return ZveltTokens.text3;
    }
  }

  String get _defaultTitle {
    switch (tier) {
      case ZveltErrorTier.network:
        return "You're offline";
      case ZveltErrorTier.auth:
        return 'Sign in needed';
      case ZveltErrorTier.server:
        return 'Our backend hiccupped';
      case ZveltErrorTier.generic:
        return 'Something went wrong';
    }
  }

  String get _defaultMessage {
    switch (tier) {
      case ZveltErrorTier.network:
        return 'Check your connection and try again.';
      case ZveltErrorTier.auth:
        return 'Please sign in again to continue.';
      case ZveltErrorTier.server:
        return "We're looking into it. Try again in a moment.";
      case ZveltErrorTier.generic:
        return 'Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ZveltEmptyState(
      title: title ?? _defaultTitle,
      subtitle: message ?? _defaultMessage,
      icon: _icon,
      iconColor: _iconColor,
      compact: compact,
      action: FilledButton(
        onPressed: onRetry,
        style: FilledButton.styleFrom(
          backgroundColor: ZveltTokens.brand,
          foregroundColor: ZveltTokens.onBrand,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ZveltTokens.rPill),
          ),
          minimumSize: Size(0, compact ? ZveltTokens.s10 : ZveltTokens.s12),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? ZveltTokens.s5 : ZveltTokens.s6,
            vertical: compact ? ZveltTokens.s2 : ZveltTokens.s3,
          ),
        ),
        child: Text(retryLabel,
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
