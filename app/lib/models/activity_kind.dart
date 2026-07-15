import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

/// Tip de activitate afișat în calendar (gym din API; restul logate local).
enum ActivityKind {
  gym,
  run,
  swim,
  cycle,
  walk,
  other;

  String get id => name;

  String get label {
    switch (this) {
      case ActivityKind.gym:
        return 'Gym / strength';
      case ActivityKind.run:
        return 'Running / jogging';
      case ActivityKind.swim:
        return 'Swimming';
      case ActivityKind.cycle:
        return 'Cycling';
      case ActivityKind.walk:
        return 'Walk / hike';
      case ActivityKind.other:
        return 'Other';
    }
  }

  IconData get icon {
    switch (this) {
      case ActivityKind.gym:
        return AppIcons.gym;
      case ActivityKind.run:
        return AppIcons.running;
      case ActivityKind.swim:
        return AppIcons.swimmer;
      case ActivityKind.cycle:
        return AppIcons.bike;
      case ActivityKind.walk:
        return AppIcons.running;
      case ActivityKind.other:
        return AppIcons.menu_dots;
    }
  }

  Color get color {
    switch (this) {
      case ActivityKind.gym:
        return const Color(0xFFE8922A);
      case ActivityKind.run:
        return const Color(0xFF3DD68C);
      case ActivityKind.swim:
        return const Color(0xFF4DA3FF);
      case ActivityKind.cycle:
        return const Color(0xFFB388FF);
      case ActivityKind.walk:
        return const Color(0xFFFFB74D);
      case ActivityKind.other:
        return const Color(0xFF7A8A8F);
    }
  }

  static ActivityKind? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    switch (raw.trim().toLowerCase()) {
      case 'ride':
      case 'bike':
      case 'cycling':
        return ActivityKind.cycle;
      case 'running':
        return ActivityKind.run;
      case 'walking':
      case 'hike':
        return ActivityKind.walk;
      case 'swimming':
        return ActivityKind.swim;
    }
    for (final e in ActivityKind.values) {
      if (e.id == raw.trim().toLowerCase()) return e;
    }
    return null;
  }

  static ActivityKind parse(String raw) {
    return tryParse(raw) ?? ActivityKind.other;
  }
}
