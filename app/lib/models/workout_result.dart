import 'package:latlong2/latlong.dart';

enum ActivityType { workout, run, walk, cycle, swim, hike }

extension ActivityTypeExt on ActivityType {
  String get label => switch (this) {
        ActivityType.workout => 'Workout',
        ActivityType.run => 'Run',
        ActivityType.walk => 'Walk',
        ActivityType.cycle => 'Cycle',
        ActivityType.swim => 'Swim',
        ActivityType.hike => 'Hike',
      };

  bool get isGps =>
      this == ActivityType.run ||
      this == ActivityType.walk ||
      this == ActivityType.cycle ||
      this == ActivityType.hike;

  bool get hasPace =>
      this == ActivityType.run ||
      this == ActivityType.walk ||
      this == ActivityType.hike;

  bool get hasSpeed => this == ActivityType.cycle;

  bool get hasElevation =>
      this == ActivityType.run ||
      this == ActivityType.walk ||
      this == ActivityType.cycle ||
      this == ActivityType.hike;

  bool get hasSplits =>
      this == ActivityType.run ||
      this == ActivityType.walk ||
      this == ActivityType.hike;
}

class SplitData {
  final int km;
  final Duration time;
  final double paceSecsPerKm;
  final double elevGainM;

  const SplitData({
    required this.km,
    required this.time,
    required this.paceSecsPerKm,
    required this.elevGainM,
  });
}

class WeatherData {
  final double tempC;
  final String condition;
  final int humidity;
  final double windKmh;
  final String iconCode;

  const WeatherData({
    required this.tempC,
    required this.condition,
    required this.humidity,
    required this.windKmh,
    required this.iconCode,
  });
}

class WorkoutResult {
  final String id;
  final ActivityType activityType;
  final DateTime startedAt;
  final DateTime endedAt;

  // GPS
  final List<LatLng> routePoints;
  final double distanceM;
  final double elevGainM;
  final double elevLossM;

  // Time
  final Duration elapsed;
  final Duration movingTime;

  // Pace / speed
  final double avgPaceSecsPerKm;
  final double avgSpeedKmh;
  final double maxSpeedKmh;

  // Fitness
  final int calories;
  final int? avgHeartRate;
  final int? maxHeartRate;
  final int? steps;
  final double? cadenceRpm;

  // Gamification
  final int xpEarned;
  final String? rankTierUnlocked;

  // Enrichment
  final List<SplitData> splits;
  final WeatherData? weather;

  // AI
  final String? aiInsight;
  final List<String> aiTags;

  // User
  final String userId;
  final String? displayName;
  final String? avatarUrl;

  const WorkoutResult({
    required this.id,
    required this.activityType,
    required this.startedAt,
    required this.endedAt,
    required this.routePoints,
    required this.distanceM,
    required this.elevGainM,
    required this.elevLossM,
    required this.elapsed,
    required this.movingTime,
    required this.avgPaceSecsPerKm,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    required this.calories,
    required this.xpEarned,
    required this.userId,
    this.avgHeartRate,
    this.maxHeartRate,
    this.steps,
    this.cadenceRpm,
    this.rankTierUnlocked,
    this.splits = const [],
    this.weather,
    this.aiInsight,
    this.aiTags = const [],
    this.displayName,
    this.avatarUrl,
  });

  String get distanceLabel {
    if (distanceM >= 1000) {
      return '${(distanceM / 1000).toStringAsFixed(2)} km';
    }
    return '${distanceM.toStringAsFixed(0)} m';
  }

  String get durationLabel {
    final h = elapsed.inHours;
    final m = elapsed.inMinutes % 60;
    final s = elapsed.inSeconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get paceLabel {
    if (avgPaceSecsPerKm <= 0) return '--:--';
    final m = (avgPaceSecsPerKm ~/ 60);
    final s = (avgPaceSecsPerKm % 60).toInt();
    return '$m:${s.toString().padLeft(2, '0')} /km';
  }

  String get speedLabel => '${avgSpeedKmh.toStringAsFixed(1)} km/h';
}
