/// Mirrors `gameXpPayload` / GET `/v1/me` `gameXp` (gym_rpg_app.html level curve).
class GameXpSnapshot {
  const GameXpSnapshot({
    required this.totalXp,
    required this.level,
    required this.levelName,
    required this.xpIntoLevel,
    required this.xpForNextLevel,
    required this.progressFraction,
  });

  final int totalXp;
  final int level;
  final String levelName;
  final int xpIntoLevel;
  final int xpForNextLevel;
  final double progressFraction;

  static GameXpSnapshot fromJson(Map<String, dynamic> j) {
    double toDouble(dynamic v) {
      if (v is num) return v.toDouble();
      return double.parse(v.toString());
    }

    int toInt(dynamic v) {
      if (v is num) return v.toInt();
      return int.parse(v.toString());
    }

    return GameXpSnapshot(
      totalXp: toInt(j['totalXp']),
      level: toInt(j['level']),
      levelName: j['levelName'] as String? ?? 'Recruit',
      xpIntoLevel: toInt(j['xpIntoLevel']),
      xpForNextLevel: toInt(j['xpForNextLevel']),
      progressFraction: toDouble(j['progressFraction']).clamp(0.0, 1.0),
    );
  }
}
