import 'package:flutter/material.dart';

import '../theme/zvelt_tokens.dart';

/// Bottom pill with **5 tabs**: Home · Train · Food · Feed · Profile.
///
/// Per the "light" redesign brief (§3, §20) the app moved from a 4-tab +
/// centered Play FAB layout to five equal destinations. Start Workout is no
/// longer a floating action — it lives as the dominant hero on Home and as the
/// primary action on Train (brief §7: "cel mai vizibil element din aplicatie").
class ZveltMainNavBar extends StatelessWidget {
  const ZveltMainNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  static const double pillHeight = 72;
  static const double navVerticalInset = 8;

  static double reservedBottomHeight(BuildContext context) =>
      pillHeight + navVerticalInset * 2 + MediaQuery.paddingOf(context).bottom;

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<ZveltNavItem> items;

  ShapeBorder _pillShape() => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(pillHeight / 2),
        side: BorderSide(color: ZveltTokens.border),
      );

  @override
  Widget build(BuildContext context) {
    assert(items.length == 5, 'ZveltMainNavBar expects 5 items.');
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
                      for (var i = 0; i < items.length; i++)
                        Expanded(child: _navCell(context, i)),
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
