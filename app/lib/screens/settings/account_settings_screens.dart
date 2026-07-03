import 'dart:convert';
import 'package:zvelt_app/theme/app_icons.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/api_config.dart';
import '../../services/app_data_cache.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../services/settings_store.dart';
import '../../theme/zvelt_tokens.dart';
import '../login_screen.dart';
import 'delete_account_screen.dart';
import 'settings_kit.dart';

class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen(
      {super.key, required this.onLogout, this.onSessionChanged});

  final Future<void> Function() onLogout;

  /// Fired after signing into a different account so the app shell can clear
  /// per-user caches and remount for the new session.
  final Future<void> Function()? onSessionChanged;

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  final _auth = AuthService();
  final _profile = ProfileService();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _bio = TextEditingController();
  final _emailController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final me = await _profile.getMe(refresh: true);
    final p = me?['profile'] as Map<String, dynamic>?;
    if (!mounted) return;
    _name.text = p?['displayName']?.toString() ?? '';
    _username.text = p?['username']?.toString() ?? '';
    _bio.text = p?['bio']?.toString() ?? '';
    _emailController.text = me?['email']?.toString() ?? '';
    setState(() {
      _photoUrl = p?['photoUrl']?.toString();
      _loading = false;
    });
  }

  String get _initials {
    final parts = _name.text.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'Z';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      settingsSnack(context, 'Add your full name first.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await _profile.updateProfile(
        displayName: _name.text.trim(),
        username: _username.text.trim().isEmpty ? null : _username.text.trim(),
        bio: _bio.text.trim(),
      );
      if (mounted) settingsSnack(context, 'Account details saved.');
    } on ProfileUpdateException catch (e) {
      if (mounted) settingsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 84,
      maxWidth: 1600,
    );
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (bytes.length > 1800000) {
      if (mounted) {
        settingsSnack(context, 'Choose a photo smaller than 1.8 MB.',
            error: true);
      }
      return;
    }
    final token = await _auth.getAccessToken();
    if (token == null || !mounted) return;
    settingsSnack(context, 'Uploading photo...');
    try {
      final res = await http
          .post(
            Uri.parse('$v1Base/me/avatar'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'photoBase64': base64Encode(bytes)}),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Upload failed (${res.statusCode})');
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      await AppDataCache.instance.clearMe();
      if (!mounted) return;
      setState(() => _photoUrl = body['photoUrl']?.toString());
      settingsSnack(context, 'Profile photo updated.');
    } catch (e) {
      if (mounted) {
        settingsSnack(context, 'Could not upload the photo.', error: true);
      }
    }
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final submitted = await showSettingsSheet<bool>(
      context,
      SettingsSheet(
        title: 'Change password',
        eyebrow: 'SECURITY',
        child: Column(
          children: [
            _SettingsField(
                controller: current, label: 'Current password', obscure: true),
            const SizedBox(height: ZveltTokens.s3),
            _SettingsField(
                controller: next, label: 'New password', obscure: true),
            const SizedBox(height: ZveltTokens.s3),
            _SettingsField(
                controller: confirm, label: 'Confirm password', obscure: true),
            const SizedBox(height: ZveltTokens.s5),
            SettingsActionButton(
              label: 'Update password',
              icon: AppIcons.lock,
              onTap: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
    if (submitted != true || !mounted) return;
    if (next.text.length < 8 || next.text != confirm.text) {
      settingsSnack(
          context, 'Passwords must match and contain at least 8 characters.',
          error: true);
      return;
    }
    final token = await _auth.getAccessToken();
    if (token == null || !mounted) return;
    try {
      final res = await http
          .post(
            Uri.parse('$v1Base/auth/change-password'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'currentPassword': current.text,
              'newPassword': next.text,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        settingsSnack(context, 'Password updated.');
      } else {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>?;
        settingsSnack(context,
            decoded?['message']?.toString() ?? 'Password update failed.',
            error: true);
      }
    } catch (_) {
      if (mounted) {
        settingsSnack(context, 'Password update failed.', error: true);
      }
    } finally {
      current.dispose();
      next.dispose();
      confirm.dispose();
    }
  }

  Future<void> _logout() async {
    final ok = await settingsConfirm(
      context,
      title: 'Sign out?',
      body: 'You will need to sign in again on this device.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (!ok || !mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    await widget.onLogout();
  }

  /// Recover an account on a new device (or switch accounts). LoginScreen owns
  /// email/Google sign-in + forgot-password; on success we pop to the shell and
  /// let AuthGate clear per-user caches and remount for the new session.
  Future<void> _signInToExistingAccount() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(
          onLoggedIn: () {
            if (!mounted) return;
            Navigator.of(context).popUntil((route) => route.isFirst);
            widget.onSessionChanged?.call();
          },
        ),
      ),
    );
  }

  Future<void> _deleteAccount() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DeleteAccountScreen(
          onAccountDeleted: () async {
            if (!mounted) return;
            Navigator.of(context).popUntil((route) => route.isFirst);
            await widget.onLogout();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsModalShell(
      title: 'Account',
      eyebrow: 'GENERAL',
      children: _loading
          ? const [
              SizedBox(height: 180),
              Center(
                  child: CircularProgressIndicator(color: ZveltTokens.brand)),
            ]
          : [
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 86,
                      height: 86,
                      clipBehavior: Clip.antiAlias,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: ZveltTokens.gradBrand,
                      ),
                      child: (_photoUrl ?? '').isNotEmpty
                          ? Image.network(
                              mediaAbsoluteUrl(_photoUrl),
                              width: 86,
                              height: 86,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Text(
                                _initials,
                                style: ZType.h1.copyWith(color: Colors.white),
                              ),
                            )
                          : Text(_initials,
                              style: ZType.h1.copyWith(color: Colors.white)),
                    ),
                    TextButton.icon(
                      onPressed: _changePhoto,
                      icon: const Icon(AppIcons.camera, size: 17),
                      label: const Text('Change photo'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ZveltTokens.s2),
              SettingsCard(
                divided: false,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(ZveltTokens.s4),
                    child: Column(
                      children: [
                        _SettingsField(controller: _name, label: 'Full name'),
                        const SizedBox(height: ZveltTokens.s3),
                        _SettingsField(
                            controller: _username,
                            label: 'Username',
                            prefix: '@'),
                        const SizedBox(height: ZveltTokens.s3),
                        _SettingsField(
                            controller: _bio, label: 'Bio', maxLines: 3),
                        const SizedBox(height: ZveltTokens.s3),
                        _SettingsField(
                          controller: _emailController,
                          label: 'Email',
                          enabled: false,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SettingsSectionTitle('Sign-in & security'),
              SettingsCard(
                children: [
                  SettingsRow(
                    icon: AppIcons.user,
                    tint: SettingsTint.orange,
                    title: 'Sign in to an existing account',
                    subtitle:
                        'Switches this device to that account (this one stays on the server)',
                    onTap: _signInToExistingAccount,
                  ),
                  SettingsRow(
                    icon: AppIcons.lock,
                    tint: SettingsTint.blue,
                    title: 'Change password',
                    subtitle: 'Update your email sign-in password',
                    onTap: _changePassword,
                  ),
                  SettingsRow(
                    icon: AppIcons.shield_check,
                    tint: SettingsTint.green,
                    title: 'Two-factor authentication',
                    subtitle: 'Additional verification for your account',
                    trailingText: 'Not set',
                    chevron: false,
                    onTap: () => settingsSnack(context,
                        'Two-factor setup requires the secure backend challenge flow.'),
                  ),
                ],
              ),
              const SizedBox(height: ZveltTokens.s5),
              SettingsActionButton(
                label: _saving ? 'Saving...' : 'Save account',
                icon: AppIcons.check,
                onTap: _saving ? null : _save,
              ),
              const SizedBox(height: ZveltTokens.cardGap),
              SettingsActionButton(
                label: 'Sign out',
                icon: AppIcons.sign_out_alt,
                destructive: true,
                onTap: _logout,
              ),
              const SizedBox(height: ZveltTokens.cardGap),
              TextButton(
                onPressed: _deleteAccount,
                child: const Text('Delete account',
                    style: TextStyle(color: ZveltTokens.error)),
              ),
            ],
    );
  }
}

class PhysicalDataSettingsScreen extends StatefulWidget {
  const PhysicalDataSettingsScreen({super.key});

  @override
  State<PhysicalDataSettingsScreen> createState() =>
      _PhysicalDataSettingsScreenState();
}

class _PhysicalDataSettingsScreenState
    extends State<PhysicalDataSettingsScreen> {
  final _profile = ProfileService();
  bool _loading = true;
  bool _saving = false;
  double _weight = 75;
  double _height = 175;
  int _age = 25;
  String _sex = 'male';
  String _units = 'metric';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = await _profile.getMe(refresh: true);
    final p = me?['profile'] as Map<String, dynamic>?;
    final year = DateTime.now().year;
    if (!mounted) return;
    setState(() {
      _weight = (p?['bodyweightKg'] as num?)?.toDouble() ?? 75;
      _height = (p?['heightCm'] as num?)?.toDouble() ?? 175;
      _sex = p?['sex']?.toString() ?? 'male';
      _units = p?['unitSystem']?.toString() ?? UnitsNotifier.system.value;
      final birthYear = (p?['birthYear'] as num?)?.toInt();
      _age = birthYear == null ? 25 : (year - birthYear).clamp(13, 99);
      _loading = false;
    });
  }

  String get _weightLabel => _units == 'imperial'
      ? '${(_weight * 2.20462).toStringAsFixed(1)} lb'
      : '${_weight.toStringAsFixed(1)} kg';

  String get _heightLabel => _units == 'imperial'
      ? '${(_height / 2.54).round()} in'
      : '${_height.round()} cm';

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _profile.updateProfile(
        bodyweightKg: _weight,
        heightCm: _height,
        sex: _sex,
        birthYear: DateTime.now().year - _age,
      );
      if (!mounted) return;
      settingsSnack(context, 'Physical data saved.');
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
      title: 'Physical data',
      closeIcon: AppIcons.cross_small,
      eyebrow: 'ACCOUNT',
      footer: SettingsActionButton(
        label: _saving ? 'Saving...' : 'Save changes',
        icon: AppIcons.check,
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
                  SettingsStepperRow(
                    label: 'Bodyweight',
                    subtitle: 'Used for relative-strength and calorie math',
                    valueLabel: _weightLabel,
                    onDec: _weight > 30
                        ? () => setState(() => _weight -= .5)
                        : null,
                    onInc: _weight < 250
                        ? () => setState(() => _weight += .5)
                        : null,
                  ),
                  SettingsStepperRow(
                    label: 'Height',
                    valueLabel: _heightLabel,
                    onDec: _height > 120
                        ? () => setState(() => _height -= 1)
                        : null,
                    onInc: _height < 230
                        ? () => setState(() => _height += 1)
                        : null,
                  ),
                  SettingsStepperRow(
                    label: 'Age',
                    valueLabel: '$_age yrs',
                    onDec: _age > 13 ? () => setState(() => _age--) : null,
                    onInc: _age < 99 ? () => setState(() => _age++) : null,
                  ),
                ],
              ),
              const SettingsSectionTitle('Biological sex'),
              SettingsCard(
                divided: false,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(ZveltTokens.s4),
                    child: SettingsSegmented<String>(
                      value: _sex,
                      options: const [
                        (value: 'male', label: 'Male'),
                        (value: 'female', label: 'Female'),
                        (value: 'other', label: 'Other'),
                      ],
                      onChanged: (value) => setState(() => _sex = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ZveltTokens.s4),
              const SettingsNoteCard(
                'These values improve BMR, recovery, heart-rate and strength calculations. Canonical storage remains metric.',
              ),
            ],
    );
  }
}

class GoalsTrainingScreen extends StatefulWidget {
  const GoalsTrainingScreen({super.key});

  @override
  State<GoalsTrainingScreen> createState() => _GoalsTrainingScreenState();
}

class _GoalsTrainingScreenState extends State<GoalsTrainingScreen> {
  final _auth = AuthService();
  bool _loading = true;
  bool _saving = false;
  String _goal = 'strength';
  int _days = 4;
  final Map<String, double> _maxes = {
    SettingsKeys.rmSquat: 140,
    SettingsKeys.rmBench: 100,
    SettingsKeys.rmDeadlift: 180,
    SettingsKeys.rmPress: 62.5,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = await _auth.getAccessToken();
    final prefs = await SharedPreferences.getInstance();
    if (token != null) {
      try {
        final res = await http.get(
          Uri.parse('$v1Base/me/training-profile'),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          final tp = body['trainingProfile'] as Map<String, dynamic>?;
          _goal = _goalFromBackend(
              tp?['primaryGoal']?.toString(), tp?['secondaryGoals']);
          _days = (tp?['daysPerWeek'] as num?)?.toInt() ?? 4;
        }
      } catch (_) {}
    }
    for (final entry in _maxes.entries.toList()) {
      _maxes[entry.key] = prefs.getDouble(entry.key) ?? entry.value;
    }
    if (mounted) setState(() => _loading = false);
  }

  String _goalFromBackend(String? value, Object? secondary) {
    if (secondary is List && secondary.contains('endurance')) {
      return 'endurance';
    }
    if (value == 'hypertrophy') return 'hypertrophy';
    if (value == 'maintenance') return 'healthy';
    return 'strength';
  }

  Future<void> _save() async {
    final token = await _auth.getAccessToken();
    if (!mounted) return;
    if (token == null) {
      settingsSnack(context, 'Sign in again to save your goals.', error: true);
      return;
    }
    setState(() => _saving = true);
    final primary = switch (_goal) {
      'hypertrophy' => 'hypertrophy',
      'healthy' => 'maintenance',
      'endurance' => 'maintenance',
      _ => 'strength',
    };
    try {
      final res = await http
          .patch(
            Uri.parse('$v1Base/me/training-profile'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'primaryGoal': primary,
              'secondaryGoals':
                  _goal == 'endurance' ? ['endurance'] : <String>[],
              'daysPerWeek': _days,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Save failed (${res.statusCode})');
      }
      final prefs = await SharedPreferences.getInstance();
      for (final entry in _maxes.entries) {
        await prefs.setDouble(entry.key, entry.value);
      }
      await AppDataCache.instance.clearTrainingProfile();
      if (!mounted) return;
      settingsSnack(context, 'Training goals updated.');
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        settingsSnack(context, 'Could not save training goals.', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const goals = [
      (id: 'strength', title: 'Strength', sub: 'Heavy, low reps'),
      (id: 'hypertrophy', title: 'Hypertrophy', sub: 'Build muscle'),
      (id: 'endurance', title: 'Endurance', sub: 'Engine and stamina'),
      (id: 'healthy', title: 'Stay healthy', sub: 'Balanced fitness'),
    ];
    return SettingsModalShell(
      title: 'Goals & training max',
      closeIcon: AppIcons.cross_small,
      eyebrow: 'ACCOUNT',
      footer: SettingsActionButton(
        label: _saving ? 'Saving...' : 'Save goals',
        icon: AppIcons.check,
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
                  for (final goal in goals)
                    SettingsRadioRow(
                      title: goal.title,
                      subtitle: goal.sub,
                      selected: _goal == goal.id,
                      onTap: () => setState(() => _goal = goal.id),
                    ),
                ],
              ),
              const SettingsSectionTitle('Weekly frequency'),
              SettingsCard(
                children: [
                  SettingsStepperRow(
                    label: 'Days per week',
                    subtitle: '$_days sessions planned',
                    valueLabel: '$_days days',
                    onDec: _days > 1 ? () => setState(() => _days--) : null,
                    onInc: _days < 7 ? () => setState(() => _days++) : null,
                  ),
                ],
              ),
              const SettingsSectionTitle('Starting 1RM'),
              SettingsCard(
                children: [
                  _maxRow('Squat', SettingsKeys.rmSquat),
                  _maxRow('Bench', SettingsKeys.rmBench),
                  _maxRow('Deadlift', SettingsKeys.rmDeadlift),
                  _maxRow('Press', SettingsKeys.rmPress),
                ],
              ),
              const SizedBox(height: ZveltTokens.s4),
              const SettingsNoteCard(
                'Starting maxes guide early recommendations. Logged workouts remain the source of truth for progression.',
              ),
            ],
    );
  }

  Widget _maxRow(String label, String key) {
    final value = _maxes[key] ?? 0;
    return SettingsStepperRow(
      label: label,
      valueLabel: '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)} kg',
      onDec: value > 0
          ? () => setState(() => _maxes[key] = (value - 2.5).clamp(0, 500))
          : null,
      onInc: value < 500
          ? () => setState(() => _maxes[key] = (value + 2.5).clamp(0, 500))
          : null,
    );
  }
}

class _SettingsField extends StatelessWidget {
  const _SettingsField({
    required this.controller,
    required this.label,
    this.prefix,
    this.maxLines = 1,
    this.obscure = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String? prefix;
  final int maxLines;
  final bool obscure;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: obscure ? 1 : maxLines,
      obscureText: obscure,
      style: ZType.bodyM,
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        filled: true,
        fillColor: ZveltTokens.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZveltTokens.rSm),
          borderSide: BorderSide(color: ZveltTokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZveltTokens.rSm),
          borderSide: BorderSide(color: ZveltTokens.border),
        ),
      ),
    );
  }
}
