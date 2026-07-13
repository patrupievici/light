import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/zvelt_tokens.dart';
import 'z/z_pressable.dart';

/// Bottom navigation — **liquid-glass floating pill** (Claude Design handoff
/// §3). Five destinations laid out Home · Plan · (gap) · Feed · Nutrition with
/// a **raised center AI button** that floats above the bar. Icon-only.
///
/// The center action is not a tab: it opens the AI Coach.
class ZveltMainNavBar extends StatelessWidget {
  const ZveltMainNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    required this.onCenterTap,
    this.centerIcon = AppIcons.sparkles,
    this.centerLabel = 'AI Coach',
  });

  /// Floating pill height (handoff: 70).
  static const double pillHeight = 70;

  /// Inset from the screen bottom (handoff: 16).
  static const double navVerticalInset = 16;

  /// The center AI button lifts this far above the pill top.
  static const double _aiLift = 14;
  static const double _aiSize = 60;

  /// Bottom scroll inset every scroll view reserves so content clears the nav.
  static double reservedBottomHeight(BuildContext context) =>
      pillHeight + navVerticalInset + MediaQuery.paddingOf(context).bottom + 20;

  /// Active tab, 0..3 (Home, Plan, Feed, Nutrition).
  final int currentIndex;

  /// Tab tapped, 0..3.
  final ValueChanged<int> onTap;

  /// Exactly four destinations: Home, Plan, Feed, Nutrition.
  final List<ZveltNavItem> items;

  /// Center AI Coach action.
  final VoidCallback onCenterTap;
  final IconData centerIcon;
  final String centerLabel;

  @override
  Widget build(BuildContext context) {
    assert(
      items.length == 4,
      'ZveltMainNavBar expects 4 destinations plus a center AI action.',
    );
    final bottom = MediaQuery.paddingOf(context).bottom;
    final stackHeight = pillHeight + _aiLift + navVerticalInset + bottom;

    return SizedBox(
      height: stackHeight,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // Warm orange glow blob behind the bar — reads as "lit from within".
          Positioned(
            left: ZveltTokens.s5 + ZveltTokens.s2,
            right: ZveltTokens.s5 + ZveltTokens.s2,
            bottom: navVerticalInset + bottom - 6,
            height: pillHeight + 20,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, 0.9),
                    radius: 0.9,
                    colors: [
                      ZveltTokens.glowBottom,
                      ZveltTokens.glowBottom.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Glass pill.
          Positioned(
            left: ZveltTokens.s4,
            right: ZveltTokens.s4,
            bottom: navVerticalInset + bottom,
            height: pillHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(ZveltTokens.rNav),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                    sigmaX: ZveltTokens.glassBlur, sigmaY: ZveltTokens.glassBlur),
                child: Container(
                  decoration: BoxDecoration(
                    color: ZveltTokens.navBg,
                    borderRadius: BorderRadius.circular(ZveltTokens.rNav),
                    border: Border.all(color: ZveltTokens.border),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 30,
                          offset: Offset(0, 12)),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _navCell(0),
                      _navCell(1),
                      const SizedBox(width: 56), // center AI gap
                      _navCell(2),
                      _navCell(3),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Raised center AI button.
          Positioned(
            bottom: navVerticalInset + bottom + pillHeight - _aiSize + _aiLift,
            child: ZPressable(
              onTap: onCenterTap,
              semanticLabel: centerLabel,
              pressedScale: 0.96,
              child: Container(
                width: _aiSize,
                height: _aiSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: ZveltTokens.gradAccentDeep,
                  border: Border.all(color: ZveltTokens.bg, width: 3),
                  boxShadow: ZveltTokens.glowAi,
                ),
                child: const Icon(AppIcons.sparkles,
                    color: ZveltTokens.onBrand, size: 26),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navCell(int i) {
    final item = items[i];
    final selected = i == currentIndex;
    return ZPressable(
      onTap: () => onTap(i),
      selected: selected,
      semanticLabel: '${item.label} tab',
      pressedScale: 0.94,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Radial orange glow disc behind the active icon.
            if (selected)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        ZveltTokens.brand.withValues(alpha: 0.35),
                        ZveltTokens.brand.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.7],
                    ),
                  ),
                ),
              ),
            item.iconBuilder?.call(selected) ??
                Icon(
                  item.icon,
                  size: 23,
                  color: selected ? ZveltTokens.brand : ZveltTokens.text3,
                ),
          ],
        ),
      ),
    );
  }
}

class ZveltNavItem {
  const ZveltNavItem({
    required this.label,
    required this.icon,
    this.iconBuilder,
  });

  final String label;
  final IconData icon;
  final Widget Function(bool selected)? iconBuilder;
}
