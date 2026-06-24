import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/health_service.dart';
import '../../services/offline_sync_coordinator.dart';
import '../../services/profile_service.dart';
import '../../services/push_messaging_service.dart';
import '../../services/settings_store.dart';
import '../../theme/zvelt_tokens.dart';
import 'settings_kit.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _master = true;
  final Map<String, bool> _values = {
    SettingsKeys.notifWorkout: true,
    SettingsKeys.notifSocial: true,
    SettingsKeys.notifChallenges: true,
    SettingsKeys.notifRecovery: true,
    SettingsKeys.notifNutrition: false,
    SettingsKeys.notifCoach: true,
  };

  static const _items = [
    (
      key: SettingsKeys.notifWorkout,
      title: 'Workout reminders',
      sub: 'Planned sessions and streak reminders',
      icon: AppIcons.gym,
      tint: SettingsTint.orange
    ),
    (
      key: SettingsKeys.notifSocial,
      title: 'Social',
      sub: 'Likes, comments and new followers',
      icon: AppIcons.users,
      tint: SettingsTint.blue
    ),
    (
      key: SettingsKeys.notifChallenges,
      title: 'Challenges & races',
      sub: 'Race starts, progress and results',
      icon: AppIcons.trophy,
      tint: SettingsTint.amber
    ),
    (
      key: SettingsKeys.notifRecovery,
      title: 'Recovery alerts',
      sub: 'Readiness and overtraining signals',
      icon: AppIcons.heart,
      tint: SettingsTint.red
    ),
    (
      key: SettingsKeys.notifNutrition,
      title: 'Nutrition',
      sub: 'Meal, hydration and target reminders',
      icon: AppIcons.restaurant,
      tint: SettingsTint.green
    ),
    (
      key: SettingsKeys.notifCoach,
      title: 'AI Coach tips',
      sub: 'Relevant training guidance',
      icon: AppIcons.sparkles,
      tint: SettingsTint.violet
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _master = prefs.getBool(SettingsKeys.notifMaster) ?? true;
      for (final item in _items) {
        _values[item.key] = prefs.getBool(item.key) ?? _values[item.key]!;
      }
    });
  }

  Future<void> _setMaster(bool value) async {
    setState(() => _master = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsKeys.notifMaster, value);
    if (value) {
      await PushMessagingService.instance.startAfterLogin();
    }
  }

  Future<void> _toggle(String key, bool value) async {
    setState(() => _values[key] = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsModalShell(
      title: 'Notifications',
      closeIcon: AppIcons.cross_small,
      eyebrow: 'PRIVACY',
      children: [
        SettingsCard(
          children: [
            SettingsSwitchRow(
              icon: AppIcons.bell_ring,
              tint: SettingsTint.red,
              title: 'All notifications',
              subtitle: _master
                  ? 'Receive the alerts you choose below'
                  : 'Everything is paused',
              value: _master,
              onChanged: _setMaster,
            ),
          ],
        ),
        const SettingsSectionTitle('Categories'),
        SettingsCard(
          children: [
            for (final item in _items)
              SettingsSwitchRow(
                icon: item.icon,
                tint: item.tint,
                title: item.title,
                subtitle: item.sub,
                value: _values[item.key]!,
                enabled: _master,
                onChanged: (value) => _toggle(item.key, value),
              ),
          ],
        ),
        const SettingsSectionTitle('Quiet hours'),
        const SettingsCard(
          children: [
            SettingsRow(
              icon: AppIcons.moon,
              tint: SettingsTint.violet,
              title: 'Do not disturb',
              subtitle: '22:00 - 07:00, no alerts overnight',
              trailingText: 'Active',
              chevron: false,
            ),
          ],
        ),
      ],
    );
  }
}

class CustomizationScreen extends StatefulWidget {
  const CustomizationScreen({super.key});

  @override
  State<CustomizationScreen> createState() => _CustomizationScreenState();
}

class _CustomizationScreenState extends State<CustomizationScreen> {
  static const _accents = [
    (name: 'Ember', color: Color(0xFFFF7A2F)),
    (name: 'Crimson', color: Color(0xFFE5484D)),
    (name: 'Sky', color: Color(0xFF3A9FE8)),
    (name: 'Violet', color: Color(0xFF7657D6)),
    (name: 'Mint', color: Color(0xFF1E9460)),
    (name: 'Carbon', color: Color(0xFF303431)),
  ];

  int _accent = 0xFFFF7A2F;
  String _start = 'home';
  bool _compact = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _accent = prefs.getInt(SettingsKeys.accent) ?? 0xFFFF7A2F;
      _start = prefs.getString(SettingsKeys.startScreen) ?? 'home';
      _compact = prefs.getBool(SettingsKeys.compact) ?? false;
      _reduceMotion = prefs.getBool(SettingsKeys.reduceMotion) ?? false;
    });
  }

  Future<void> _setInt(String key, int value) async {
    setState(() => _accent = value);
    await AppPreferencesNotifier.setAccent(value);
  }

  Future<void> _setString(String key, String value) async {
    setState(() => _start = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _setBool(String key, bool value) async {
    setState(() {
      if (key == SettingsKeys.compact) _compact = value;
      if (key == SettingsKeys.reduceMotion) _reduceMotion = value;
    });
    if (key == SettingsKeys.compact) {
      await AppPreferencesNotifier.setCompact(value);
    } else if (key == SettingsKeys.reduceMotion) {
      await AppPreferencesNotifier.setReduceMotion(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsModalShell(
      title: 'Customization',
      eyebrow: 'GENERAL',
      children: [
        const SettingsEyebrow('ACCENT COLOR'),
        const SizedBox(height: ZveltTokens.s3),
        SettingsCard(
          divided: false,
          children: [
            Padding(
              padding: const EdgeInsets.all(ZveltTokens.s4),
              child: Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final accent in _accents)
                    Semantics(
                      button: true,
                      selected: _accent == accent.color.toARGB32(),
                      label: accent.name,
                      child: GestureDetector(
                        onTap: () => _setInt(
                            SettingsKeys.accent, accent.color.toARGB32()),
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: accent.color,
                            shape: BoxShape.circle,
                            border: Border.all(color: ZveltTokens.surface, width: 3),
                            boxShadow: _accent == accent.color.toARGB32()
                                ? [
                                    BoxShadow(
                                        color:
                                            accent.color.withValues(alpha: .35),
                                        blurRadius: 0,
                                        spreadRadius: 4)
                                  ]
                                : null,
                          ),
                          child: _accent == accent.color.toARGB32()
                              ? const Icon(AppIcons.check,
                                  color: Colors.white)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SettingsSectionTitle('Start screen'),
        SettingsCard(
          divided: false,
          children: [
            Padding(
              padding: const EdgeInsets.all(ZveltTokens.s4),
              child: SettingsSegmented<String>(
                value: _start,
                options: const [
                  (value: 'home', label: 'Home'),
                  (value: 'train', label: 'Train'),
                  (value: 'food', label: 'Food'),
                  (value: 'feed', label: 'Feed'),
                ],
                onChanged: (value) =>
                    _setString(SettingsKeys.startScreen, value),
              ),
            ),
          ],
        ),
        const SettingsSectionTitle('Layout & motion'),
        SettingsCard(
          children: [
            SettingsSwitchRow(
              icon: AppIcons.list,
              tint: SettingsTint.amber,
              title: 'Compact cards',
              subtitle: 'Tighter spacing, more on screen',
              value: _compact,
              onChanged: (value) => _setBool(SettingsKeys.compact, value),
            ),
            SettingsSwitchRow(
              icon: AppIcons.cross_circle,
              tint: SettingsTint.violet,
              title: 'Reduce motion',
              subtitle: 'Minimise animations and transitions',
              value: _reduceMotion,
              onChanged: (value) => _setBool(SettingsKeys.reduceMotion, value),
            ),
          ],
        ),
        const SizedBox(height: ZveltTokens.s4),
        const SettingsNoteCard(
            'Start-screen changes apply on the next app launch. Accessibility motion settings are kept on this device.'),
      ],
    );
  }
}

class UnitsScreen extends StatefulWidget {
  const UnitsScreen({super.key});

  @override
  State<UnitsScreen> createState() => _UnitsScreenState();
}

class _UnitsScreenState extends State<UnitsScreen> {
  final _profile = ProfileService();
  String _system = UnitsNotifier.system.value;
  String _energy = 'kcal';
  String _distance = 'km';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _system = prefs.getString(SettingsKeys.unitSystem) ??
          UnitsNotifier.system.value;
      _energy = prefs.getString(SettingsKeys.energyUnit) ?? 'kcal';
      _distance = prefs.getString(SettingsKeys.distanceUnit) ??
          (_system == 'imperial' ? 'mi' : 'km');
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _profile.updateProfile(unitSystem: _system);
      await UnitsNotifier.set(_system);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(SettingsKeys.energyUnit, _energy);
      await prefs.setString(SettingsKeys.distanceUnit, _distance);
      if (!mounted) return;
      settingsSnack(context, 'Units updated across Zvelt.');
      Navigator.of(context).pop();
    } on ProfileUpdateException catch (e) {
      if (mounted) settingsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsModalShell(
      title: 'Units',
      closeIcon: AppIcons.cross_small,
      eyebrow: 'APP',
      footer: SettingsActionButton(
        label: _saving ? 'Saving...' : 'Save units',
        icon: AppIcons.check,
        onTap: _saving ? null : _save,
      ),
      children: [
        SettingsCard(
          divided: false,
          children: [
            Padding(
              padding: const EdgeInsets.all(ZveltTokens.s4),
              child: SettingsSegmented<String>(
                value: _system,
                options: const [
                  (value: 'metric', label: 'Metric'),
                  (value: 'imperial', label: 'Imperial'),
                ],
                onChanged: (value) => setState(() {
                  _system = value;
                  _distance = value == 'imperial' ? 'mi' : 'km';
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: ZveltTokens.cardGap),
        Row(
          children: [
            Expanded(
                child: _PreviewMetric(
                    label: 'Weight',
                    value: _system == 'metric' ? '80 kg' : '176 lb')),
            const SizedBox(width: ZveltTokens.s2),
            Expanded(
                child: _PreviewMetric(
                    label: 'Height',
                    value: _system == 'metric' ? '180 cm' : '5 ft 11')),
            const SizedBox(width: ZveltTokens.s2),
            Expanded(
                child: _PreviewMetric(
                    label: 'Distance',
                    value: _system == 'metric' ? '5.0 km' : '3.1 mi')),
          ],
        ),
        const SettingsSectionTitle('Energy'),
        SettingsCard(
          divided: false,
          children: [
            Padding(
              padding: const EdgeInsets.all(ZveltTokens.s4),
              child: SettingsSegmented<String>(
                value: _energy,
                options: const [
                  (value: 'kcal', label: 'kcal'),
                  (value: 'kj', label: 'kJ')
                ],
                onChanged: (value) => setState(() => _energy = value),
              ),
            ),
          ],
        ),
        const SettingsSectionTitle('Running & cardio'),
        SettingsCard(
          divided: false,
          children: [
            Padding(
              padding: const EdgeInsets.all(ZveltTokens.s4),
              child: SettingsSegmented<String>(
                value: _distance,
                options: const [
                  (value: 'km', label: 'Kilometres'),
                  (value: 'mi', label: 'Miles')
                ],
                onChanged: (value) => setState(() => _distance = value),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class ProfileVisibilityScreen extends StatefulWidget {
  const ProfileVisibilityScreen({super.key});

  @override
  State<ProfileVisibilityScreen> createState() =>
      _ProfileVisibilityScreenState();
}

class _ProfileVisibilityScreenState extends State<ProfileVisibilityScreen> {
  final _profile = ProfileService();
  String _visibility = 'friends';
  bool _showStats = true;
  bool _showActivity = true;
  bool _discoverable = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait(
        [_profile.getMe(refresh: true), SharedPreferences.getInstance()]);
    final me = results[0] as Map<String, dynamic>?;
    final prefs = results[1] as SharedPreferences;
    final p = me?['profile'] as Map<String, dynamic>?;
    if (!mounted) return;
    setState(() {
      _visibility = p?['privacyDefault']?.toString() ?? 'friends';
      _showStats = p?['showBodyStats'] as bool? ??
          prefs.getBool(SettingsKeys.showStats) ??
          true;
      _showActivity = p?['showActivityFeed'] as bool? ??
          prefs.getBool(SettingsKeys.showActivity) ??
          true;
      _discoverable = p?['discoveryOptIn'] as bool? ??
          prefs.getBool(SettingsKeys.discoverable) ??
          false;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _profile.updateProfile(privacyDefault: _visibility);
      await _profile.updateSettings({
        'showBodyStats': _showStats,
        'showActivityFeed': _showActivity,
        'discoveryOptIn': _discoverable,
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SettingsKeys.showStats, _showStats);
      await prefs.setBool(SettingsKeys.showActivity, _showActivity);
      await prefs.setBool(SettingsKeys.discoverable, _discoverable);
      if (!mounted) return;
      settingsSnack(context, 'Privacy settings saved.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) settingsSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsModalShell(
      title: 'Profile visibility',
      closeIcon: AppIcons.cross_small,
      eyebrow: 'PRIVACY',
      footer: SettingsActionButton(
        label: _saving ? 'Saving...' : 'Save privacy',
        icon: AppIcons.shield_check,
        onTap: _loading || _saving ? null : _save,
      ),
      children: _loading
          ? const [
              SizedBox(height: 220),
              Center(
                  child: CircularProgressIndicator(color: ZveltTokens.brand)),
            ]
          : [
              SettingsCard(
                children: [
                  SettingsRadioRow(
                    title: 'Public',
                    subtitle:
                        'Anyone on Zvelt can see your profile and activity',
                    selected: _visibility == 'public',
                    onTap: () => setState(() => _visibility = 'public'),
                  ),
                  SettingsRadioRow(
                    title: 'Friends only',
                    subtitle: 'Only people you follow back',
                    selected: _visibility == 'friends',
                    onTap: () => setState(() => _visibility = 'friends'),
                  ),
                  SettingsRadioRow(
                    title: 'Private',
                    subtitle: 'Hidden - nothing is shared to the feed',
                    selected: _visibility == 'private',
                    onTap: () => setState(() => _visibility = 'private'),
                  ),
                ],
              ),
              const SettingsSectionTitle('Profile details'),
              SettingsCard(
                children: [
                  SettingsSwitchRow(
                    icon: AppIcons.balance_scale_left,
                    tint: SettingsTint.blue,
                    title: 'Show body stats',
                    value: _showStats,
                    onChanged: (value) => setState(() => _showStats = value),
                  ),
                  SettingsSwitchRow(
                    icon: AppIcons.list,
                    tint: SettingsTint.orange,
                    title: 'Show activity feed',
                    value: _showActivity,
                    onChanged: (value) => setState(() => _showActivity = value),
                  ),
                  SettingsSwitchRow(
                    icon: AppIcons.search,
                    tint: SettingsTint.green,
                    title: 'Discoverable in search',
                    value: _discoverable,
                    onChanged: (value) => setState(() => _discoverable = value),
                  ),
                ],
              ),
            ],
    );
  }
}

class CloudSyncScreen extends StatefulWidget {
  const CloudSyncScreen({super.key});

  @override
  State<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends State<CloudSyncScreen> {
  bool _auto = true;
  bool _cellular = false;
  bool _syncing = false;
  DateTime? _lastSync;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(SettingsKeys.cloudLastSync);
    if (!mounted) return;
    setState(() {
      _auto = prefs.getBool(SettingsKeys.cloudAuto) ?? true;
      _cellular = prefs.getBool(SettingsKeys.cloudCellular) ?? false;
      _lastSync = raw == null ? null : DateTime.tryParse(raw);
    });
  }

  Future<void> _set(String key, bool value) async {
    setState(() {
      if (key == SettingsKeys.cloudAuto) _auto = value;
      if (key == SettingsKeys.cloudCellular) _cellular = value;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      await OfflineSyncCoordinator.instance.refreshPending(flush: true);
      try {
        await HealthService.instance.incrementalSync();
      } catch (_) {}
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(SettingsKeys.cloudLastSync, now.toIso8601String());
      if (!mounted) return;
      setState(() => _lastSync = now);
      settingsSnack(context, 'Synced to cloud.');
    } catch (_) {
      if (mounted) {
        settingsSnack(context, 'Sync could not finish. Try again online.',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String get _lastLabel {
    final value = _lastSync;
    if (value == null) return 'Not synced on this device yet';
    final minutes = DateTime.now().difference(value).inMinutes;
    if (minutes < 1) return 'Synced just now';
    if (minutes < 60) return 'Synced $minutes min ago';
    return 'Synced ${value.day}/${value.month} at ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return SettingsModalShell(
      title: 'Cloud sync',
      eyebrow: 'DATA',
      children: [
        SettingsNoteCard(
          _syncing
              ? 'Syncing workouts, health imports and offline changes...'
              : 'All up to date. $_lastLabel.',
          icon: _syncing ? AppIcons.refresh : AppIcons.cloud_check,
          tint: SettingsTint.blue,
        ),
        const SizedBox(height: ZveltTokens.cardGap),
        SettingsActionButton(
          label: _syncing ? 'Syncing...' : 'Sync now',
          icon: AppIcons.refresh,
          onTap: _syncing ? null : _syncNow,
        ),
        const SettingsSectionTitle('Sync preferences'),
        SettingsCard(
          children: [
            SettingsSwitchRow(
              icon: AppIcons.refresh,
              tint: SettingsTint.green,
              title: 'Auto-sync',
              subtitle: 'Keep data current in the background',
              value: _auto,
              onChanged: (value) => _set(SettingsKeys.cloudAuto, value),
            ),
            SettingsSwitchRow(
              icon: AppIcons.chart_histogram,
              tint: SettingsTint.blue,
              title: 'Sync on cellular',
              subtitle: 'May use your mobile data allowance',
              value: _cellular,
              onChanged: (value) => _set(SettingsKeys.cloudCellular, value),
            ),
          ],
        ),
        const SettingsSectionTitle('Cloud storage'),
        SettingsCard(
          divided: false,
          children: [
            Padding(
              padding: const EdgeInsets.all(ZveltTokens.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('1.8 GB of 5 GB used',
                      style: ZType.bodyM.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: ZveltTokens.s3),
                  LinearProgressIndicator(
                    value: .36,
                    minHeight: 7,
                    color: ZveltTokens.recovery,
                    backgroundColor: ZveltTokens.surface3,
                    borderRadius: const BorderRadius.all(Radius.circular(99)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PreviewMetric extends StatelessWidget {
  const _PreviewMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
          color: ZveltTokens.surface,
          borderRadius: BorderRadius.circular(ZveltTokens.rMd)),
      child: Column(
        children: [
          Text(label, style: ZType.bodyS.copyWith(color: ZveltTokens.text3)),
          const SizedBox(height: 3),
          FittedBox(
              child: Text(value, style: ZType.num_.copyWith(fontSize: 15))),
        ],
      ),
    );
  }
}
