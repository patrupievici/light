import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import '../models/game_xp_models.dart';
import '../theme/zvelt_tokens.dart';
import 'z/z_card.dart';

/// Level + progress toward next threshold (Zvelt V2 design).
class GameXpBarCard extends StatelessWidget {
  const GameXpBarCard({super.key, required this.snapshot});

  final GameXpSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final String semanticsLabel = snapshot.xpForNextLevel > 0
        ? 'Level ${snapshot.level}, ${snapshot.levelName}. '
            '${snapshot.xpIntoLevel} of ${snapshot.xpForNextLevel} XP toward next level. '
            '${snapshot.totalXp} total XP.'
        : 'Level ${snapshot.level}, ${snapshot.levelName}. '
            'Max level. ${snapshot.totalXp} total XP.';
    return ZCard(
      padding: const EdgeInsets.all(ZveltTokens.s4),
      child: Semantics(
        container: true,
        label: semanticsLabel,
        value: snapshot.xpForNextLevel > 0
            ? '${snapshot.xpIntoLevel} of ${snapshot.xpForNextLevel} XP'
            : 'Max level',
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(ZveltTokens.s2),
                    decoration: BoxDecoration(
                      color: ZveltTokens.brandTint,
                      borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                    ),
                    child: const Icon(AppIcons.bolt, color: ZveltTokens.brand, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      snapshot.levelName,
                      style: ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 15),
                    ),
                  ),
                  Text(
                    'Lv ${snapshot.level}',
                    style: ZType.num_.copyWith(
                      color: ZveltTokens.text2,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: snapshot.progressFraction,
                  minHeight: 6,
                  backgroundColor: ZveltTokens.surface2,
                  color: ZveltTokens.brand,
                ),
              ),
              const SizedBox(height: ZveltTokens.s2),
              Text(
              snapshot.xpForNextLevel > 0
                  ? '${snapshot.xpIntoLevel} / ${snapshot.xpForNextLevel} XP · ${snapshot.totalXp} total'
                  : 'Max level · ${snapshot.totalXp} XP total',
              style: ZType.monoXS.copyWith(
                color: ZveltTokens.text2,
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}
