// Zvelt — Onboarding 2 (the new 29-screen flow). FOUNDATION.
//
// This is a faithful Flutter port of Razvan's `_onb` design bundle
// (onboarding-kit.jsx + onboarding-app.jsx + onboarding-design-system.md),
// built on ZveltTokens / ZType. It is a DROP-IN replacement for the legacy
// onboarding routers: [NewOnboardingFlow] keeps the same public constructor
// shape ({completionKey, onComplete, startAuthenticated}) so main.dart can be
// re-wired by a human without touching this file.
//
// Architecture (mirrors the JSX bundle 1:1):
//   - _OnbData          → the handoff's `data` object (collected answers +
//                         toJson/fromJson for resume + toPayload()).
//   - Kit widgets       → OnbShell / OnbProgress / SelectCard / OnbHead /
//                         OnbField / OnbPrimaryButton / OnbTileIcon / OnbEyebrow.
//   - NewOnboardingFlow → the 29-screen router (onboarding-app.jsx's
//                         OnboardingApp), with per-user persistence, next/back,
//                         the auth-aware start index, and the completion logic.
//
// The 29 screens are split across 5 `part` files (one per act). This file
// holds everything shared; the screens live in the parts and receive an
// [OnbScreenArgs] bundle (next / back / data / setData / authed).
//
// IMPORTANT CONTRACT NOTES (see the task brief):
//   - Auth lives INSIDE the flow at ScrAuth (index 1, screen 2 — right after
//     the splash). When the user already has a token (startAuthenticated ==
//     true), the router SKIPS screens 0–4 and starts at ScrProfile (index 5).
//   - The plan prewarm fires right after the goal screen (ScrGoal → next).
//   - The full backend sync is kicked at ScrBuilding (index 10) and AWAITED
//     (with an ~8s grace) at ScrEnter (index 28) before completing.
//   - completeOnboarding never throws — failures still complete the flow.

import 'dart:async';
import 'package:zvelt_app/theme/app_icons.dart';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

// NOTE: the auth (ScrAuth), notifications (ScrNotifications) and health
// (ScrConnect) screen-fleshing agents will add the imports they need here —
// e.g. `package:firebase_messaging/firebase_messaging.dart`,
// `../../services/auth_service.dart`, `../../services/health_service.dart`.
// The notifications agent has wired `firebase_messaging` + `kIsWeb` above for
// the REAL FCM permission request on ScrNotifications.
// The auth agent has wired `flutter_svg` + `google_sign_in` above and the
// AuthService / auth-error mapper below for the FUNCTIONAL ScrAuth screen.
import '../../config/platform_info.dart' show isAndroid;
import '../../l10n/auth_error_messages.dart';
import '../../services/_crash_reporter.dart';
import '../../services/auth_service.dart';
import '../../services/health_capability_service.dart';
import '../../services/health_service.dart';
import '../../services/onboarding_service.dart';
import '../../services/profile_service.dart';
import '../../theme/zvelt_tokens.dart';

part 'onboarding2_intro.dart';
part 'onboarding2_personalization.dart';
part 'onboarding2_discovery.dart';
part 'onboarding2_community.dart';
part 'onboarding2_launch.dart';

// ═════════════════════════════════════════════════════════════════════════════
// PUBLIC CONTRACT — completion key constant
// ═════════════════════════════════════════════════════════════════════════════

/// Default SharedPreferences key flipped true when onboarding 2 finishes.
/// The router stores per-user completion under the [completionKey] it is given,
/// so this is only the conventional default the wiring layer can pass in.
const String kOnboarding2CompletedKey = 'onboarding2_completed';

// Resume keys (suffixed per-user with the completionKey so two accounts on one
// device don't clobber each other's in-progress answers).
const String _kStepKey = 'onb2_step';
const String _kDataKey = 'onb2_data';

// ═════════════════════════════════════════════════════════════════════════════
// LABEL / ENUM MAPS — mirror the design bundle's label maps + backend enums
// ═════════════════════════════════════════════════════════════════════════════

/// Goal code → human label (echoed back on Commit / Summary screens).
const Map<String, String> kGoalLabel = {
  'muscle': 'Build muscle',
  'fat': 'Lose fat',
  'strong': 'Get stronger',
  'health': 'Improve health',
};

/// Goal code → backend `primaryGoal` enum.
const Map<String, String> kGoalEnum = {
  'muscle': 'hypertrophy',
  'fat': 'fat_loss',
  'strong': 'strength',
  'health': 'maintenance',
};

const Map<String, String> kLevelLabel = {
  'beg': 'Beginner',
  'int': 'Intermediate',
  'adv': 'Advanced',
};
const Map<String, String> kLevelEnum = {
  'beg': 'beginner',
  'int': 'intermediate',
  'adv': 'advanced',
};

const Map<String, String> kDietLabel = {
  'balanced': 'Balanced',
  'protein': 'High protein',
  'plant': 'Plant-based',
  'lowcarb': 'Low carb',
};

/// Diet code → backend dietary-restriction tag (null = no restriction).
const Map<String, String?> kDietTag = {
  'balanced': null,
  'protein': 'high_protein',
  'plant': 'plant_based',
  'lowcarb': 'low_carb',
};

// ═════════════════════════════════════════════════════════════════════════════
// DATA MODEL — the handoff's `data` object
// ═════════════════════════════════════════════════════════════════════════════

/// All answers collected through the flow plus the transient sync handle.
///
/// Field codes match the design bundle's `localStorage['zvelt_onb_data']`
/// contract. [toPayload] builds the EXISTING [OnboardingPayload] so the same
/// backend wiring (`OnboardingService.completeOnboarding`) is reused unchanged.
class OnbData {
  String name = '';
  String username = '';

  /// 'muscle' | 'fat' | 'strong' | 'health'
  String? goal;

  /// Optional free-text goal — feeds the deterministic workout engine via
  /// the training-profile `onboardingGoalText`.
  String goalText = '';

  /// 'beg' | 'int' | 'adv'
  String? level;

  /// 'f' | 'm' | 'x'
  String? sex;
  String age = '';
  String height = '';
  String weight = '';

  /// 'balanced' | 'protein' | 'plant' | 'lowcarb'
  String? diet;

  // ── Transient (NOT persisted to JSON) ──
  /// True once the backend sync has succeeded (set at ScrEnter or ScrBuilding).
  bool synced = false;

  /// In-flight backend sync started at ScrBuilding and awaited at ScrEnter.
  Future<OnboardingResult>? syncFuture;

  /// Best label for the user's goal — prefers their free text, else the picker
  /// label. Used for the plan prewarm + Commit/Summary echoes.
  String get effectiveGoalText =>
      goalText.trim().isNotEmpty ? goalText.trim() : (kGoalLabel[goal] ?? '');

  Map<String, dynamic> toJson() => {
        'name': name,
        'username': username,
        'goal': goal,
        'goalText': goalText,
        'level': level,
        'sex': sex,
        'age': age,
        'height': height,
        'weight': weight,
        'diet': diet,
      };

  /// Inverse of [toJson] — restore on flow entry. Tolerant of missing keys.
  void fromJson(Map<String, dynamic> j) {
    name = j['name'] as String? ?? '';
    username = j['username'] as String? ?? '';
    goal = j['goal'] as String?;
    goalText = j['goalText'] as String? ?? '';
    level = j['level'] as String?;
    sex = j['sex'] as String?;
    age = j['age'] as String? ?? '';
    height = j['height'] as String? ?? '';
    weight = j['weight'] as String? ?? '';
    diet = j['diet'] as String?;
  }

  /// Build the EXISTING backend payload. units is always 'metric' per contract.
  OnboardingPayload toPayload() => OnboardingPayload(
        name: name.trim().isEmpty ? null : name.trim(),
        goal: kGoalEnum[goal],
        units: 'metric',
        sex: sex,
        age: double.tryParse(age),
        height: double.tryParse(height),
        weight: double.tryParse(weight),
        experience: kLevelEnum[level],
        aiVision: effectiveGoalText.isEmpty ? null : effectiveGoalText,
        dietary: [
          if (kDietTag[diet] != null) kDietTag[diet]!,
        ],
      );
}

// ═════════════════════════════════════════════════════════════════════════════
// SCREEN ARGS — passed to every screen (the JSX {next, back, data, setData})
// ═════════════════════════════════════════════════════════════════════════════

/// Bundle handed to every screen. Mirrors the JSX router's per-screen props.
///
///   - [next]      → advance one screen (also persists + completes at the end).
///   - [back]      → go back one screen (no-op at index 0 / skipped intro).
///   - [data]      → the shared, mutable [OnbData].
///   - [setData]   → mutate [data] inside a callback + persist (use this so a
///                   resume snapshot is written on every answer change).
///   - [authed]    → true when the user is already authenticated (intro+auth
///                   screens were skipped). Lets ScrEnter etc. branch copy.
class OnbScreenArgs {
  const OnbScreenArgs({
    required this.next,
    required this.back,
    required this.data,
    required this.setData,
    required this.authed,
    required this.complete,
  });

  final VoidCallback next;
  final VoidCallback back;
  final OnbData data;

  /// Mutate [data] inside [fn], rebuild the flow, and persist the snapshot.
  final void Function(void Function() fn) setData;

  final bool authed;

  /// Exit onboarding immediately (skip remaining screens) — used by ScrAuth
  /// when a RETURNING user logs in and has already completed onboarding.
  final VoidCallback complete;
}

// ═════════════════════════════════════════════════════════════════════════════
// ROOT ROUTER — the handoff's onboarding-app.jsx (29 screens)
// ═════════════════════════════════════════════════════════════════════════════

/// Drop-in onboarding root. Constructor shape is intentionally identical to the
/// legacy onboarding flows so main.dart wiring is unchanged:
///
/// ```dart
/// NewOnboardingFlow(
///   completionKey: '$kOnboarding2CompletedKey-$userId',
///   onComplete: () => /* route into the app */,
///   startAuthenticated: hasToken,
/// )
/// ```
class NewOnboardingFlow extends StatefulWidget {
  const NewOnboardingFlow({
    super.key,
    required this.completionKey,
    required this.onComplete,
    this.startAuthenticated = true,
  });

  /// Per-user SharedPreferences key flipped true on completion.
  final String completionKey;

  /// Invoked exactly once, after completion bookkeeping, to leave the flow.
  final VoidCallback onComplete;

  /// When true (user already has a token), skip the intro + auth screens
  /// (indices 0–4) and start at ScrProfile (index 5).
  final bool startAuthenticated;

  @override
  State<NewOnboardingFlow> createState() => _NewOnboardingFlowState();
}

class _NewOnboardingFlowState extends State<NewOnboardingFlow> {
  /// Total screen count (the SCREENS[] list below).
  static const int total = 29;

  /// First screen the user sees when they already have a token: ScrProfile.
  static const int _authedStart = 5;

  final OnbData _data = OnbData();
  int _step = 0;
  bool _restored = false;
  bool _finishing = false;

  String _keyed(String base) => '${base}_${widget.completionKey}';

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyed(_kDataKey));
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) _data.fromJson(decoded);
      }
      final saved = prefs.getInt(_keyed(_kStepKey));
      if (saved != null) {
        _step = saved.clamp(0, total - 1);
      } else if (widget.startAuthenticated) {
        // No resume snapshot but already signed in → skip intro + auth.
        _step = _authedStart;
      }
      // Defense in depth: never strand an authed user inside the auth act even
      // if an old snapshot put them there.
      if (widget.startAuthenticated && _step < _authedStart) {
        _step = _authedStart;
      }
    } catch (e, st) {
      reportError(e, st, reason: 'onb2:restore');
      if (widget.startAuthenticated) _step = _authedStart;
    }
    if (mounted) setState(() => _restored = true);
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyed(_kStepKey), _step);
      await prefs.setString(_keyed(_kDataKey), jsonEncode(_data.toJson()));
    } catch (_) {
      // Best-effort: resume is a convenience, not a correctness requirement.
    }
  }

  void _next() {
    HapticFeedback.lightImpact();
    if (_step >= total - 1) {
      _finish();
      return;
    }
    setState(() => _step++);
    _persist();
  }

  void _back() {
    if (_step <= 0) return;
    // Authed users can't reverse into the skipped auth act.
    if (widget.startAuthenticated && _step <= _authedStart) return;
    HapticFeedback.selectionClick();
    setState(() => _step--);
    _persist();
  }

  void _setData(void Function() fn) {
    setState(fn);
    _persist();
  }

  /// Fire the plan prewarm as soon as we know the goal (called from ScrGoal).
  /// 22+ screens of headroom before completion, so DeepSeek is usually done.
  void _prewarm() {
    final text = _data.effectiveGoalText;
    if (text.isEmpty) return;
    OnboardingService().prewarmPlanFromGoal(
      goalText: text,
      primaryGoal: kGoalEnum[_data.goal],
    );
  }

  /// Kick the real backend sync (called from ScrBuilding). Stored on [_data]
  /// so ScrEnter can await it. Idempotent — only fires once.
  void _startSync() {
    if (_data.syncFuture != null || _data.synced) return;
    _data.syncFuture = OnboardingService().completeOnboarding(_data.toPayload());
    // Patch the username separately (handles 409 USERNAME_TAKEN gracefully).
    _patchUsername();
  }

  /// PATCH the chosen username on its own so a 409 (already taken) doesn't fail
  /// the whole profile write. Best-effort and non-fatal.
  Future<void> _patchUsername() async {
    final uname = _data.username.trim();
    if (uname.isEmpty) return;
    try {
      await ProfileService().updateProfile(username: uname);
    } on ProfileUpdateException catch (e) {
      // 409 / USERNAME_TAKEN → keep going; the user keeps their auto handle.
      if (e.statusCode != 409 && e.code != 'USERNAME_TAKEN') {
        reportError(e, StackTrace.current, reason: 'onb2:patch-username');
      }
    } catch (e, st) {
      reportError(e, st, reason: 'onb2:patch-username');
    }
  }

  /// Final completion. Awaits the in-flight sync with an ~8s grace, falls back
  /// to a fresh completeOnboarding, flips the per-user completion flag, clears
  /// resume keys, then calls onComplete(). NEVER throws.
  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      final f = _data.syncFuture;
      if (f != null && !_data.synced) {
        try {
          final r = await f.timeout(const Duration(seconds: 8));
          _data.synced = r.profileSynced;
        } catch (_) {
          // Timeout / error → fall through to the explicit fallback below.
        }
      }
      if (!_data.synced) {
        try {
          final result =
              await OnboardingService().completeOnboarding(_data.toPayload());
          _data.synced = result.isSuccess;
          if (!result.isSuccess) {
            reportError(
              Exception('Onboarding2 sync incomplete: ${result.errors.join("; ")}'),
              StackTrace.current,
              reason: 'onb2:finish-fallback',
            );
          }
        } catch (e, st) {
          reportError(e, st, reason: 'onb2:finish-fallback');
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(widget.completionKey, true);
      // Also set the per-user key from the now-known (post-auth) userId, so
      // AuthGate — which reads 'onboarding2_completed_<userId>' — sees
      // completion even when a NEW user authenticated INSIDE the flow (at
      // which point AuthGate could only have passed the 'guest' key).
      final uid = await AuthService().getStoredUserId();
      await prefs.setBool(
        '${kOnboarding2CompletedKey}_${(uid == null || uid.isEmpty) ? 'guest' : uid}',
        true,
      );
      await prefs.remove(_keyed(_kStepKey));
      await prefs.remove(_keyed(_kDataKey));
    } catch (e, st) {
      // Completion bookkeeping must never trap the user in the flow.
      reportError(e, st, reason: 'onb2:finish');
    } finally {
      if (mounted) {
        setState(() => _finishing = false);
        widget.onComplete();
      }
    }
  }

  /// Returning user who already onboarded → skip the rest of the flow, clear
  /// scratch state, and exit to the app. No profile sync (they already have one).
  Future<void> _completeEarly() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyed(_kStepKey));
      await prefs.remove(_keyed(_kDataKey));
    } catch (_) {}
    if (mounted) {
      setState(() => _finishing = false);
      widget.onComplete();
    }
  }

  OnbScreenArgs get _args => OnbScreenArgs(
        next: _next,
        back: _back,
        data: _data,
        setData: _setData,
        authed: widget.startAuthenticated,
        complete: _completeEarly,
      );

  @override
  Widget build(BuildContext context) {
    if (!_restored) {
      return Scaffold(
        backgroundColor: ZveltTokens.bg,
        body: const Center(
          child: CircularProgressIndicator(
              color: ZveltTokens.brand, strokeWidth: 2),
        ),
      );
    }
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
                    begin: const Offset(0, 0.015), end: Offset.zero)
                .animate(anim),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(_step), child: _screen()),
      ),
    );
  }

  /// The SCREENS[] order (onboarding-app.jsx). Index == screen number.
  Widget _screen() {
    final a = _args;
    switch (_step) {
      // ── ACT 1 · Hook & Sign-in (0–4) ────────────────────────────────
      // Order mirrors the design deck: Splash → Auth → Problem → Promise
      // → Social proof. Sign-in is screen 2 (index 1), right after the splash;
      // both the splash and the auth screen carry the Zvelt wordmark.
      case 0:
        return ScrSplash(args: a);
      case 1:
        return ScrAuth(args: a);
      case 2:
        return ScrProblem(args: a);
      case 3:
        return ScrPromise(args: a);
      case 4:
        return ScrSocialProof(args: a);
      // ── ACT 2 · Personalization (5–10), progress n/6 ────────────────
      case 5:
        return ScrProfile(args: a);
      case 6:
        // AI starts HERE: prewarm the plan on the way out of the goal screen.
        return ScrGoal(args: a, onPrewarm: _prewarm);
      case 7:
        return ScrLevel(args: a);
      case 8:
        return ScrBiology(args: a);
      case 9:
        return ScrNutritionStyle(args: a);
      case 10:
        // The full backend sync is kicked here; ScrEnter awaits it.
        return ScrBuilding(args: a, onStartSync: _startSync);
      // ── ACT 3 · Feature discovery (11–18) ───────────────────────────
      case 11:
        return ScrFeatureOverview(args: a);
      case 12:
        return ScrSocialFeed(args: a);
      case 13:
        return ScrSocialDetail(args: a);
      case 14:
        return ScrNutrition(args: a);
      case 15:
        return ScrNutritionDetail(args: a);
      case 16:
        return ScrBiology2(args: a);
      case 17:
        return ScrBiologyDetail(args: a);
      case 18:
        return ScrTracking(args: a);
      // ── ACT 4 · Community (19–23) ───────────────────────────────────
      case 19:
        return ScrMosaic(args: a);
      case 20:
        return ScrTestimonials(args: a);
      case 21:
        return ScrChallenge(args: a);
      case 22:
        return ScrBadge(args: a);
      case 23:
        return ScrNotifications(args: a);
      // ── ACT 5 · Launch (24–28) ──────────────────────────────────────
      case 24:
        return ScrConnect(args: a);
      case 25:
        return ScrCommit(args: a);
      case 26:
        return ScrSummary(args: a);
      case 27:
        return ScrMotivation(args: a);
      default:
        return ScrEnter(args: a, busy: _finishing);
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// KIT — ported from onboarding-kit.jsx onto ZveltTokens / ZType
// ═════════════════════════════════════════════════════════════════════════════

/// Full-width gradient CTA pill with disabled-gating + busy spinner.
/// Mirrors the JSX `PillBtn variant="gradient" size="lg"` used in every footer.
class OnbPrimaryButton extends StatelessWidget {
  const OnbPrimaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.busy = false,
    this.showArrow = true,
  });

  final String label;

  /// Null disables the button (gates required input). Also disabled while busy.
  final VoidCallback? onTap;
  final bool busy;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                onTap!();
              }
            : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: enabled ? 1 : 0.45,
          child: Container(
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: ZveltTokens.gradBtn,
              borderRadius: BorderRadius.circular(ZveltTokens.rPill),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: ZveltTokens.brand.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontFamily: ZveltTokens.fontPrimary,
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      if (showArrow) ...[
                        const SizedBox(width: ZveltTokens.s2),
                        const Icon(AppIcons.arrow_small_right,
                            color: Colors.white, size: 18),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Low-emphasis text link CTA (the JSX "Maybe later" / "Not now" / mode toggle).
class OnbGhostButton extends StatelessWidget {
  const OnbGhostButton({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: TextButton(
        onPressed: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Text(
          label,
          style: TextStyle(
            fontFamily: ZveltTokens.fontPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: ZveltTokens.text2,
          ),
        ),
      ),
    );
  }
}

/// Thin progress track + brand gradient fill + `n/total` mono label.
/// JSX `OnbProgress`. Used on personalization screens 5–10 with total = 6.
class OnbProgress extends StatelessWidget {
  const OnbProgress({super.key, required this.step, required this.total});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final factor = total <= 0 ? 0.0 : (step / total).clamp(0.0, 1.0);
    return Semantics(
      label: 'Step $step of $total',
      excludeSemantics: true,
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(ZveltTokens.rPill),
              child: SizedBox(
                height: 6,
                child: Stack(
                  children: [
                    ColoredBox(
                        color: ZveltTokens.surface3,
                        child: const SizedBox.expand()),
                    AnimatedFractionallySizedBox(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                      widthFactor: factor,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                              colors: [ZveltTokens.brandDeep, ZveltTokens.brand]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: ZveltTokens.s3),
          Text(
            '$step / $total',
            style: TextStyle(
              fontFamily: ZveltTokens.fontMono,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: ZveltTokens.text3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Status-bar-safe scaffold: optional circular back button + optional
/// [OnbProgress] header, a scrollable (or centered) body, and a fixed footer.
/// JSX `OnbShell`.
class OnbShell extends StatelessWidget {
  const OnbShell({
    super.key,
    this.onBack,
    this.progress,
    this.footer,
    required this.child,
    this.dark = false,
    this.scroll = true,
  });

  /// When non-null, renders the circular back button in the header row.
  final VoidCallback? onBack;

  /// (step, total) — renders the progress bar in the header row.
  final (int, int)? progress;

  /// Fixed footer (usually the primary CTA). Null hides the footer area.
  final Widget? footer;

  final Widget child;

  /// Dark hero variant (gradient #0a0a0c→#16161a). Defined per the bundle but
  /// the current flow renders light everywhere.
  final bool dark;

  /// When false, the body is centered/non-scrolling (splash, building, badge,
  /// motivation, enter). When true, the body scrolls.
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(
        ZveltTokens.screenPaddingH,
        ZveltTokens.s1,
        ZveltTokens.screenPaddingH,
        ZveltTokens.s4,
      ),
      child: child,
    );
    return Container(
      decoration: BoxDecoration(
        gradient: dark
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0A0A0C), Color(0xFF16161A)],
              )
            : null,
        color: dark ? null : ZveltTokens.bg,
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (onBack != null || progress != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ZveltTokens.screenPaddingH,
                  ZveltTokens.s2,
                  ZveltTokens.screenPaddingH,
                  ZveltTokens.s3,
                ),
                child: Row(
                  children: [
                    if (onBack != null)
                      Semantics(
                        button: true,
                        label: 'Back',
                        excludeSemantics: true,
                        child: GestureDetector(
                          onTap: onBack,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: dark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : ZveltTokens.surface,
                              border: dark
                                  ? null
                                  : Border.all(color: ZveltTokens.border),
                            ),
                            child: Icon(
                              AppIcons.arrow_small_left,
                              size: 18,
                              color: dark ? Colors.white : ZveltTokens.text,
                            ),
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 36),
                    if (progress != null) ...[
                      const SizedBox(width: ZveltTokens.s3),
                      Expanded(
                        child: OnbProgress(
                            step: progress!.$1, total: progress!.$2),
                      ),
                    ] else
                      const Spacer(),
                  ],
                ),
              )
            else
              const SizedBox(height: 56),
            Expanded(
              child: scroll
                  ? SingleChildScrollView(
                      // Keyboard-aware: pad by the keyboard inset so the focused
                      // field (e.g. Username on Step 1) can always scroll above
                      // the keyboard and the pinned footer instead of hiding
                      // behind the Continue button.
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.viewInsetsOf(context).bottom,
                      ),
                      child: body,
                    )
                  : SizedBox.expand(child: body),
            ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ZveltTokens.screenPaddingH,
                  ZveltTokens.s3,
                  ZveltTokens.screenPaddingH,
                  ZveltTokens.s4,
                ),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

/// Mono uppercase technical label. JSX `Eyebrow` / `.z-eyebrow`.
class OnbEyebrow extends StatelessWidget {
  const OnbEyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: ZveltTokens.fontMono,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.6,
        color: color ?? ZveltTokens.text3,
      ),
    );
  }
}

/// Headline block: eyebrow (mono, tertiary) → 30px display title → 15px sub.
/// JSX `OnbHead`.
class OnbHead extends StatelessWidget {
  const OnbHead({
    super.key,
    this.eyebrow,
    required this.title,
    this.sub,
    this.dark = false,
    this.center = false,
  });

  final String? eyebrow;
  final String title;
  final String? sub;
  final bool dark;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          OnbEyebrow(eyebrow!,
              color: dark ? ZveltTokens.brand3 : ZveltTokens.text3),
          const SizedBox(height: ZveltTokens.s2),
        ],
        Text(
          title,
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontFamily: ZveltTokens.fontPrimary,
            fontSize: 30,
            height: 1.12,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.66,
            color: dark ? Colors.white : ZveltTokens.text,
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: ZveltTokens.s3),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              sub!,
              textAlign: center ? TextAlign.center : TextAlign.start,
              style: TextStyle(
                fontFamily: ZveltTokens.fontPrimary,
                fontSize: 14.5,
                height: 1.55,
                color: dark
                    ? Colors.white.withValues(alpha: 0.65)
                    : ZveltTokens.text2,
              ),
            ),
          ),
        ],
        const SizedBox(height: ZveltTokens.s5),
      ],
    );
  }
}

/// Rounded-square tinted icon tile. JSX `TileIcon`.
class OnbTileIcon extends StatelessWidget {
  const OnbTileIcon({
    super.key,
    required this.icon,
    this.color = ZveltTokens.brand,
    this.bg,
    this.size = 46,
    this.iconSize = 22,
  });

  final IconData icon;
  final Color color;
  final Color? bg;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg ?? ZveltTokens.brandTint,
        borderRadius: BorderRadius.circular(size * 0.26),
      ),
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}

/// Single-select option row: tinted icon tile + title/sub + right radio.
/// Selected = 2px brand border + brand-glow shadow + filled check. JSX `SelectCard`.
class SelectCard extends StatelessWidget {
  const SelectCard({
    super.key,
    required this.icon,
    required this.title,
    this.sub,
    required this.selected,
    required this.onTap,
    this.color = ZveltTokens.brand,
    this.bg,
  });

  final IconData icon;
  final String title;
  final String? sub;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
  final Color? bg;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(ZveltTokens.s4),
          decoration: BoxDecoration(
            color: ZveltTokens.surface,
            borderRadius: BorderRadius.circular(ZveltTokens.rLg),
            border: Border.all(
              color: selected ? ZveltTokens.brand : Colors.transparent,
              width: 2,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: ZveltTokens.brand.withValues(alpha: 0.16),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : ZveltTokens.shadowCard,
          ),
          child: Row(
            children: [
              OnbTileIcon(icon: icon, color: color, bg: bg),
              const SizedBox(width: ZveltTokens.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: ZveltTokens.fontPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ZveltTokens.text,
                      ),
                    ),
                    if (sub != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        sub!,
                        style: TextStyle(
                            fontFamily: ZveltTokens.fontPrimary,
                            fontSize: 12,
                            color: ZveltTokens.text2),
                      ),
                    ],
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? ZveltTokens.brand : Colors.transparent,
                  border: selected
                      ? null
                      : Border.all(color: ZveltTokens.borderStrong, width: 2),
                ),
                child: selected
                    ? const Icon(AppIcons.check,
                        size: 14, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Labeled text input: mono eyebrow label → white card with 1px border, 16px
/// text, optional unit suffix (cm/kg/years). JSX `OnbField`.
class OnbField extends StatefulWidget {
  const OnbField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.placeholder,
    this.suffix,
    this.numeric = false,
    this.obscure = false,
    this.keyboardType,
    this.hint,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? placeholder;

  /// Trailing unit text (cm / kg / years).
  final String? suffix;

  /// Numeric keyboard + digits-only filtering.
  final bool numeric;

  /// Password-style obscured input.
  final bool obscure;

  /// Explicit keyboard type (overrides [numeric] inference when set).
  final TextInputType? keyboardType;

  /// Inline hint shown under the field (e.g. password too short).
  final String? hint;

  @override
  State<OnbField> createState() => _OnbFieldState();
}

class _OnbFieldState extends State<OnbField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(OnbField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _ctrl.text) {
      final previous = _ctrl.selection;
      _ctrl.text = widget.value;
      if (previous.isValid && previous.end <= widget.value.length) {
        _ctrl.selection = previous;
      } else {
        _ctrl.selection =
            TextSelection.collapsed(offset: widget.value.length);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OnbEyebrow(widget.label),
        const SizedBox(height: ZveltTokens.s2),
        Container(
          decoration: BoxDecoration(
            color: ZveltTokens.surface,
            borderRadius: BorderRadius.circular(ZveltTokens.rMd),
            border: Border.all(color: ZveltTokens.borderStrong),
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: ZveltTokens.s4, vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  onChanged: widget.onChanged,
                  obscureText: widget.obscure,
                  keyboardType: widget.keyboardType ??
                      (widget.numeric
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : null),
                  inputFormatters: widget.numeric
                      ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
                      : null,
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontSize: 16,
                    color: ZveltTokens.text,
                  ),
                  cursorColor: ZveltTokens.brand,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: widget.placeholder,
                    hintStyle: TextStyle(
                      fontFamily: ZveltTokens.fontPrimary,
                      fontSize: 16,
                      color: ZveltTokens.text4,
                    ),
                  ),
                ),
              ),
              if (widget.suffix != null) ...[
                const SizedBox(width: ZveltTokens.s2),
                Text(
                  widget.suffix!,
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontMono,
                    fontSize: 13,
                    color: ZveltTokens.text3,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (widget.hint != null) ...[
          const SizedBox(height: ZveltTokens.s1),
          Text(
            widget.hint!,
            style: TextStyle(
              fontFamily: ZveltTokens.fontPrimary,
              fontSize: 12,
              color: ZveltTokens.text3,
            ),
          ),
        ],
      ],
    );
  }
}
