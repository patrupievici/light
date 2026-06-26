import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';
import '../../services/training_profile_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';
import '../splash_screen.dart';
import 'onboarding_keys.dart';

/// Light onboarding: Splash → (silent guest sign-in, no login screen) → 3 short
/// questions (Goal · Experience · Days/week, skippable) → into the app. The user
/// can later save their account from Settings; until then they run as an
/// anonymous guest so backend calls still have a session.
class LightOnboardingFlow extends StatefulWidget {
  const LightOnboardingFlow({
    super.key,
    required this.completionKey,
    required this.startAuthenticated,
    required this.onComplete,
  });

  /// Per-user pref key the gate already derived (may be the `_guest` key if the
  /// user is signing up inside this flow — we re-derive the real key on finish).
  final String completionKey;
  final bool startAuthenticated;
  final VoidCallback onComplete;

  @override
  State<LightOnboardingFlow> createState() => _LightOnboardingFlowState();
}

enum _Phase { splash, settingUp, goal, experience, days, finishing }

class _LightOnboardingFlowState extends State<LightOnboardingFlow> {
  _Phase _phase = _Phase.splash;

  String? _goal; // backend primaryGoal enum
  String? _level; // beginner | intermediate | advanced
  int? _days;

  void _afterSplash() {
    if (widget.startAuthenticated) {
      setState(() => _phase = _Phase.goal);
    } else {
      _createGuestThenContinue();
    }
  }

  /// No login screen: silently spin up an anonymous guest account so the user
  /// has a backend session, then drop into the questions. If it fails (offline)
  /// we still continue — the questions + app degrade gracefully without a token.
  Future<void> _createGuestThenContinue() async {
    setState(() => _phase = _Phase.settingUp);
    try {
      await AuthService().continueAsGuest();
    } catch (_) {/* offline — let them in anyway */}
    if (mounted) setState(() => _phase = _Phase.goal);
  }

  Future<void> _finish() async {
    setState(() => _phase = _Phase.finishing);

    // Best-effort server sync — never block entry on the network (offline-first).
    try {
      await TrainingProfileService().patch({
        if (_goal != null) 'primaryGoal': _goal,
        if (_level != null) 'trainingLevel': _level, // backend field is trainingLevel
        if (_days != null) 'daysPerWeek': _days,
        'onboardingCompleted': true,
      });
    } catch (_) {/* fall through — local flag still lets the user in */}

    // Mark onboarding complete for the REAL (post-login) user id, mirroring
    // AuthGate._key(). A guest who signed up inside the flow has a different id
    // than the gate's `completionKey`, so derive it fresh here too.
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = await AuthService().getStoredUserId() ?? '';
      final realKey = '${kOnboarding2CompletedKey}_${uid.isEmpty ? 'guest' : uid}';
      await prefs.setBool(realKey, true);
      await prefs.setBool(widget.completionKey, true);
    } catch (_) {}

    if (mounted) widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _Phase.splash:
        return SplashScreen(onDone: _afterSplash);
      case _Phase.settingUp:
        return Scaffold(
          backgroundColor: ZveltTokens.bg,
          body: const Center(child: CircularProgressIndicator(color: ZveltTokens.brand)),
        );
      case _Phase.goal:
        return _QuestionScreen(
          step: 0,
          title: "What's your goal?",
          subtitle: 'This helps us personalize your experience.',
          options: const [
            _Opt('hypertrophy', 'Build Muscle', AppIcons.gym),
            _Opt('fat_loss', 'Lose Fat', AppIcons.flame),
            _Opt('strength', 'Get Stronger', AppIcons.chart_line_up),
            _Opt('maintenance', 'Stay Consistent', AppIcons.check),
          ],
          selected: _goal,
          onSelect: (v) => setState(() => _goal = v),
          ctaLabel: 'Next',
          onCta: _goal == null ? null : () => setState(() => _phase = _Phase.experience),
          onBack: null,
          onSkip: _finish,
        );
      case _Phase.experience:
        return _QuestionScreen(
          step: 1,
          title: 'Training level',
          subtitle: 'Be honest — we scale the plan to you.',
          options: const [
            _Opt('beginner', 'Beginner', AppIcons.user),
            _Opt('intermediate', 'Intermediate', AppIcons.user),
            _Opt('advanced', 'Advanced', AppIcons.user),
          ],
          selected: _level,
          onSelect: (v) => setState(() => _level = v),
          ctaLabel: 'Next',
          onCta: _level == null ? null : () => setState(() => _phase = _Phase.days),
          onBack: () => setState(() => _phase = _Phase.goal),
          onSkip: _finish,
        );
      case _Phase.days:
        return _QuestionScreen(
          step: 2,
          title: 'How many days per week?',
          subtitle: 'Pick a number you can actually keep.',
          options: const [
            _Opt('2', '2 days / week', null),
            _Opt('3', '3 days / week', null),
            _Opt('4', '4 days / week', null),
            _Opt('5', '5 days / week', null),
            _Opt('6', '6 days / week', null),
          ],
          selected: _days?.toString(),
          onSelect: (v) => setState(() => _days = int.tryParse(v)),
          ctaLabel: 'Create my plan',
          onCta: _days == null ? null : _finish,
          onBack: () => setState(() => _phase = _Phase.experience),
          onSkip: _finish,
        );
      case _Phase.finishing:
        return Scaffold(
          backgroundColor: ZveltTokens.bg,
          body: const Center(child: CircularProgressIndicator(color: ZveltTokens.brand)),
        );
    }
  }
}

class _Opt {
  const _Opt(this.value, this.label, this.icon);
  final String value;
  final String label;
  final IconData? icon;
}

class _QuestionScreen extends StatelessWidget {
  const _QuestionScreen({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.options,
    required this.selected,
    required this.onSelect,
    required this.ctaLabel,
    required this.onCta,
    this.onBack,
    this.onSkip,
  });

  final int step; // 0..2
  final String title;
  final String subtitle;
  final List<_Opt> options;
  final String? selected;
  final ValueChanged<String> onSelect;
  final String ctaLabel;
  final VoidCallback? onCta;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              ZveltTokens.s5, ZveltTokens.s3, ZveltTokens.s5, ZveltTokens.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: back + progress dots
              Row(
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: onBack == null
                        ? null
                        : Material(
                            color: Colors.transparent,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: onBack,
                              child: Icon(AppIcons.arrow_small_left,
                                  color: ZveltTokens.text2),
                            ),
                          ),
                  ),
                  const Spacer(),
                  for (var i = 0; i < 3; i++) ...[
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: i == step ? 22 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i <= step ? ZveltTokens.brand : ZveltTokens.surface3,
                        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                      ),
                    ),
                    if (i < 2) const SizedBox(width: 6),
                  ],
                  const Spacer(),
                  SizedBox(
                    width: 56,
                    height: 44,
                    child: onSkip == null
                        ? null
                        : Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: onSkip,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s2),
                              ),
                              child: Text('Skip',
                                  style: ZType.bodyM.copyWith(color: ZveltTokens.text2)),
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: ZveltTokens.s8),
              Text(title, style: ZType.displayM),
              const SizedBox(height: ZveltTokens.s2),
              Text(subtitle, style: ZType.bodyM.copyWith(color: ZveltTokens.text2)),
              const SizedBox(height: ZveltTokens.s6),
              Expanded(
                child: ListView.separated(
                  itemCount: options.length,
                  separatorBuilder: (_, __) => const SizedBox(height: ZveltTokens.s3),
                  itemBuilder: (_, i) {
                    final opt = options[i];
                    final sel = opt.value == selected;
                    return _OptionCard(
                      opt: opt,
                      selected: sel,
                      onTap: () => onSelect(opt.value),
                    );
                  },
                ),
              ),
              const SizedBox(height: ZveltTokens.s4),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: ZveltTokens.brand,
                    foregroundColor: ZveltTokens.onBrand,
                    disabledBackgroundColor: ZveltTokens.surface3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                    ),
                  ),
                  onPressed: onCta,
                  child: Text(ctaLabel,
                      style: ZType.h4.copyWith(color: ZveltTokens.onBrand)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.opt, required this.selected, required this.onTap});

  final _Opt opt;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? ZveltTokens.brandTint : ZveltTokens.surface,
      borderRadius: BorderRadius.circular(ZveltTokens.rLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: ZveltTokens.s4, vertical: ZveltTokens.s4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ZveltTokens.rLg),
            border: Border.all(
              color: selected ? ZveltTokens.brand : ZveltTokens.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              if (opt.icon != null) ...[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selected ? ZveltTokens.brand : ZveltTokens.bg2,
                    borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                  ),
                  child: Icon(opt.icon,
                      size: 18,
                      color: selected ? ZveltTokens.onBrand : ZveltTokens.text2),
                ),
                const SizedBox(width: ZveltTokens.s3),
              ],
              Expanded(
                child: Text(
                  opt.label,
                  style: ZType.h4.copyWith(
                    color: selected ? ZveltTokens.brandDeep : ZveltTokens.text,
                  ),
                ),
              ),
              if (selected)
                const Icon(AppIcons.check, size: 20, color: ZveltTokens.brand),
            ],
          ),
        ),
      ),
    );
  }
}
