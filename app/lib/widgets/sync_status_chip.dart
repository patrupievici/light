import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../theme/zvelt_tokens.dart';

/// Lightweight sync indicator. When [pendingCount] is 0 it reads "Synced"; with
/// queued mutations it reads "Pending N" in the warn color.
///
/// Pass [onRetry] to make the chip tappable — a small trailing retry glyph is
/// shown and the whole chip becomes a tap target that triggers the callback
/// (e.g. force-flush the offline set queue). Without [onRetry] the chip is a
/// plain, non-interactive status pill exactly as before.
class SyncStatusChip extends StatelessWidget {
  const SyncStatusChip({super.key, this.pendingCount = 0, this.onRetry});

  final int pendingCount;

  /// Optional tap handler. When non-null the chip is interactive and renders a
  /// trailing retry glyph after the label.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final synced = pendingCount <= 0;
    final color = synced ? ZveltTokens.success : ZveltTokens.warn;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            synced ? AppIcons.cloud_check : AppIcons.cloud_upload,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            synced ? 'Synced' : 'Pending $pendingCount',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 6),
            Icon(AppIcons.arrows_repeat, size: 13, color: color),
          ],
        ],
      ),
    );

    if (onRetry == null) return chip;

    return Semantics(
      button: true,
      label: 'Retry sync, $pendingCount pending',
      child: Tooltip(
        message: 'Retry sync',
        child: InkWell(
          onTap: onRetry,
          borderRadius: BorderRadius.circular(ZveltTokens.rPill),
          child: chip,
        ),
      ),
    );
  }
}
