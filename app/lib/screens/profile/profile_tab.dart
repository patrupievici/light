import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/profile_service.dart';
import '../../services/settings_store.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';
import '../../theme/zvelt_theme_notifier.dart';
import '../../widgets/zvelt_main_nav_bar.dart';
import '../ai/ai_chat_screen.dart';
import '../analytics/progress_hub_screen.dart';
import 'account_settings_screen.dart';
import 'integrations_screen.dart';

/// PROFILE — 1:1 with the ZVELT handoff prototype (screen A7).
///
/// Header ("Profile" + settings gear + logout) · profile block (76px rounded
/// avatar, name + premium crown, email) · Edit Profile + Add Device buttons ·
/// Premium banner · Appearance row (Dark/Light) · rows: Progress, Preferences,
/// Account, Help & Feedback, AI Companion, About ZVELT, Request a Feature,
/// Report a Bug. Nothing else.
///
/// The settings gear and Preferences both open the prototype's
/// `sheetSettings` (Units · Notifications · Haptics · Rest sound · Sign out —
/// all persisted; Units actually converts via [UnitsNotifier]).
class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key, required this.onLogout});
  final Future<void> Function() onLogout;

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final _profile = ProfileService();

  String _name = 'Athlete';
  String _email = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await _profile.getMe();
      if (!mounted) return;
      final profile = me?['profile'] as Map<String, dynamic>?;
      setState(() {
        _name = (profile?['displayName'] as String?)?.trim().isNotEmpty == true
            ? (profile!['displayName'] as String).trim()
            : 'Athlete';
        _email = (me?['email'] as String?)?.trim() ?? '';
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── actions ──────────────────────────────────────────────────────────────
  void _openSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SettingsSheet(onLogout: _confirmLogout),
    );
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZveltTokens.surface,
        title: const Text('Sign out?'),
        content: Text("You'll need to sign in again to sync your data.",
            style: TextStyle(color: ZveltTokens.text2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ZveltTokens.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await widget.onLogout();
  }

  void _push(Widget screen) => Navigator.of(context)
      .push<void>(MaterialPageRoute<void>(builder: (_) => screen))
      .then((_) => _load());

  void _sheet(Widget sheet) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => sheet,
      );

  // ─── build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: ListView(
        padding: EdgeInsets.only(
          top: topPad + 8,
          bottom: ZveltMainNavBar.reservedBottomHeight(context),
        ),
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
            child: Row(
              children: [
                if (canPop)
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Icon(AppIcons.arrow_small_left,
                          size: 22, color: ZveltTokens.text2),
                    ),
                  ),
                Text('Profile', style: ZType.h2),
                const Spacer(),
                _iconBtn(AppIcons.settings, 'Settings', _openSettingsSheet),
                const SizedBox(width: 9),
                _iconBtn(AppIcons.sign_out_alt, 'Sign out', _confirmLogout),
              ],
            ),
          ),
          // Profile block
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
            child: Row(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: ZveltTokens.gradAccentDeep,
                    borderRadius: BorderRadius.circular(ZveltTokens.rCardSm),
                    border:
                        Border.all(color: ZveltTokens.border, width: 1.5),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x40000000),
                          blurRadius: 20,
                          offset: Offset(0, 8)),
                    ],
                  ),
                  child: Text(
                    _name.isEmpty ? 'A' : _name[0].toUpperCase(),
                    style: ZType.h2.copyWith(color: ZveltTokens.onBrand),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(_loading ? '…' : _name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ZType.h3.copyWith(fontSize: 20)),
                          ),
                          const SizedBox(width: 7),
                          const Icon(AppIcons.crown,
                              size: 18, color: ZveltTokens.brand),
                        ],
                      ),
                      if (_email.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Icon(AppIcons.envelope,
                                size: 15, color: ZveltTokens.text2),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(_email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ZType.bodyS),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Edit Profile + Add Device
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () =>
                        _push(AccountSettingsScreen(onLogout: widget.onLogout)),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: ZveltTokens.chip,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: ZveltTokens.borderStrong),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(AppIcons.edit,
                              size: 16, color: ZveltTokens.text),
                          const SizedBox(width: 7),
                          Text('Edit Profile',
                              style: ZType.bodyM.copyWith(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: ZveltTokens.text)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => _push(const IntegrationsScreen()),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: ZveltTokens.brand,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: ZveltTokens.glowMd,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(AppIcons.plus,
                              size: 16, color: ZveltTokens.onBrand),
                          const SizedBox(width: 7),
                          Text('Add Device',
                              style: ZType.bodyM.copyWith(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: ZveltTokens.onBrand)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Premium banner
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
            child: InkWell(
              onTap: () => _sheet(const _PremiumSheet()),
              borderRadius: BorderRadius.circular(ZveltTokens.rCard),
              child: Container(
                clipBehavior: Clip.antiAlias,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment(-1, -0.3),
                    end: Alignment(1, 0.6),
                    stops: [0, 0.55, 1],
                    colors: [
                      Color(0xFFF58A11),
                      Color(0xFFEE6E08),
                      Color(0xFFD85F04)
                    ],
                  ),
                  borderRadius: BorderRadius.circular(ZveltTokens.rCard),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x8CEE6E08),
                        blurRadius: 34,
                        offset: Offset(0, 16),
                        spreadRadius: -8),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(AppIcons.crown,
                          size: 24, color: ZveltTokens.onBrand),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Upgrade To ZVELT Premium',
                              style: ZType.bodyL.copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: ZveltTokens.onBrand)),
                          const SizedBox(height: 3),
                          Text(
                              'Unlock smarter training, nutrition and AI coaching.',
                              style: ZType.bodyS.copyWith(
                                  fontSize: 12,
                                  color: const Color(0xE6FFFFFF))),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: Color(0x38FFFFFF)),
                      child: const Icon(AppIcons.angle_small_right,
                          size: 18, color: ZveltTokens.onBrand),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Appearance row
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
              decoration: BoxDecoration(
                gradient: ZveltTokens.surfaceGrad,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: ZveltTokens.border),
              ),
              child: Row(
                children: [
                  Icon(AppIcons.moon, size: 20, color: ZveltTokens.text),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text('Appearance',
                        style: ZType.bodyM.copyWith(
                            fontSize: 14.5, fontWeight: FontWeight.w600)),
                  ),
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: ZveltThemeNotifier.mode,
                    builder: (context, mode, _) {
                      final dark = mode != ThemeMode.light;
                      Widget item(IconData icon, bool selected,
                              VoidCallback onTap) =>
                          InkWell(
                            onTap: onTap,
                            borderRadius: BorderRadius.circular(11),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 11, vertical: 6),
                              decoration: BoxDecoration(
                                color: selected
                                    ? ZveltTokens.brand
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Icon(icon,
                                  size: 15,
                                  color: selected
                                      ? ZveltTokens.onBrand
                                      : ZveltTokens.text3),
                            ),
                          );
                      return Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: ZveltTokens.chip,
                          borderRadius: BorderRadius.circular(ZveltTokens.rChip),
                          border: Border.all(color: ZveltTokens.border),
                        ),
                        child: Row(
                          children: [
                            item(AppIcons.moon, dark,
                                () => ZveltThemeNotifier.set(ThemeMode.dark)),
                            const SizedBox(width: 3),
                            item(AppIcons.sun, !dark,
                                () => ZveltThemeNotifier.set(ThemeMode.light)),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          // Menu rows
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
            child: Column(
              children: [
                _row(AppIcons.chart_line_up, 'Progress',
                    accent: true, onTap: () => _push(const ProgressHubScreen())),
                _row(AppIcons.settings_sliders, 'Preferences',
                    onTap: _openSettingsSheet),
                _row(AppIcons.user, 'Account',
                    onTap: () =>
                        _push(AccountSettingsScreen(onLogout: widget.onLogout))),
                _row(AppIcons.interrogation, 'Help & Feedback',
                    onTap: () => _sheet(const _HelpSheet())),
                _row(AppIcons.sparkles, 'AI Companion',
                    accent: true, onTap: () => _push(const AiChatScreen())),
                _row(AppIcons.info, 'About ZVELT',
                    onTap: () => _sheet(const _AboutSheet())),
                _row(AppIcons.bulb, 'Request a Feature',
                    onTap: () => _sheet(const _FeedbackSheet(
                        title: 'Request a Feature',
                        hint: 'What should ZVELT do next?',
                        subject: 'Feature request'))),
                _row(AppIcons.bug, 'Report a Bug',
                    onTap: () => _sheet(const _FeedbackSheet(
                        title: 'Report a Bug',
                        hint: 'What happened? What did you expect?',
                        subject: 'Bug report'))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, String label, VoidCallback onTap) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZveltTokens.rChip),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ZveltTokens.chip,
            borderRadius: BorderRadius.circular(ZveltTokens.rChip),
            border: Border.all(color: ZveltTokens.border),
          ),
          child: Icon(icon, size: 20, color: ZveltTokens.text),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label,
      {bool accent = false, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(
            gradient: ZveltTokens.surfaceGrad,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: ZveltTokens.border),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 20,
                  color: accent ? ZveltTokens.brand : ZveltTokens.text),
              const SizedBox(width: 13),
              Expanded(
                child: Text(label,
                    style: ZType.bodyM.copyWith(
                        fontSize: 14.5, fontWeight: FontWeight.w600)),
              ),
              Icon(AppIcons.angle_small_right,
                  size: 17, color: ZveltTokens.text4),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// sheetSettings — Units · Notifications · Haptics · Rest sound · Sign out
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.onLogout});
  final Future<void> Function() onLogout;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  static const _kNotif = 'zvelt_pref_notifications';
  static const _kHaptics = 'zvelt_pref_haptics';
  static const _kRestSound = 'zvelt_pref_rest_sound';

  bool _notifications = true;
  bool _haptics = true;
  bool _restSound = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _notifications = p.getBool(_kNotif) ?? true;
        _haptics = p.getBool(_kHaptics) ?? true;
        _restSound = p.getBool(_kRestSound) ?? false;
        _ready = true;
      });
    } catch (_) {
      if (mounted) setState(() => _ready = true);
    }
  }

  Future<void> _save(String key, bool value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(key, value);
    } catch (_) {/* best-effort */}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: ZveltTokens.sheetGrad,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rSheet)),
        border: Border.all(color: ZveltTokens.border),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: ZveltTokens.track,
                borderRadius: BorderRadius.circular(ZveltTokens.rPill),
              ),
            ),
          ),
          Row(
            children: [
              Text('Settings', style: ZType.h4.copyWith(fontSize: 19)),
              const Spacer(),
              InkWell(
                onTap: () => Navigator.of(context).pop(),
                customBorder: const CircleBorder(),
                child: Icon(AppIcons.cross_small,
                    size: 22, color: ZveltTokens.text2),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Units — actually converts (UnitsNotifier drives kg/lb app-wide).
          Text('UNITS', style: ZType.eyebrow),
          const SizedBox(height: 8),
          ValueListenableBuilder<String>(
            valueListenable: UnitsNotifier.system,
            builder: (context, system, _) {
              Widget item(String label, String value) => Expanded(
                    child: InkWell(
                      onTap: () => UnitsNotifier.set(value),
                      borderRadius: BorderRadius.circular(ZveltTokens.rControl),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: system == value
                              ? ZveltTokens.brand
                              : ZveltTokens.chip,
                          borderRadius:
                              BorderRadius.circular(ZveltTokens.rControl),
                          border: system == value
                              ? null
                              : Border.all(color: ZveltTokens.borderStrong),
                          boxShadow:
                              system == value ? ZveltTokens.glowSm : null,
                        ),
                        child: Text(label,
                            style: ZType.bodyM.copyWith(
                                fontWeight: FontWeight.w700,
                                color: system == value
                                    ? ZveltTokens.onBrand
                                    : ZveltTokens.text)),
                      ),
                    ),
                  );
              return Row(children: [
                item('Kilograms', 'metric'),
                const SizedBox(width: 8),
                item('Pounds', 'imperial'),
              ]);
            },
          ),
          const SizedBox(height: 16),
          _toggleRow('Notifications', _notifications, (v) {
            setState(() => _notifications = v);
            _save(_kNotif, v);
          }),
          _toggleRow('Haptics', _haptics, (v) {
            setState(() => _haptics = v);
            _save(_kHaptics, v);
          }),
          _toggleRow('Rest sound', _restSound, (v) {
            setState(() => _restSound = v);
            _save(_kRestSound, v);
          }),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: !_ready
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      widget.onLogout();
                    },
              style: FilledButton.styleFrom(
                backgroundColor: ZveltTokens.chip,
                foregroundColor: ZveltTokens.error,
                side: BorderSide(color: ZveltTokens.borderStrong),
              ),
              child: const Text('Sign out'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
        decoration: BoxDecoration(
          gradient: ZveltTokens.surface2Grad,
          borderRadius: BorderRadius.circular(ZveltTokens.rControl),
          border: Border.all(color: ZveltTokens.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: ZType.bodyM.copyWith(
                      fontSize: 13.5, fontWeight: FontWeight.w700)),
            ),
            Switch(value: value, onChanged: _ready ? onChanged : null),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// sheetPremium — plan toggle + benefits (purchases are backend-TBD)
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumSheet extends StatefulWidget {
  const _PremiumSheet();

  @override
  State<_PremiumSheet> createState() => _PremiumSheetState();
}

class _PremiumSheetState extends State<_PremiumSheet> {
  bool _annual = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: ZveltTokens.sheetGrad,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rSheet)),
        border: Border.all(color: ZveltTokens.border),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: ZveltTokens.track,
                borderRadius: BorderRadius.circular(ZveltTokens.rPill),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: ZveltTokens.gradAccent,
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: ZveltTokens.glowSm,
                ),
                child: const Icon(AppIcons.crown,
                    size: 20, color: ZveltTokens.onBrand),
              ),
              const SizedBox(width: 11),
              Text('ZVELT Premium', style: ZType.h4.copyWith(fontSize: 19)),
              const Spacer(),
              InkWell(
                onTap: () => Navigator.of(context).pop(),
                customBorder: const CircleBorder(),
                child: Icon(AppIcons.cross_small,
                    size: 22, color: ZveltTokens.text2),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final (label, annual) in const [
                ('Monthly', false),
                ('Annual · save 40%', true)
              ]) ...[
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _annual = annual),
                    borderRadius: BorderRadius.circular(ZveltTokens.rControl),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _annual == annual
                            ? ZveltTokens.brand
                            : ZveltTokens.chip,
                        borderRadius:
                            BorderRadius.circular(ZveltTokens.rControl),
                        border: _annual == annual
                            ? null
                            : Border.all(color: ZveltTokens.borderStrong),
                      ),
                      child: Text(label,
                          style: ZType.bodyS.copyWith(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _annual == annual
                                  ? ZveltTokens.onBrand
                                  : ZveltTokens.text)),
                    ),
                  ),
                ),
                if (!annual) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 16),
          for (final b in const [
            'Unlimited exercise ranks & explainability',
            'AI program builder + weekly meal plans',
            'Advanced progress analytics',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                children: [
                  const Icon(AppIcons.check,
                      size: 16, color: ZveltTokens.success),
                  const SizedBox(width: 9),
                  Expanded(child: Text(b, style: ZType.bodyS)),
                ],
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content:
                        Text('Purchases open at launch — you\'re early 🎉')));
              },
              child: Text(_annual ? 'Upgrade · Annual' : 'Upgrade · Monthly'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// sheetHelp / sheetFeature / sheetBug / sheetAbout
// ─────────────────────────────────────────────────────────────────────────────

class _HelpSheet extends StatelessWidget {
  const _HelpSheet();

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'Help & Feedback',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (q, a) in const [
            ('How do ranks work?',
                'Every WORK set in 1–12 reps counts. Your best e1RM per exercise is compared to athletes in your weight class.'),
            ('Does tracking work offline?',
                'Yes — workouts, food and cardio log offline and sync when you reconnect.'),
            ('How is my streak counted?',
                'Any completed workout or saved cardio session marks the day as trained.'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(q,
                      style: ZType.bodyM.copyWith(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(a, style: ZType.bodyS.copyWith(fontSize: 12.5)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet(
      {required this.title, required this.hint, required this.subject});
  final String title;
  final String hint;
  final String subject;

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _ctrl.text.trim();
    if (body.isEmpty) return; // never submit empty
    final info = await PackageInfo.fromPlatform();
    final text =
        '[ZVELT ${widget.subject}] v${info.version}+${info.buildNumber}\n\n$body';
    if (!mounted) return;
    Navigator.of(context).pop();
    // Share sheet — the user picks email/messaging; nothing is invented.
    await SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: widget.title,
      child: Column(
        children: [
          TextField(
            controller: _ctrl,
            maxLines: 5,
            minLines: 4,
            style: ZType.bodyM,
            decoration: InputDecoration(hintText: widget.hint),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: _send,
              child: const Text('Send'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutSheet extends StatefulWidget {
  const _AboutSheet();

  @override
  State<_AboutSheet> createState() => _AboutSheetState();
}

class _AboutSheetState extends State<_AboutSheet> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = 'v${info.version} (${info.buildNumber})');
      }
    });
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {/* best-effort */}
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'About ZVELT',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: ZveltTokens.gradAccent,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: ZveltTokens.glowSm,
                ),
                child: const Icon(AppIcons.sparkles,
                    size: 22, color: ZveltTokens.onBrand),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ZVELT',
                      style: ZType.h4.copyWith(letterSpacing: 2.5)),
                  Text(_version.isEmpty ? '…' : _version,
                      style: ZType.monoXS),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () => _open('https://zvelt.app/privacy'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Privacy Policy',
                  style: ZType.bodyM.copyWith(color: ZveltTokens.brand)),
            ),
          ),
          InkWell(
            onTap: () => _open('https://zvelt.app/terms'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Terms of Service',
                  style: ZType.bodyM.copyWith(color: ZveltTokens.brand)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared sheet chrome: grabber + title row with ✕.
class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          gradient: ZveltTokens.sheetGrad,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(ZveltTokens.rSheet)),
          border: Border.all(color: ZveltTokens.border),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: ZveltTokens.track,
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                ),
              ),
            ),
            Row(
              children: [
                Text(title, style: ZType.h4.copyWith(fontSize: 19)),
                const Spacer(),
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  customBorder: const CircleBorder(),
                  child: Icon(AppIcons.cross_small,
                      size: 22, color: ZveltTokens.text2),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
