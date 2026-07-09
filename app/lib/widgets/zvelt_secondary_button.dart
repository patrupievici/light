import 'package:flutter/material.dart';
import '../theme/zvelt_tokens.dart';
import 'z/z_pressable.dart';

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
      child: ZPressable(
        onTap: enabled ? onTap : null,
        semanticLabel: label,
        pressedScale: 0.975,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: ZveltTokens.surface2,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: ZveltTokens.border),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
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
