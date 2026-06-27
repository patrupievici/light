import 'package:flutter/material.dart';

import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';
import 'z_card.dart';

/// A small header card that reveals a chart on tap (the user's "charts in small
/// cards that expand when tapped"). Collapsed = just the title row; expanded =
/// the [child] chart animated open below. The child keeps its own card chrome,
/// so this stays a thin header strip rather than nesting cards.
class ZCollapsibleChartCard extends StatefulWidget {
  const ZCollapsibleChartCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.subtitle,
    this.initialExpanded = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;
  final bool initialExpanded;

  @override
  State<ZCollapsibleChartCard> createState() => _ZCollapsibleChartCardState();
}

class _ZCollapsibleChartCardState extends State<ZCollapsibleChartCard> {
  late bool _expanded = widget.initialExpanded;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ZCard(
          onTap: () => setState(() => _expanded = !_expanded),
          padding: const EdgeInsets.symmetric(
              horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
          child: Row(
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: ZveltTokens.brand, size: 18),
                const SizedBox(width: ZveltTokens.s3),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: ZType.bodyM.copyWith(
                            color: ZveltTokens.text, fontWeight: FontWeight.w600)),
                    if (widget.subtitle != null)
                      Text(widget.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ZType.bodyS.copyWith(color: ZveltTokens.text3, fontSize: 12)),
                  ],
                ),
              ),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(AppIcons.angle_small_down, color: ZveltTokens.text3, size: 20),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: ZveltTokens.cardGap),
                  child: widget.child,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
