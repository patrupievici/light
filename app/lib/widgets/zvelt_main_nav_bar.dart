import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/zvelt_tokens.dart';
import 'z/z_pressable.dart';

/// Bottom pill: 4 destinations plus a center Quick-Start action.
///
/// The center action is not a tab. It launches the workout quick-start flow.
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

  /// Exactly four destinations: Home, Train, Feed, Nutrition.
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
    assert(
      items.length == 4,
      'ZveltMainNavBar expects 4 destinations plus a center action.',
    );
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
    return Center(
      child: ZPressable(
        onTap: onCenterTap,
        semanticLabel: '$centerLabel quick start',
        pressedScale: 0.94,
        child: Container(
          width: _fabSize,
          height: _fabSize,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: ZveltTokens.gradBrand,
            boxShadow: ZveltTokens.shadowFloat,
          ),
          child: Icon(centerIcon, color: ZveltTokens.onBrand, size: 24),
        ),
      ),
    );
  }

  Widget _navCell(BuildContext context, int i) {
    final item = items[i];
    final selected = i == currentIndex;
    return ZPressable(
      onTap: () => onTap(i),
      selected: selected,
      semanticLabel: '${item.label} tab',
      pressedScale: 0.96,
      child: AnimatedContainer(
        duration: ZMotion.standard,
        curve: ZMotion.emphasized,
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
                AnimatedScale(
                  scale: selected ? 1.06 : 1,
                  duration: ZMotion.standard,
                  curve: ZMotion.emphasized,
                  child: Icon(
                    item.icon,
                    size: 21,
                    color: selected ? ZveltTokens.brand : ZveltTokens.text3,
                  ),
                ),
            const SizedBox(height: 3),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  item.label,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontSize: 11,
                    height: 1.05,
                    letterSpacing: 0,
                    color: selected ? ZveltTokens.brand : ZveltTokens.text3,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
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
