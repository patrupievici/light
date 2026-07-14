
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../services/settings_store.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';
import '../../theme/zvelt_theme_notifier.dart';
import '../../widgets/zvelt_main_nav_bar.dart';
import '../ai/ai_chat_screen.dart';
import '../analytics/progress_screen.dart';
import '../onboarding/light_onboarding_flow.dart';
import '../onboarding/onboarding_keys.dart';

/// PROFILE — 1:1 with the ZVELT handoff prototype (screen A7).
///
/// Header ("Profile" + settings gear + logout) · profile block (76px rounded
/// avatar, name + premium crown, email) · Edit Profile button (Add Device cut
/// for V1 — user call 2026-07-14) · Premium banner · Appearance row
/// (Dark/Light) · rows: Progress (→ the 1:1 ProgressScreen, prototype goProg),
/// Preferences, Account, Help & Feedback, AI Companion, About ZVELT,
/// Request a Feature, Report a Bug. Nothing else.
///
/// Sheets (all prototype 1:1): sheetSettings (Units · Notifications · Haptics ·
/// Rest timer sound · Replay intro tour · Sign out), sheetEdit, sheetPremium,
/// sheetAccount, sheetHelp, sheetAbout, sheetFeature, sheetBug.
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
  DateTime? _memberSince;
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
      final createdRaw = me?['createdAt'] ?? profile?['createdAt'];
      setState(() {
        _name = (profile?['displayName'] as String?)?.trim().isNotEmpty == true
            ? (profile!['displayName'] as String).trim()
            : 'Athlete';
        _email = (me?['email'] as String?)?.trim() ?? '';
        _memberSince =
            createdRaw is String ? DateTime.tryParse(createdRaw) : null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── actions ──────────────────────────────────────────────────────────────
  void _openSettingsSheet() {
    _sheet(_SettingsSheet(onLogout: _confirmLogout));
  }

  void _openEditSheet() {
    _sheet(_EditProfileSheet(
      initialName: _name,
      initialEmail: _email,
      onSaved: () {
        _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profile updated')));
      },
    ));
  }

  void _openAccountSheet() {
    _sheet(_AccountSheet(
      name: _name,
      email: _email,
      memberSince: _memberSince,
      onEditProfile: _openEditSheet,
      onLogout: _confirmLogout,
    ));
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
          // Edit Profile (Add Device removed for V1 — user call 2026-07-14;
          // the device/integrations flow returns post-V1).
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
            child: InkWell(
              onTap: _openEditSheet,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: ZveltTokens.chip,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: ZveltTokens.borderStrong),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(AppIcons.edit, size: 16, color: ZveltTokens.text),
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
          // Appearance row — prototype leading glyph is a sun/brightness icon.
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
                  Icon(AppIcons.sun, size: 20, color: ZveltTokens.text),
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
                // Prototype goProg (HTML 634): the Progress row opens the SAME
                // 1:1 Progress screen as Home's Volume card — nothing else.
                _row(AppIcons.chart_line_up, 'Progress',
                    accent: true, onTap: () => _push(const ProgressScreen())),
                _row(AppIcons.settings_sliders, 'Preferences',
                    onTap: _openSettingsSheet),
                _row(AppIcons.user, 'Account', onTap: _openAccountSheet),
                _row(AppIcons.interrogation, 'Help & Feedback',
                    onTap: () => _sheet(const _HelpSheet())),
                _row(AppIcons.sparkles, 'AI Companion',
                    accent: true, onTap: () => _push(const AiChatScreen())),
                _row(AppIcons.info, 'About ZVELT',
                    onTap: () => _sheet(const _AboutSheet())),
                _row(AppIcons.bulb, 'Request a Feature',
                    onTap: () => _sheet(const _FeedbackSheet(
                        title: 'Request a Feature',
                        subtitle: 'What would make ZVELT better for you?',
                        hint: "Describe the feature you'd love to see…",
                        ctaLabel: 'Submit request',
                        subject: 'Feature request'))),
                _row(AppIcons.bug, 'Report a Bug',
                    onTap: () => _sheet(const _FeedbackSheet(
                        title: 'Report a Bug',
                        subtitle: 'Tell us what went wrong so we can fix it',
                        hint: 'What happened? What did you expect instead?…',
                        ctaLabel: 'Send report',
                        subject: 'Bug report',
                        showVersionChip: true))),
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
                  size: 17, color: ZveltTokens.text3),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// sheetSettings — Units · Notifications · Haptics · Rest timer sound ·
// Replay intro tour · Sign out (HTML 1042-1057)
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

  /// Relaunch the light onboarding flow ("intro tour"). The flow re-derives
  /// its own completion key on finish, so replaying is safe for the same user.
  Future<void> _replayTour() async {
    final nav = Navigator.of(context);
    String uid = '';
    try {
      uid = await AuthService().getStoredUserId() ?? '';
    } catch (_) {/* offline — replay as guest key */}
    if (!mounted) return;
    Navigator.of(context).pop(); // close the sheet first
    nav.push<void>(MaterialPageRoute<void>(
      builder: (ctx) => LightOnboardingFlow(
        completionKey:
            '${kOnboarding2CompletedKey}_${uid.isEmpty ? 'guest' : uid}',
        startAuthenticated: true,
        onComplete: () => Navigator.of(ctx).pop(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'Settings',
      maxHeightFactor: 0.92,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Units — sentence-case 12px label (prototype line 1046), segments
          // "Kilograms (kg)" / "Pounds (lb)" (line 1047). Actually converts
          // app-wide via [UnitsNotifier].
          Text('Units',
              style: ZType.bodyS
                  .copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 9),
          ValueListenableBuilder<String>(
            valueListenable: UnitsNotifier.system,
            builder: (context, system, _) {
              Widget item(String label, String value) => Expanded(
                    child: InkWell(
                      onTap: () => UnitsNotifier.set(value),
                      borderRadius: BorderRadius.circular(11),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: system == value
                              ? ZveltTokens.brand
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Text(label,
                            style: ZType.bodyS.copyWith(
                                fontSize: 13,
                                fontWeight: system == value
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: system == value
                                    ? ZveltTokens.onBrand
                                    : ZveltTokens.text2)),
                      ),
                    ),
                  );
              return Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: ZveltTokens.chip,
                  borderRadius: BorderRadius.circular(ZveltTokens.rChip),
                  border: Border.all(color: ZveltTokens.border),
                ),
                child: Row(children: [
                  item('Kilograms (kg)', 'metric'),
                  const SizedBox(width: 4),
                  item('Pounds (lb)', 'imperial'),
                ]),
              );
            },
          ),
          const SizedBox(height: 18),
          _toggleRow('Notifications', _notifications, (v) {
            setState(() => _notifications = v);
            _save(_kNotif, v);
          }),
          _toggleRow('Haptics', _haptics, (v) {
            setState(() => _haptics = v);
            _save(_kHaptics, v);
          }),
          _toggleRow('Rest timer sound', _restSound, (v) {
            setState(() => _restSound = v);
            _save(_kRestSound, v);
          }),
          const SizedBox(height: 9),
          // Replay intro tour (prototype line 1053).
          InkWell(
            onTap: _replayTour,
            borderRadius: BorderRadius.circular(ZveltTokens.rControl),
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
              decoration: BoxDecoration(
                gradient: ZveltTokens.surface2Grad,
                borderRadius: BorderRadius.circular(ZveltTokens.rControl),
                border: Border.all(color: ZveltTokens.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ZveltTokens.brandTint,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: ZveltTokens.brand.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(AppIcons.refresh,
                        size: 17, color: ZveltTokens.brand),
                  ),
                  const SizedBox(width: 12),
                  Text('Replay intro tour',
                      style: ZType.bodyM.copyWith(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Sign out — red-tinted treatment (prototype line 1054).
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
                backgroundColor: ZveltTokens.error.withValues(alpha: 0.12),
                foregroundColor: ZveltTokens.error,
                side: BorderSide(
                    color: ZveltTokens.error.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ZveltTokens.rControl),
                ),
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
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
                      fontSize: 14.5, fontWeight: FontWeight.w600)),
            ),
            _BrandSwitch(value: value, onChanged: _ready ? onChanged : null),
          ],
        ),
      ),
    );
  }
}

/// 44×26 brand-styled switch (prototype JS 2076-2077): accent track when on,
/// neutral track when off, 20px white knob.
class _BrandSwitch extends StatelessWidget {
  const _BrandSwitch({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: ZMotion.quick,
          curve: ZMotion.emphasized,
          width: 44,
          height: 26,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? ZveltTokens.brand : ZveltTokens.track,
            borderRadius: BorderRadius.circular(13),
          ),
          child: AnimatedAlign(
            duration: ZMotion.quick,
            curve: ZMotion.emphasized,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: ZveltTokens.onBrand,
                boxShadow: [
                  BoxShadow(
                      color: Color(0x4D000000),
                      blurRadius: 4,
                      offset: Offset(0, 2)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// sheetEdit — Edit Profile (HTML 946-960)
// ─────────────────────────────────────────────────────────────────────────────

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({
    required this.initialName,
    required this.initialEmail,
    required this.onSaved,
  });
  final String initialName;
  final String initialEmail;
  final VoidCallback onSaved;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.initialName);
  late final TextEditingController _emailCtrl =
      TextEditingController(text: widget.initialEmail);
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || name.length > 40) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Name must be 1–40 characters.'),
          backgroundColor: ZveltTokens.error));
      return;
    }
    setState(() => _saving = true);
    try {
      await ProfileService().updateProfile(displayName: name);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
    } on ProfileUpdateException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message), backgroundColor: ZveltTokens.error));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Update failed. Try again.'),
          backgroundColor: ZveltTokens.error));
    }
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: ZType.bodyS
                .copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'Edit Profile',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Name'),
          TextField(
            controller: _nameCtrl,
            maxLength: 40,
            style:
                ZType.bodyM.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
            decoration:
                const InputDecoration(hintText: 'Your name', counterText: ''),
          ),
          const SizedBox(height: 16),
          _label('Email'),
          // Email changes aren't supported by PATCH /v1/me/profile — render
          // read-only with a subtle note instead of pretending to save it.
          TextField(
            controller: _emailCtrl,
            readOnly: true,
            style: ZType.bodyM.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ZveltTokens.text3),
            decoration: const InputDecoration(hintText: 'you@email.com'),
          ),
          const SizedBox(height: 6),
          Text("Email can't be changed yet.",
              style: ZType.bodyS
                  .copyWith(fontSize: 11.5, color: ZveltTokens.text3)),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save changes'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// sheetAccount — Account (HTML 1267-1283)
// ─────────────────────────────────────────────────────────────────────────────

class _AccountSheet extends StatelessWidget {
  const _AccountSheet({
    required this.name,
    required this.email,
    required this.memberSince,
    required this.onEditProfile,
    required this.onLogout,
  });
  final String name;
  final String email;
  final DateTime? memberSince;
  final VoidCallback onEditProfile;
  final Future<void> Function() onLogout;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  Widget _infoRow(String label, String value, {bool accent = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        decoration: BoxDecoration(
          gradient: ZveltTokens.surface2Grad,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: ZveltTokens.border),
        ),
        child: Row(
          children: [
            Text(label,
                style: ZType.bodyS
                    .copyWith(fontSize: 12.5, fontWeight: FontWeight.w600)),
            const Spacer(),
            Flexible(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: accent
                      ? ZType.bodyM.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: ZveltTokens.brand)
                      : ZType.bodyM.copyWith(
                          fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final since = memberSince;
    return _SheetShell(
      title: 'Account',
      maxHeightFactor: 0.9,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _infoRow('Name', name),
          if (email.isNotEmpty) _infoRow('Email', email),
          // 'Member since' only when the backend exposes a creation date —
          // never fabricate one.
          if (since != null)
            _infoRow(
                'Member since', '${_months[since.month - 1]} ${since.year}'),
          _infoRow('Current plan', 'Free', accent: true),
          const SizedBox(height: 6),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                onEditProfile();
              },
              style: FilledButton.styleFrom(
                backgroundColor: ZveltTokens.chip,
                foregroundColor: ZveltTokens.text,
                side: BorderSide(color: ZveltTokens.borderStrong),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                textStyle: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
              child: const Text('Edit profile'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                onLogout();
              },
              style: FilledButton.styleFrom(
                backgroundColor: ZveltTokens.error.withValues(alpha: 0.1),
                foregroundColor: ZveltTokens.error,
                side: BorderSide(
                    color: ZveltTokens.error.withValues(alpha: 0.35)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                textStyle: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
              child: const Text('Sign out'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumSheet extends StatefulWidget {
  const _PremiumSheet();

  @override
  State<_PremiumSheet> createState() => _PremiumSheetState();
}

class _PremiumSheetState extends State<_PremiumSheet> {
  bool _annual = true; // prototype default: annual selected

  static const _benefits = [
    'Unlimited goal-based AI programs',
    'AI meal plans for your diet',
    'Advanced progress analytics',
    'Unlimited challenges & custom fasting',
  ];

  Widget _priceCard({
    required bool selected,
    required VoidCallback onTap,
    required String label,
    required String price,
    required String sub,
    bool saveBadge = false,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZveltTokens.rControl),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? ZveltTokens.brand.withValues(alpha: 0.12)
                : ZveltTokens.chip,
            borderRadius: BorderRadius.circular(ZveltTokens.rControl),
            border: selected
                ? Border.all(color: ZveltTokens.brand, width: 1.5)
                : Border.all(color: ZveltTokens.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(label,
                      style: ZType.bodyS.copyWith(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                  if (saveBadge) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: ZveltTokens.success.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                            color:
                                ZveltTokens.success.withValues(alpha: 0.3)),
                      ),
                      child: Text('SAVE 30%',
                          style: ZType.bodyS.copyWith(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: ZveltTokens.success)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(price,
                  style: ZType.h3.copyWith(fontSize: 22)),
              const SizedBox(height: 1),
              Text(sub,
                  style: ZType.bodyS.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: ZveltTokens.text3)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'ZVELT Premium',
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: ZveltTokens.gradAccent,
          borderRadius: BorderRadius.circular(13),
          boxShadow: ZveltTokens.glowSm,
        ),
        child:
            const Icon(AppIcons.crown, size: 21, color: ZveltTokens.onBrand),
      ),
      maxHeightFactor: 0.92,
      footer: SizedBox(
        width: double.infinity,
        height: 50,
        child: FilledButton(
          onPressed: () {
            // Purchases aren't wired yet (RevenueCat pending) — be honest.
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('Coming soon — purchases open at launch'),
            ));
          },
          child: Text(_annual
              ? 'Start free trial · then \$6.99/mo'
              : 'Start free trial · then \$9.99/mo'),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Benefits first — accent-tinted check chips (prototype order).
          for (final b in _benefits)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ZveltTokens.brandTint,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Icon(AppIcons.check,
                        size: 13, color: ZveltTokens.brand),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(b,
                        style: ZType.bodyM.copyWith(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          // IntrinsicHeight bounds the stretch — a bare stretch Row inside a
          // scrollable blanks release screens (flutter-layout-release-blank).
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _priceCard(
                  selected: !_annual,
                  onTap: () => setState(() => _annual = false),
                  label: 'Monthly',
                  price: '\$9.99',
                  sub: 'per month',
                ),
                const SizedBox(width: 10),
                _priceCard(
                  selected: _annual,
                  onTap: () => setState(() => _annual = true),
                  label: 'Annual',
                  price: '\$6.99',
                  sub: 'per month, billed yearly',
                  saveBadge: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// sheetHelp — QUICK ANSWERS + SEND FEEDBACK (HTML 1284-1300)
// ─────────────────────────────────────────────────────────────────────────────

class _HelpSheet extends StatefulWidget {
  const _HelpSheet();

  @override
  State<_HelpSheet> createState() => _HelpSheetState();
}

class _HelpSheetState extends State<_HelpSheet> {
  final _feedbackCtrl = TextEditingController();
  final _expanded = <bool>[false, false];

  static const _faqs = [
    (
      'How does the AI Coach work?',
      'Tell it a goal and it builds a progressive multi-week program that drops into Plan Your Day.'
    ),
    (
      'Does run tracking need a watch?',
      'No — your phone GPS covers the live map, distance and pace. A watch or strap adds heart rate.'
    ),
  ];

  @override
  void dispose() {
    _feedbackCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _feedbackCtrl.text.trim();
    if (body.isEmpty) return; // never submit empty
    final info = await PackageInfo.fromPlatform();
    final text =
        '[ZVELT Feedback] v${info.version}+${info.buildNumber}\n\n$body';
    if (!mounted) return;
    Navigator.of(context).pop();
    // Share sheet — the user picks email/messaging; nothing is invented.
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Widget _eyebrow(String text) => Text(text,
      style: ZType.eyebrow.copyWith(color: ZveltTokens.text3));

  Widget _faqCard(int index) {
    final (q, a) = _faqs[index];
    final open = _expanded[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => setState(() => _expanded[index] = !open),
        borderRadius: BorderRadius.circular(ZveltTokens.rChip),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          decoration: BoxDecoration(
            gradient: ZveltTokens.surface2Grad,
            borderRadius: BorderRadius.circular(ZveltTokens.rChip),
            border: Border.all(color: ZveltTokens.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(q,
                        style: ZType.bodyM.copyWith(
                            fontSize: 13.5, fontWeight: FontWeight.w700)),
                  ),
                  Icon(
                      open
                          ? AppIcons.angle_small_up
                          : AppIcons.angle_small_down,
                      size: 16,
                      color: ZveltTokens.text3),
                ],
              ),
              if (open) ...[
                const SizedBox(height: 9),
                Text(a, style: ZType.bodyS.copyWith(fontSize: 12.5)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'Help & Feedback',
      maxHeightFactor: 0.9,
      footer: SizedBox(
        width: double.infinity,
        height: 50,
        child: FilledButton(
          onPressed: _send,
          child: const Text('Send feedback'),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow('QUICK ANSWERS'),
          const SizedBox(height: 9),
          _faqCard(0),
          _faqCard(1),
          const SizedBox(height: 16),
          _eyebrow('SEND FEEDBACK'),
          const SizedBox(height: 9),
          TextField(
            controller: _feedbackCtrl,
            minLines: 3,
            maxLines: 5,
            style: ZType.bodyM.copyWith(fontSize: 13.5),
            decoration: const InputDecoration(
                hintText: 'Tell us what would make ZVELT better…'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// sheetFeature / sheetBug — subtitle + exact placeholders + CTA labels
// (HTML 1320-1342); bug variant shows the "App version attached" info chip.
// ─────────────────────────────────────────────────────────────────────────────

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet({
    required this.title,
    required this.subtitle,
    required this.hint,
    required this.ctaLabel,
    required this.subject,
    this.showVersionChip = false,
  });
  final String title;
  final String subtitle;
  final String hint;
  final String ctaLabel;
  final String subject;
  final bool showVersionChip;

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _ctrl = TextEditingController();
  String _version = '';

  @override
  void initState() {
    super.initState();
    if (widget.showVersionChip) {
      PackageInfo.fromPlatform().then((info) {
        if (mounted) setState(() => _version = info.version);
      });
    }
  }

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
      subtitle: widget.subtitle,
      child: Column(
        children: [
          TextField(
            controller: _ctrl,
            maxLines: 5,
            minLines: 4,
            style: ZType.bodyM.copyWith(fontSize: 13.5),
            decoration: InputDecoration(hintText: widget.hint),
          ),
          if (widget.showVersionChip) ...[
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                gradient: ZveltTokens.surface2Grad,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: ZveltTokens.border),
              ),
              child: Row(
                children: [
                  Icon(AppIcons.exclamation,
                      size: 16, color: ZveltTokens.text2),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        'App version ${_version.isEmpty ? '…' : _version} attached automatically',
                        style: ZType.bodyS.copyWith(fontSize: 11.5)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: _send,
              child: Text(widget.ctaLabel),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// sheetAbout — centered logo + tagline + link rows (HTML 1301-1319)
// ─────────────────────────────────────────────────────────────────────────────

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
      if (mounted) setState(() => _version = info.version);
    });
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {/* best-effort */}
  }

  Widget _linkRow(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(
            gradient: ZveltTokens.surface2Grad,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: ZveltTokens.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: ZType.bodyM.copyWith(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
              Icon(AppIcons.angle_small_right,
                  size: 17, color: ZveltTokens.text3),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'About ZVELT',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 2),
          Column(
            children: [
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: ZveltTokens.gradAccent,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: ZveltTokens.glowMd,
                ),
                child: const Icon(AppIcons.star,
                    size: 30, color: ZveltTokens.onBrand),
              ),
              const SizedBox(height: 14),
              Text('ZVELT',
                  style: ZType.h3
                      .copyWith(fontSize: 21, letterSpacing: 3.4)),
              const SizedBox(height: 4),
              Text(_version.isEmpty ? '…' : 'Version $_version',
                  style: ZType.bodyS.copyWith(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Your AI-assisted coach for training, nutrition and recovery — calm, premium and athlete-built.',
                  textAlign: TextAlign.center,
                  style: ZType.bodyS.copyWith(fontSize: 13.5, height: 1.55),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _linkRow('Privacy Policy', () => _open('https://zvelt.app/privacy')),
          _linkRow('Terms of Service', () => _open('https://zvelt.app/terms')),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sheet chrome: grabber + (leading?) title/subtitle row with ✕,
// optional scrollable body (maxHeightFactor) and pinned footer.
// ─────────────────────────────────────────────────────────────────────────────

class _SheetShell extends StatelessWidget {
  const _SheetShell({
    required this.title,
    this.subtitle,
    this.leading,
    required this.child,
    this.footer,
    this.maxHeightFactor,
  });
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget child;

  /// Rendered below the (scrollable) body, pinned — e.g. a CTA button.
  final Widget? footer;

  /// When set, the sheet caps at this fraction of the screen height and the
  /// body scrolls (prototype max-height 88–92%).
  final double? maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    Widget body = child;
    if (maxHeightFactor != null) {
      body = Flexible(child: SingleChildScrollView(child: child));
    }
    Widget column = Column(
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
            if (leading != null) ...[leading!, const SizedBox(width: 11)],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: ZType.h4.copyWith(fontSize: 19)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: ZType.bodyS.copyWith(fontSize: 12)),
                  ],
                ],
              ),
            ),
            InkWell(
              onTap: () => Navigator.of(context).pop(),
              customBorder: const CircleBorder(),
              child: Icon(AppIcons.cross_small,
                  size: 22, color: ZveltTokens.text2),
            ),
          ],
        ),
        const SizedBox(height: 16),
        body,
        if (footer != null) ...[const SizedBox(height: 14), footer!],
      ],
    );
    if (maxHeightFactor != null) {
      column = ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor!),
        child: column,
      );
    }
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
        child: column,
      ),
    );
  }
}
