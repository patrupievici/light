import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/zvelt_tokens.dart';

/// Bottom pill: **4 destinations + a center Quick-Start action** —
/// Home · Train · ⚡ · Feed · Nutrition.
///
/// The four [items] are the real tabs (two left, two right of center). The raised
/// brand circle in the middle is NOT a tab — it fires [onCenterTap] (Quick Start
/// workout). Profile is no longer a destination: it opens from the Home avatar.
class ZveltMainNavBar extends StatelessWidget {
  const ZveltMainNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    required this.onCenterTap,
    this.centerIcon = AppIcons.bolt,
    this.centerLabel = 'Start',
  });

  static const double pillHeight = 72;
  static const double navVerticalInset = 8;
  static const double _fabSize = 54;

  static double reservedBottomHeight(BuildContext context) =>
      pillHeight + navVerticalInset * 2 + MediaQuery.paddingOf(context).bottom;

  /// Active tab, 0..3 (Home, Train, Feed, Nutrition).
  final int currentIndex;

  /// Tab tapped, 0..3.
  final ValueChanged<int> onTap;

  /// Exactly four destinations: [Home, Train, Feed, Nutrition].
  final List<ZveltNavItem> items;

  /// Center Quick-Start action.
  final VoidCallback onCenterTap;
  final IconData centerIcon;
  final String centerLabel;

  ShapeBorder _pillShape() => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(pillHeight / 2),
        side: BorderSide(color: ZveltTokens.border),
      );

  @override
  Widget build(BuildContext context) {
    assert(items.length == 4, 'ZveltMainNavBar expects 4 destinations + a center action.');
    final bottom = MediaQuery.paddingOf(context).bottom;
    final stackHeight = pillHeight + navVerticalInset * 2 + bottom;

    return Material(
      color: Colors.transparent,
      child: SizedBox(
        height: stackHeight,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              left: ZveltTokens.s4,
              right: ZveltTokens.s4,
              bottom: navVerticalInset + bottom,
              height: pillHeight,
              child: Material(
                color: ZveltTokens.surface,
                elevation: 0,
                shadowColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                shape: _pillShape(),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  decoration: const BoxDecoration(
                    boxShadow: ZveltTokens.shadowFloat,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(child: _navCell(context, 0)),
                      Expanded(child: _navCell(context, 1)),
                      Expanded(child: _centerCell(context)),
                      Expanded(child: _navCell(context, 2)),
                      Expanded(child: _navCell(context, 3)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _centerCell(BuildContext context) {
    return Semantics(
      button: true,
      label: '$centerLabel — quick start',
      child: Center(
        child: InkWell(
          onTap: onCenterTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: _fabSize,
            height: _fabSize,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: ZveltTokens.gradBrand,
              boxShadow: ZveltTokens.shadowFloat,
            ),
            child: const Icon(AppIcons.bolt, color: ZveltTokens.onBrand, size: 24),
          ),
        ),
      ),
    );
  }

  Widget _navCell(BuildContext context, int i) {
    final item = items[i];
    final selected = i == currentIndex;
    return Semantics(
      button: true,
      selected: selected,
      label: '${item.label} tab',
      child: InkWell(
        onTap: () => onTap(i),
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? ZveltTokens.brandTint : Colors.transparent,
            borderRadius: BorderRadius.circular(ZveltTokens.rLg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              item.iconBuilder?.call(selected) ??
                  Icon(
                    item.icon,
                    size: 21,
                    color: selected ? ZveltTokens.brand : ZveltTokens.text3,
                  ),
              const SizedBox(height: 3),
              Text(
                item.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: ZveltTokens.fontPrimary,
                  fontSize: 11,
                  height: 1.05,
                  letterSpacing: -0.1,
                  color: selected ? ZveltTokens.brand : ZveltTokens.text3,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
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
