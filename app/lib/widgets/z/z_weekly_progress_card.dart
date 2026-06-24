import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../../theme/zvelt_tokens.dart';
import 'z_card.dart';
import 'z_eyebrow.dart';

/// 7-day vertical-bar strip showing sessions completed vs goal for the week.
/// Mirrors `WeeklyProgressCard` from screens-train.jsx.
///
/// Visual: M T W T F S S labels under thin vertical pills (filled brand
/// orange when training happened that day, surface3 grey when skipped),
/// big "done / goal" number on the right.
class ZWeeklyProgressCard extends StatelessWidget {
  const ZWeeklyProgressCard({
    super.key,
    required this.done,
    required this.goal,
    required this.filled,
    this.eyebrow = 'Weekly progress',
    this.scopeLabel = 'This week',
    this.onScopeTap,
  });

  /// Sessions completed this week.
  final int done;
  /// Weekly target (typically `trainingProfile.daysPerWeek`).
  final int goal;
  /// 7-element list, true = trained that day. Order: Mon → Sun.
  /// Lists with != 7 entries are padded/truncated silently to keep the
  /// row visually intact.
  final List<bool> filled;
  final String eyebrow;
  /// Right-side dropdown label (default "This week"). Tap fires
  /// [onScopeTap] — typically opens a scope picker (week/month/season).
  final String scopeLabel;
  final VoidCallback? onScopeTap;

  List<bool> get _safeFilled {
    if (filled.length == 7) return filled;
    final out = List<bool>.from(filled);
    while (out.length < 7) {
      out.add(false);
    }
    return out.sublist(0, 7);
  }

  @override
  Widget build(BuildContext context) {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final cells = _safeFilled;

    return ZCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ZEyebrow(eyebrow),
              GestureDetector(
                onTap: onScopeTap,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      scopeLabel,
                      style: TextStyle(
                        fontFamily: ZveltTokens.fontPrimary,
                        fontSize: 12,
                        color: ZveltTokens.text3,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (onScopeTap != null) ...[
                      const SizedBox(width: 3),
                      Icon(
                        AppIcons.angle_small_down,
                        size: 14,
                        color: ZveltTokens.text3,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < 7; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 40,
                              decoration: BoxDecoration(
                                color: cells[i] ? ZveltTokens.brand : ZveltTokens.surface3,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              days[i],
                              style: TextStyle(
                                fontFamily: ZveltTokens.fontMono,
                                fontSize: 11,
                                color: ZveltTokens.text3,
                                fontWeight: FontWeight.w500,
                                height: 1.2,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$done',
                          style: ZType.stat.copyWith(
                            fontSize: 24,
                            color: ZveltTokens.text,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '/ $goal',
                          style: TextStyle(
                            fontFamily: ZveltTokens.fontPrimary,
                            fontSize: 13,
                            color: ZveltTokens.text3,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Workouts',
                      style: TextStyle(
                        fontFamily: ZveltTokens.fontPrimary,
                        fontSize: 11,
                        color: ZveltTokens.text3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
