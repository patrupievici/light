// Shortcuts — General sub-screen. Lets the user choose which quick-launch
// actions appear in their floating "+" menu. Six independent toggles, each
// persisted to SharedPreferences; a live header note reflects how many are
// currently active. Light theme, V2 design language (white card, colored icon
// tiles, mono eyebrow, single orange signal).
import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/settings_store.dart';
import '../../theme/zvelt_tokens.dart';
import 'settings_kit.dart';

class ShortcutsScreen extends StatefulWidget {
  const ShortcutsScreen({super.key});

  @override
  State<ShortcutsScreen> createState() => _ShortcutsScreenState();
}

/// One configurable quick-launch shortcut.
class _Shortcut {
  const _Shortcut({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tint,
    required this.defaultOn,
  });

  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color tint;
  final bool defaultOn;
}

class _ShortcutsScreenState extends State<ShortcutsScreen> {
  static const List<_Shortcut> _shortcuts = [
    _Shortcut(
      key: SettingsKeys.scEmpty,
      title: 'Empty workout',
      subtitle: 'Start a blank session',
      icon: AppIcons.plus,
      tint: SettingsTint.orange,
      defaultOn: true,
    ),
    _Shortcut(
      key: SettingsKeys.scAi,
      title: 'AI workout',
      subtitle: 'Generate from your goals',
      icon: AppIcons.sparkles,
      tint: SettingsTint.violet,
      defaultOn: true,
    ),
    _Shortcut(
      key: SettingsKeys.scRun,
      title: 'Outdoor run',
      subtitle: 'GPS-tracked cardio',
      icon: AppIcons.running,
      tint: SettingsTint.blue,
      defaultOn: true,
    ),
    _Shortcut(
      key: SettingsKeys.scMeal,
      title: 'Log a meal',
      subtitle: 'Quick nutrition entry',
      icon: AppIcons.restaurant,
      tint: SettingsTint.green,
      defaultOn: false,
    ),
    _Shortcut(
      key: SettingsKeys.scRace,
      title: 'Join a race',
      subtitle: 'Hop into a live race',
      icon: AppIcons.trophy,
      tint: SettingsTint.amber,
      defaultOn: false,
    ),
    _Shortcut(
      key: SettingsKeys.scPhoto,
      title: 'Progress photo',
      subtitle: 'Snap a body update',
      icon: AppIcons.camera,
      tint: SettingsTint.red,
      defaultOn: false,
    ),
  ];

  final Map<String, bool> _values = {
    for (final s in _shortcuts) s.key: s.defaultOn,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loaded = <String, bool>{
        for (final s in _shortcuts) s.key: prefs.getBool(s.key) ?? s.defaultOn,
      };
      if (!mounted) return;
      setState(() => _values.addAll(loaded));
    } catch (_) {
      // Best-effort: keep in-memory defaults if prefs are unavailable.
    }
  }

  Future<void> _toggle(String key, bool value) async {
    setState(() => _values[key] = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {
      // Best-effort persistence; UI state already updated.
    }
  }

  int get _activeCount => _values.values.where((v) => v).length;

  @override
  Widget build(BuildContext context) {
    final count = _activeCount;
    final note = count == 1
        ? '1 active in your quick-launch menu.'
        : '$count active in your quick-launch menu.';

    return SettingsModalShell(
      title: 'Shortcuts',
      eyebrow: 'GENERAL',
      children: [
        SettingsNoteCard(
          note,
          icon: AppIcons.bolt,
          tint: ZveltTokens.brand,
        ),
        const SizedBox(height: ZveltTokens.cardGap),
        SettingsCard(
          children: [
            for (final s in _shortcuts)
              SettingsSwitchRow(
                icon: s.icon,
                tint: s.tint,
                title: s.title,
                subtitle: s.subtitle,
                value: _values[s.key] ?? s.defaultOn,
                onChanged: (v) => _toggle(s.key, v),
              ),
          ],
        ),
      ],
    );
  }
}
