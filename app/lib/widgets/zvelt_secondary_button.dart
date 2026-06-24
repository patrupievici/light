import 'package:flutter/material.dart';
import '../theme/zvelt_tokens.dart';

/// Secondary CTA button (outline/ghost style) aligned with Zvelt visuals.
class ZveltSecondaryButton extends StatelessWidget {
  const ZveltSecondaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    const fg = ZveltTokens.brand;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: 56,
          decoration: BoxDecoration(
            color: ZveltTokens.surface2,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: ZveltTokens.border),
          ),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(32),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: fg),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: fg,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
