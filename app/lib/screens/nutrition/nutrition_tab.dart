import 'dart:async';
import 'dart:math' as math;
import 'package:zvelt_app/theme/app_icons.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/z/z_loading.dart';
import '../../services/_crash_reporter.dart' show reportError;
import '../../services/auth_service.dart';
import '../../services/fasting_service.dart';
import '../../services/nutrition_service.dart';
import '../../services/onboarding_service.dart';
import '../../services/profile_service.dart';
import '../../services/nutrition_food_labels.dart';
import '../../widgets/zvelt_primary_button.dart';
import '../../widgets/zvelt_main_nav_bar.dart';
import '../../widgets/zvelt_error_state.dart';
import 'recipe_builder_screen.dart';
import 'nutrition_barcode_scan_screen.dart';

/// Precomputed diary roll-up for one day. The four macro totals + the
/// per-meal grouping are derived ONCE per `_day` change (single pass over
/// `entries`) instead of being recomputed on every rebuild — the diary used
/// to fold the entries list 4× for the totals and run `.where().toList()` 4×
/// for the meal grouping on each frame.
class _DiaryTotals {
  const _DiaryTotals({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.byMeal,
  });

  final double calories;
  final double protein;
  final double carbs;
  final double fat;

  /// breakfast / lunch / dinner / snack → that meal's entries (in order).
  final Map<String, List<MealEntry>> byMeal;

  static const _DiaryTotals empty = _DiaryTotals(
    calories: 0,
    protein: 0,
    carbs: 0,
    fat: 0,
    byMeal: {},
  );

  factory _DiaryTotals.from(DailyNutrition day) {
    var calories = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0;
    final byMeal = <String, List<MealEntry>>{};
    for (final e in day.entries) {
      calories += e.calories;
      protein += e.protein;
      carbs += e.carbs;
      fat += e.fat;
      (byMeal[e.meal] ??= <MealEntry>[]).add(e);
    }
    return _DiaryTotals(
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      byMeal: byMeal,
    );
  }
}

/// Diary row subtitle — portion ONLY, per prototype food rows (HTML 253):
/// e.g. '1 bowl' or '240 g'. Macros stay in the portion/detail sheet.
String _mealEntrySubtitle(MealEntry entry) {
  final sg = entry.food.servingGrams;
  if (sg != null && sg > 0) {
    final n = entry.grams / sg;
    if (n > 0) {
      final key = entry.food.portionUnitKey ?? 'serving';
      return NutritionFoodLabels.formatUnitCount(n, key);
    }
  }
  return '${entry.grams.round()} g';
}

// ─────────────────────────────────────────────────────────────────────────────
// NUTRITION TAB
// ─────────────────────────────────────────────────────────────────────────────

class NutritionTab extends StatefulWidget {
  const NutritionTab({super.key});

  @override
  State<NutritionTab> createState() => _NutritionTabState();
}

class _NutritionTabState extends State<NutritionTab> {
  final _service = NutritionService.instance;
  final _profileService = ProfileService();
  final _onboardingService = OnboardingService();
  DailyNutrition _day = DailyNutrition.empty;
  // Derived once per `_day` change (see _setDay) — diary totals + per-meal
  // grouping, so the build path never folds/filters the entries list again.
  _DiaryTotals _totals = _DiaryTotals.empty;
  NutritionGoals _goals = const NutritionGoals();
  List<NutritionPlanDay> _weekPlan = const [];
  bool _loading = true;
  // First-load failure: when the whole `_load` body throws before any usable
  // data is in place we surface the shared ZveltErrorState + retry instead of
  // silently showing a zeroed/empty tracker.
  bool _loadFailed = false;
  bool _signedIn = false;
  // AI plan generation runs in the background — only the week-plan card
  // shows a generating state, the rest of the tracker stays usable.
  bool _planGenerating = false;
  // One-shot guard so we auto-generate the weekly meal plan only once per
  // session when the tab opens empty (e.g. right after onboarding).
  bool _autoBootstrapTried = false;
  // NOT final: the tab State lives in the nav shell across midnight, so the
  // day must roll over (see build) — otherwise food logged after 00:00 was
  // written to yesterday.
  DateTime _today = _midnightOf(DateTime.now());
  static DateTime _midnightOf(DateTime d) => DateTime(d.year, d.month, d.day);
  final _auth = AuthService();

  // ── Prototype nutrition state (HTML 217–317) ──
  /// Day the tracker shows (week strip / calendar sheet select it).
  DateTime _selDate = _midnightOf(DateTime.now());

  /// Active meal pill: breakfast / lunch / dinner / snack.
  String _activeMeal = 'breakfast';

  /// Checked-off basket ingredient names for [_selDate] (persisted).
  Set<String> _basketChecked = {};

  /// yyyy-mm-dd keys of days with logged calories — dots in the calendar sheet.
  Set<String> _loggedDayKeys = const {};

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get _basketPrefsKey => 'zvelt_basket_checked_${_ymd(_selDate)}';

  /// Plan day for [_selDate] (week plan is indexed by weekday).
  NutritionPlanDay? get _selPlanDay {
    if (_weekPlan.isEmpty) return null;
    final i = _selDate.weekday - 1;
    return i < _weekPlan.length ? _weekPlan[i] : _weekPlan.first;
  }

  /// Basket = ingredients of the selected day's planned meals (real plan data).
  List<({String name, String qty})> get _basketItems {
    final plan = _selPlanDay?.mealPlan;
    if (plan == null) return const [];
    const mealLabels = {
      'breakfast': 'Breakfast',
      'lunch': 'Lunch',
      'dinner': 'Dinner',
      'snack': 'Snacks',
      'snacks': 'Snacks',
    };
    final out = <({String name, String qty})>[];
    final seen = <String>{};
    for (final meal in plan.meals) {
      for (final item in meal.items) {
        final name = item.text.trim();
        if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
        out.add((
          name: name,
          qty: item.portion?.trim().isNotEmpty == true
              ? item.portion!.trim()
              : (mealLabels[meal.mealKey.toLowerCase()] ?? meal.mealKey),
        ));
      }
    }
    return out;
  }

  int get _basketCount =>
      _basketItems.where((b) => !_basketChecked.contains(b.name)).length;

  // Fasting (handoff §13d) — persisted protocol + start; ring ticks live
  // from wall-clock only while a fast is active.
  FastingState _fasting = const FastingState(active: false, protocolHours: 16);
  Timer? _fastTick;

  void _syncFastingTicker() {
    if (_fasting.active && _fastTick == null) {
      _fastTick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!_fasting.active) {
      _fastTick?.cancel();
      _fastTick = null;
    }
  }

  @override
  void dispose() {
    _fastTick?.cancel();
    super.dispose();
  }

  static double? _bodyweightFromProfileMap(Map<String, dynamic>? profile) {
    if (profile == null) return null;
    final bwRaw = profile['bodyweightKg'] ??
        profile['bodweightKg'] ??
        profile['bodyweight_kg'];
    if (bwRaw == null) return null;
    return bwRaw is num ? bwRaw.toDouble() : double.tryParse(bwRaw.toString());
  }

  /// Single funnel for `_day` mutations: assigns the day AND recomputes the
  /// derived totals/grouping in the same pass, so every rebuild reads cached
  /// fields instead of re-folding/re-filtering the entries list.
  void _setDay(DailyNutrition day) {
    _day = day;
    _totals = _DiaryTotals.from(day);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showSpinner = true}) async {
    // ── Defensive bootstrap. Each fetch is wrapped + has a sensible default,
    //    and the whole body sits in try/finally so a single unexpected throw
    //    on any service call cannot leave the spinner spinning forever. The
    //    previous version had none of these guards, which is why a single
    //    failing fetch made the entire nutrition tab look "broken" (infinite
    //    progress indicator instead of an empty/usable state).
    if (!mounted) return;
    if (showSpinner) setState(() => _loading = true);
    await Future<void>.delayed(Duration.zero);
    bool signedIn = false;
    DailyNutrition day = DailyNutrition.empty;
    NutritionGoals goals = const NutritionGoals();
    List<NutritionPlanDay> plan = const [];
    double? profileBw;
    bool failed = false;
    try {
      try {
        signedIn = (await _auth.getStoredUserId()) != null;
      } catch (_) {
        signedIn = false;
      }
      // Best-effort warm-up of the local day cache. Already swallows errors
      // internally; we don't propagate either way.
      try {
        await _service.syncHistoryFromServer(days: 14);
      } catch (_) {/* non-fatal */}

      // Per-call catchError so one slow / failing endpoint can't kill the
      // whole tab. getDay/getGoals/getWeeklyPlan already return sane
      // defaults internally — this is a belt-and-suspenders extra layer.
      // Signed-in: fetch /me ONCE and derive BOTH goals and bodyweight from
      // that single response (goalsFromMeResponse keeps getGoals' prefs-write
      // / cached-fallback side effects) instead of getGoals()+getMe() each
      // hitting /me.
      final results = await Future.wait<dynamic>([
        _service.getDay(_selDate).catchError((_) => DailyNutrition.empty),
        _service.getWeeklyPlan().catchError((_) => <NutritionPlanDay>[]),
        if (signedIn)
          _profileService.getMe().catchError((_) => null)
        else
          Future<Map<String, dynamic>?>.value(null),
      ]);
      day = results[0] as DailyNutrition;
      plan = results[1] as List<NutritionPlanDay>;
      final me = signedIn ? results[2] as Map<String, dynamic>? : null;
      goals = signedIn
          ? await _service
              .goalsFromMeResponse(me)
              .catchError((_) => const NutritionGoals())
          : await _service.getGoals().catchError((_) => const NutritionGoals());
      if (!nutritionPlanMatchesGoals(goals, plan)) {
        // A plan is server-derived output. Ignore stale/cross-version rows
        // instead of letting a previous target leak into today's tracker.
        debugPrint(
          '[NutritionTab] ignoring weekly plan that differs from profile targets',
        );
        plan = const [];
      }
      profileBw = signedIn
          ? _bodyweightFromProfileMap(me?['profile'] as Map<String, dynamic>?)
          : null;
      if (signedIn && profileBw == null) {
        try {
          await _onboardingService.syncSavedQuestionnaireToProfile();
          final meRetry = await _profileService.getMe().catchError((_) => null);
          profileBw = _bodyweightFromProfileMap(
              meRetry?['profile'] as Map<String, dynamic>?);
        } catch (_) {/* non-fatal */}
      }
      profileBw ??= await _onboardingService.getSavedWeightKg();
      try {
        _fasting = await FastingService().load();
      } catch (_) {/* non-fatal — card renders inactive */}
      // Calendar-sheet dots + basket checked state (best-effort).
      try {
        final history = await _service.loadNutritionHistory(days: 60);
        _loggedDayKeys = {
          for (final d in history)
            if (d.calories > 0) _ymd(d.date),
        };
      } catch (_) {/* non-fatal — calendar renders without dots */}
      try {
        final p = await SharedPreferences.getInstance();
        _basketChecked = (p.getStringList(_basketPrefsKey) ?? const []).toSet();
      } catch (_) {/* non-fatal */}
    } catch (e, st) {
      // Each fetch above has its own catchError fallback, so reaching here
      // means something unexpected threw outside those guards. Flag the load
      // as failed so the UI can offer a retry instead of presenting the
      // zeroed defaults as if they were real data.
      failed = true;
      reportError(e, st, reason: 'nutrition-tab:_load');
    } finally {
      if (mounted) {
        setState(() {
          _setDay(day);
          _goals = goals;
          _weekPlan = plan;
          _signedIn = signedIn;
          // Only treat as a hard failure on the FIRST load (nothing usable on
          // screen yet). A background refresh that throws keeps the existing
          // data rather than blanking the tab into an error surface.
          _loadFailed = failed && showSpinner;
          _loading = false;
        });
        _syncFastingTicker();
      }
    }
    // Auto-generate the weekly meal plan the first time Nutrition opens with no
    // plan yet (e.g. right after onboarding set the goal) so the tab isn't
    // empty. One-shot per session to avoid repeated 30-120s AI calls.
    if (mounted && _signedIn && _weekPlan.isEmpty && !_autoBootstrapTried) {
      _autoBootstrapTried = true;
      unawaited(_bootstrapWeekPlan(userInitiated: false));
    }
  }

  /// [userInitiated] — false for the automatic once-per-session bootstrap:
  /// that path must fail SILENTLY (debugPrint only), otherwise opening the
  /// tab offline surfaces an unprompted "sign in again" snackbar. Explicit
  /// taps (Create weekly plan / RETRY) keep the full snackbar feedback.
  Future<void> _bootstrapWeekPlan({bool userInitiated = true}) async {
    if (!_signedIn) return;
    final bearer = await _auth.getAccessToken();
    if (bearer == null) {
      if (!userInitiated) {
        debugPrint(
            '[NutritionTab] auto plan bootstrap skipped: no server session');
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No valid server session. Check your connection or sign in again.'),
        ),
      );
      return;
    }
    // Background generation: only the week-plan card shows the generating
    // state — the AI call takes 30-120s on a cold Render dyno + DeepSeek and
    // the old full-tab spinner blocked food/water/weight logging the whole
    // time (the user's FIRST impression of the tab, right after onboarding).
    if (mounted) setState(() => _planGenerating = true);
    try {
      await _service.generateWeeklyPlan(force: false);
      await _load(showSpinner: false);
      if (!mounted) return;
      if (_weekPlan.isEmpty && !userInitiated) {
        debugPrint('[NutritionTab] auto plan bootstrap produced no plan');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _weekPlan.isEmpty
                  ? 'Could not create a plan (backend, network, or account).'
                  : 'Weekly plan created.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (userInitiated) {
        _showPlanError(context, e);
      } else {
        debugPrint('[NutritionTab] auto plan bootstrap failed: $e');
      }
    } finally {
      if (mounted) setState(() => _planGenerating = false);
    }
  }

  /// Friendly, auto-dismissing error SnackBar scoped to the nutrition tab.
  /// Never shows raw server text or a stack: [NutritionPlanException.toString]
  /// is already user-safe, anything else falls back to a generic message. The
  /// 5s duration (vs the old persistent 15s) stops the red box from bleeding
  /// over Home / Workout-complete / Imported history.
  void _showPlanError(BuildContext ctx, Object error) {
    final friendly = error is NutritionPlanException
        ? error.message
        : 'Could not create the weekly plan. Try again.';
    final messenger = ScaffoldMessenger.of(ctx);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: ZveltTokens.error,
        duration: const Duration(seconds: 5),
        content: Text(friendly,
            style: ZType.bodyS.copyWith(color: ZveltTokens.onBrand)),
        action: SnackBarAction(
          label: 'RETRY',
          textColor: ZveltTokens.onBrand,
          onPressed: () => unawaited(_bootstrapWeekPlan()),
        ),
      ),
    );
  }

  Future<void> _regenerateWeeklyPlanWithAi() async {
    final bearer = await _auth.getAccessToken();
    if (bearer == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Sign in again to regenerate the plan on the server.')),
      );
      return;
    }
    // Same UX as _bootstrapWeekPlan — generating state on the plan card
    // only; the tracker stays usable while DeepSeek grinds for ~60-120s.
    if (_planGenerating) return; // double-tap guard
    if (mounted) setState(() => _planGenerating = true);
    try {
      await _service.generateWeeklyPlan(force: true);
      if (!mounted) return;
      await _load(showSpinner: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Weekly plan refreshed.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showPlanError(context, e);
    } finally {
      if (mounted) setState(() => _planGenerating = false);
    }
  }

  /// Inline generating state for the week-plan card — honest about the wait
  /// while keeping the rest of the tracker fully usable.
  Widget _buildPlanGeneratingCard() {
    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                color: ZveltTokens.brand, strokeWidth: 2.5),
          ),
          const SizedBox(width: ZveltTokens.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Building your weekly plan…',
                  style: ZType.bodyM.copyWith(
                    color: ZveltTokens.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: ZveltTokens.s1),
                Text(
                  'Usually 1-2 minutes. You can keep logging meanwhile.',
                  style: ZType.monoS.copyWith(color: ZveltTokens.text2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openDayMealPlan(NutritionPlanDay day) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DayMealPlanSheet(
        planDay: day,
        onSave: (plan) async {
          await _service.patchNutritionPlanDay(day.day, plan);
          await _load();
        },
        onRegenerateWeek: _regenerateWeeklyPlanWithAi,
      ),
    );
  }

  void _showAddFood(String meal) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddFoodSheet(
        meal: meal,
        onAdd: (entry) async {
          await _service.addEntry(entry);
          // Local mutation persisted to prefs (server push runs in the
          // background, dirty-flag protected) — apply the exact next state
          // directly instead of a full _load() reload (which flashes the
          // spinner and re-hits the network).
          if (mounted) {
            setState(() {
              _setDay(DailyNutrition(
                entries: List<MealEntry>.from(_day.entries)..add(entry),
                waterMl: _day.waterMl,
                weightKg: _day.weightKg,
              ));
            });
            // Prototype addFood (JS 1639): confirm the log with a toast.
            _toast('Added ${entry.food.name}');
          }
        },
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    // Global SnackBarTheme (app_theme.dart) already handles bg/shape/behavior.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<String?> _promptName(String hint) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZveltTokens.surface,
        title: Text(hint, style: ZType.h4.copyWith(color: ZveltTokens.text)),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: ZveltTokens.brand,
                foregroundColor: ZveltTokens.onBrand),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return name;
  }

  Future<void> _showDayMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: ZveltTokens.surface,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: ZveltTokens.s2),
            _sheetHandle(),
            ListTile(
              leading:
                  const Icon(AppIcons.restaurant, color: ZveltTokens.brand),
              title: Text('Save day as meal',
                  style: ZType.bodyM.copyWith(color: ZveltTokens.text)),
              onTap: () => Navigator.pop(context, 'save'),
            ),
            ListTile(
              leading: const Icon(AppIcons.calendar, color: ZveltTokens.brand),
              title: Text('Copy from another day',
                  style: ZType.bodyM.copyWith(color: ZveltTokens.text)),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            const SizedBox(height: ZveltTokens.s4),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'save') await _saveAsTemplate();
    if (action == 'copy') await _copyFromDay();
  }

  Future<void> _saveAsTemplate() async {
    if (_day.entries.isEmpty) {
      _toast('This day is empty — nothing to save');
      return;
    }
    final name = await _promptName('Meal name');
    if (!mounted || name == null || name.isEmpty) return;
    final items = _day.entries
        .map((e) => MealTemplateItem(
              name: e.food.name,
              grams: e.grams,
              calories: e.calories,
              proteinG: e.protein,
              carbsG: e.carbs,
              fatG: e.fat,
              meal: e.meal,
            ))
        .toList();
    try {
      await _service.createMealTemplate(name, items);
      _toast('Meal saved');
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _copyFromDay() async {
    final src = await showDatePicker(
      context: context,
      initialDate: _today.subtract(const Duration(days: 1)),
      firstDate: DateTime(2021, 1, 1),
      lastDate: _today,
    );
    if (!mounted || src == null) return;
    try {
      final day = await _service.getDay(src);
      if (!mounted) return;
      if (day.entries.isEmpty) {
        _toast('The selected day is empty');
        return;
      }
      for (final e in day.entries) {
        await _service.addEntry(MealEntry(
          id: 'cp${DateTime.now().microsecondsSinceEpoch}_${e.id}',
          food: e.food,
          grams: e.grams,
          meal: e.meal,
          loggedAt: DateTime.now(),
        ));
      }
      if (!mounted) return;
      await _load(showSpinner: false);
      _toast('Copied ${day.entries.length} foods');
    } catch (e) {
      if (mounted) _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _toggleFasting() async {
    final svc = FastingService();
    final next = _fasting.active
        ? await svc.end()
        : await svc.start(protocolHours: _fasting.protocolHours);
    if (!mounted) return;
    setState(() => _fasting = next);
    _syncFastingTicker();
  }

  Future<void> _openFastingSheet() async {
    final next = await showModalBottomSheet<FastingState>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FastingSheet(state: _fasting),
    );
    if (!mounted) return;
    // No result = dismissed via X/scrim — the sheet may still have applied
    // live window/start edits mid-fast, so re-read the persisted state.
    final latest = next ?? await FastingService().load();
    if (!mounted) return;
    setState(() => _fasting = latest);
    _syncFastingTicker();
  }

  @override
  Widget build(BuildContext context) {
    // Day rollover: the tab State survives across midnight inside the nav
    // shell. Without this, water/weight/entry writes landed on YESTERDAY's
    // key and the screen kept showing yesterday's totals as 'today'.
    final nowDay = _midnightOf(DateTime.now());
    if (nowDay != _today) {
      // Keep the selected day tracking "today" across midnight rollover.
      if (_selDate == _today) _selDate = nowDay;
      _today = nowDay;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            Expanded(
              child: _loading
                  ? ZPageSkeleton(
                      showHeader: false,
                      itemCount: 5,
                      padding: EdgeInsets.fromLTRB(
                        ZveltTokens.s4,
                        ZveltTokens.s3,
                        ZveltTokens.s4,
                        ZveltMainNavBar.reservedBottomHeight(context) +
                            ZveltTokens.s4,
                      ),
                    )
                  : _loadFailed
                      ? ZveltErrorState(
                          title: "Couldn't load nutrition",
                          onRetry: _load,
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: ZveltTokens.brand,
                          child: ListView(
                            padding: EdgeInsets.only(
                                bottom: ZveltMainNavBar.reservedBottomHeight(
                                        context) +
                                    ZveltTokens.s4),
                            children: [
                              // Prototype block order (HTML 217–312): date row,
                              // week strip, meal pills, meal log, plan card,
                              // calories hero, macros, fasting.
                              _dateRow(),
                              _weekStrip(),
                              _mealPills(),
                              _mealLogCard(),
                              if (_planGenerating)
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 12, 20, 0),
                                  child: _buildPlanGeneratingCard(),
                                )
                              else if (_weekPlan.isEmpty)
                                _aiPlanCard()
                              else
                                _weekPlanRow(),
                              _caloriesHero(),
                              _macrosCard(),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 16, 20, 0),
                                child: _FastingCard(
                                  state: _fasting,
                                  onTap: _openFastingSheet,
                                  onToggle: _toggleFasting,
                                ),
                              ),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Prototype blocks (HTML 217–312) ────────────────────────────────────────

  // Header — 'Nutrition' + basket button with badge (HTML 219–222).
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
      child: Row(
        children: [
          Text('Nutrition', style: ZType.h1.copyWith(fontSize: 24)),
          const Spacer(),
          InkWell(
            onTap: _openBasket,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ZveltTokens.chip,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ZveltTokens.border),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(AppIcons.apps, size: 20, color: ZveltTokens.text),
                  if (_basketCount > 0)
                    Positioned(
                      top: -8,
                      right: -10,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        height: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: ZveltTokens.brand,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: ZveltTokens.bg, width: 2),
                        ),
                        child: Text('$_basketCount',
                            style: ZType.monoXS.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: ZveltTokens.onBrand)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openBasket() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BasketSheet(
        items: _basketItems,
        checked: _basketChecked,
        onChanged: (next) async {
          setState(() => _basketChecked = next);
          try {
            final p = await SharedPreferences.getInstance();
            await p.setStringList(_basketPrefsKey, next.toList());
          } catch (_) {}
        },
      ),
    );
    if (mounted) setState(() {}); // refresh badge
  }

  Future<void> _selectDate(DateTime d) async {
    final day = _midnightOf(d);
    if (day == _selDate) return;
    setState(() => _selDate = day);
    await _load(showSpinner: false);
  }

  Future<void> _openCalendarSheet() async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CalendarSheet(
        selected: _selDate,
        loggedDayKeys: _loggedDayKeys,
      ),
    );
    if (picked != null && mounted) await _selectDate(picked);
  }

  // Date row — '{Month Year}' + chevron · calendar button (HTML 224–227).
  Widget _dateRow() {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
      child: Row(
        children: [
          InkWell(
            onTap: _openCalendarSheet,
            onLongPress: _showDayMenu,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${months[_selDate.month - 1]} ${_selDate.year}',
                    style: ZType.bodyL
                        .copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                Icon(AppIcons.angle_small_down,
                    size: 16, color: ZveltTokens.text2),
              ],
            ),
          ),
          const Spacer(),
          Semantics(
            button: true,
            label: 'Choose nutrition date',
            child: Tooltip(
              message: 'Choose date',
              child: SizedBox(
                width: 48,
                height: 48,
                child: InkWell(
                  onTap: _openCalendarSheet,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ZveltTokens.chip,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: ZveltTokens.border),
                    ),
                    child: Icon(AppIcons.calendar,
                        size: 18, color: ZveltTokens.text),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Week strip — 7 day cells, selected = orange-tinted card (HTML 229–233).
  Widget _weekStrip() {
    final sunday = _selDate.subtract(Duration(days: _selDate.weekday % 7));
    const letters = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < 7; i++)
            _weekCell(sunday.add(Duration(days: i)), letters[i]),
        ],
      ),
    );
  }

  Widget _weekCell(DateTime day, String letter) {
    final sel = DateUtils.isSameDay(day, _selDate);
    return InkWell(
      onTap: () => _selectDate(day),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: sel
            ? const EdgeInsets.fromLTRB(10, 7, 10, 9)
            : const EdgeInsets.fromLTRB(4, 7, 4, 9),
        decoration: sel
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x8CF58214)),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0x33F58214), Color(0x0AF58214)],
                ),
              )
            : null,
        child: Column(
          children: [
            Text(letter,
                style: ZType.bodyS.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: sel ? ZveltTokens.brand : ZveltTokens.text3)),
            const SizedBox(height: 6),
            Text('${day.day}',
                style: ZType.bodyL
                    .copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  // Meal pills — Breakfast/Lunch/Dinner/Snacks (HTML 235–239).
  Widget _mealPills() {
    const meals = [
      ('breakfast', 'Breakfast'),
      ('lunch', 'Lunch'),
      ('dinner', 'Dinner'),
      ('snack', 'Snacks'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(
        children: [
          for (var i = 0; i < meals.length; i++) ...[
            Expanded(child: _mealPill(meals[i].$1, meals[i].$2)),
            if (i < meals.length - 1) const SizedBox(width: 7),
          ],
        ],
      ),
    );
  }

  Widget _mealPill(String key, String label) {
    final active = _activeMeal == key;
    final count = (_totals.byMeal[key] ?? const []).length;
    return InkWell(
      onTap: () => setState(() => _activeMeal = key),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
        decoration: BoxDecoration(
          color: active ? ZveltTokens.brand : ZveltTokens.chip,
          borderRadius: BorderRadius.circular(16),
          border: active ? null : Border.all(color: ZveltTokens.border),
          boxShadow: active ? ZveltTokens.glowSm : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZType.bodyS.copyWith(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      color: active ? ZveltTokens.onBrand : ZveltTokens.text2)),
            ),
            if (active) ...[
              const SizedBox(width: 5),
              const Icon(AppIcons.badge_check,
                  size: 13, color: ZveltTokens.onBrand),
            ] else if (count > 0) ...[
              const SizedBox(width: 5),
              Container(
                constraints: const BoxConstraints(minWidth: 17),
                height: 17,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ZveltTokens.chip,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text('$count',
                    style: ZType.monoXS
                        .copyWith(fontSize: 10.5, fontWeight: FontWeight.w800)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Meal log — active meal's entries + dashed Add-food (HTML 241–260).
  Widget _mealLogCard() {
    const mealLabels = {
      'breakfast': 'Breakfast',
      'lunch': 'Lunch',
      'dinner': 'Dinner',
      'snack': 'Snacks',
    };
    final entries = _totals.byMeal[_activeMeal] ?? const <MealEntry>[];
    final kcal = entries.fold<double>(0, (a, e) => a + e.calories).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          gradient: ZveltTokens.surfaceGrad,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: ZveltTokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${mealLabels[_activeMeal]} log',
                    style: ZType.bodyL
                        .copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('$kcal kcal',
                    style: ZType.bodyS.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: ZveltTokens.brand)),
              ],
            ),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 6),
                child: Center(
                  child: Text('No foods logged yet — tap “Add food” to start.',
                      style: ZType.bodyS.copyWith(
                          fontSize: 12.5, fontWeight: FontWeight.w500)),
                ),
              )
            else ...[
              const SizedBox(height: 12),
              for (var i = 0; i < entries.length; i++) ...[
                _foodRow(entries[i]),
                if (i < entries.length - 1) const SizedBox(height: 9),
              ],
            ],
            const SizedBox(height: 14),
            InkWell(
              onTap: () => _showAddFood(_activeMeal),
              borderRadius: BorderRadius.circular(15),
              child: CustomPaint(
                painter: const _DashedRRectPainter(
                    color: Color(0x66F58214), radius: 15),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: const Color(0x14F58214),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(AppIcons.plus,
                          size: 15, color: ZveltTokens.brand),
                      const SizedBox(width: 7),
                      Text('Add food',
                          style: ZType.bodyS.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: ZveltTokens.brand)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _foodRow(MealEntry e) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ZveltTokens.chip,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: ZveltTokens.border),
          ),
          child: Icon(AppIcons.restaurant, size: 16, color: ZveltTokens.text2),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.food.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZType.bodyM
                      .copyWith(fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 1),
              Text(_mealEntrySubtitle(e),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZType.bodyS
                      .copyWith(fontSize: 11, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text('${e.calories.round()} kcal',
            style: ZType.bodyS
                .copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        InkWell(
          onTap: () async {
            await _service.removeEntry(e.id, _selDate);
            if (!mounted) return;
            setState(() {
              _setDay(DailyNutrition(
                entries: _day.entries.where((x) => x.id != e.id).toList(),
                waterMl: _day.waterMl,
                weightKg: _day.weightKg,
              ));
            });
          },
          customBorder: const CircleBorder(),
          child: Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ZveltTokens.chip,
              border: Border.all(color: ZveltTokens.border),
            ),
            child:
                Icon(AppIcons.cross_small, size: 13, color: ZveltTokens.text2),
          ),
        ),
      ],
    );
  }

  // AI Meal Plan card — noPlan state (HTML 262–270).
  Widget _aiPlanCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: ZveltTokens.surfaceGrad,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: ZveltTokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [ZveltTokens.brand2, ZveltTokens.brandDeep],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: ZveltTokens.glowSm,
                  ),
                  child: const Icon(AppIcons.sparkles,
                      size: 22, color: ZveltTokens.onBrand),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AI Meal Plan',
                          style: ZType.bodyL.copyWith(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        _signedIn
                            ? 'Answer a few questions and we’ll build your week.'
                            : 'Sign in and we’ll build your week.',
                        style: ZType.bodyS.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _signedIn ? _openPlanQuizSheet : null,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: ZveltTokens.brand,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: ZveltTokens.glowMd,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(AppIcons.sparkles,
                        size: 16, color: ZveltTokens.onBrand),
                    const SizedBox(width: 7),
                    Text('Generate meal plan',
                        style: ZType.bodyS.copyWith(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: ZveltTokens.onBrand)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // This week's plan row — hasPlan state (HTML 271–277).
  Widget _weekPlanRow() {
    final day = _selPlanDay;
    final goal = day?.goal.trim() ?? '';
    final goalLabel =
        goal.isEmpty ? 'Plan' : '${goal[0].toUpperCase()}${goal.substring(1)}';
    final summary =
        '$goalLabel · ${_fmtInt(day?.calories ?? _goals.calories)} kcal/day';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: InkWell(
        onTap: _openWeekPlanSheet,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            gradient: ZveltTokens.heroGrad,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: ZveltTokens.heroBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [ZveltTokens.brand2, ZveltTokens.brandDeep],
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(AppIcons.sparkles,
                    size: 20, color: ZveltTokens.onBrand),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('This week’s plan',
                        style: ZType.bodyM.copyWith(
                            fontSize: 14.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(summary,
                        style: ZType.bodyS.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: ZveltTokens.brand)),
                  ],
                ),
              ),
              Icon(AppIcons.angle_small_right,
                  size: 18, color: ZveltTokens.text2),
            ],
          ),
        ),
      ),
    );
  }

  /// AI Meal Plan quiz (prototype sheetPlan quiz step, HTML 743–758).
  /// Answers are persisted in the canonical profile before generation.
  Future<void> _openPlanQuizSheet() async {
    final picked = await showModalBottomSheet<
        ({String diet, String goal, String activity, int meals})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlanQuizSheet(goals: _goals),
    );
    if (picked == null || !mounted) return;
    final nextGoals = _goals.copyWith(
      diet: picked.diet,
      goal: picked.goal,
      activityLevel: picked.activity,
      mealsPerDay: picked.meals,
    );
    await _service.saveGoals(nextGoals);
    if (!mounted) return;
    setState(() {
      _goals = nextGoals;
      _weekPlan = const [];
    });
    await _bootstrapWeekPlan(userInitiated: true);
  }

  /// 'Active plan' summary, same shape as the week-plan row (goal · kcal/day).
  String _planSummary() {
    final day = _selPlanDay;
    final goal = day?.goal.trim() ?? '';
    final goalLabel =
        goal.isEmpty ? 'Plan' : '${goal[0].toUpperCase()}${goal.substring(1)}';
    return '$goalLabel · ${_fmtInt(day?.calories ?? _goals.calories)} kcal/day';
  }

  /// Plan RESULT view (prototype sheetPlan result step, HTML 761–786):
  /// 'Active plan' summary chip + per-day cards with colored meal-dot rows,
  /// Adjust (reopens the quiz → regenerate) / Activate plan footer.
  void _openWeekPlanSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _PlanResultSheet(
        weekPlan: _weekPlan,
        summary: _planSummary(),
        onDayTap: _openDayMealPlan,
        onAdjust: () {
          Navigator.of(sheetCtx).pop();
          _openPlanQuizSheet();
        },
        onActivate: () {
          Navigator.of(sheetCtx).pop();
          _toast('Plan activated for this week ✨');
        },
      ),
    );
  }

  // Calories hero — ring + consumed/goal/left (HTML 279–292).
  Widget _caloriesHero() {
    final goal = _goals.calories;
    final consumed = _totals.calories.round();
    final frac = goal <= 0 ? 0.0 : (consumed / goal).clamp(0.0, 1.0);
    final left = goal - consumed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: InkWell(
        onTap: _showGoalsSheet, // goals editor lives behind the calories card
        borderRadius: BorderRadius.circular(28),
        child: Container(
          clipBehavior: Clip.antiAlias,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          decoration: BoxDecoration(
            gradient: ZveltTokens.heroGrad,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: ZveltTokens.heroBorder),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -60,
                top: -50,
                child: Container(
                  width: 210,
                  height: 210,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                        colors: [Color(0x4DF58214), Color(0x00F58214)]),
                  ),
                ),
              ),
              Row(
                children: [
                  SizedBox(
                    width: 118,
                    height: 118,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        RepaintBoundary(
                          child: CustomPaint(
                            size: const Size(118, 118),
                            painter: _CalorieRingPainter(
                                progress: frac, track: ZveltTokens.track),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${(frac * 100).round()}%',
                                style: ZType.stat.copyWith(fontSize: 28)),
                            Text('filled',
                                style: ZType.bodyS.copyWith(
                                    fontSize: 11, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Calories',
                            style: ZType.bodyL.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: ZveltTokens.text2)),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(_fmtInt(consumed),
                                    style: ZType.stat
                                        .copyWith(fontSize: 40, height: 1)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text('/ ${_fmtInt(goal)} cal',
                                style: ZType.bodyS.copyWith(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          left >= 0
                              ? '${_fmtInt(left)} cal left today'
                              : '${_fmtInt(-left)} cal over today',
                          style: ZType.bodyS.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: ZveltTokens.brand),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Macros card — Carbs / Fat / Protein bars with knob (HTML 294–298).
  Widget _macrosCard() {
    Widget macro(String label, double value, int goal, Color color,
        {bool trailingGap = true}) {
      final frac = goal <= 0 ? 0.0 : (value / goal).clamp(0.0, 1.0);
      return Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: trailingGap ? 14 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('${value.round()}',
                      style: ZType.stat.copyWith(fontSize: 22)),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text('/$goal g',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZType.bodyS.copyWith(
                            fontSize: 11.5, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text(label,
                  style: ZType.bodyS
                      .copyWith(fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 9),
              SizedBox(
                height: 10,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final x = frac * c.maxWidth;
                    return Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.centerLeft,
                      children: [
                        Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: ZveltTokens.track,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        Container(
                          height: 6,
                          width: x,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        Positioned(
                          left: (x - 5).clamp(0.0, c.maxWidth - 10),
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color,
                              border:
                                  Border.all(color: ZveltTokens.bg, width: 2.5),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
        decoration: BoxDecoration(
          gradient: ZveltTokens.surfaceGrad,
          borderRadius: BorderRadius.circular(ZveltTokens.rCard),
          border: Border.all(color: ZveltTokens.border),
        ),
        child: Row(
          children: [
            macro('Carbs', _totals.carbs, _goals.carbsG, ZveltTokens.brand),
            macro('Fat', _totals.fat, _goals.fatG, const Color(0xFFE8A33D)),
            macro('Protein', _totals.protein, _goals.proteinG,
                const Color(0xFFE8724E),
                trailingGap: false),
          ],
        ),
      ),
    );
  }

  static String _fmtInt(int v) {
    final s = '$v';
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '$buf';
  }

  void _showGoalsSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GoalsSheet(
        goals: _goals,
        onSave: (g) async {
          await _service.saveGoals(g);
          await _load(showSpinner: false);
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// sheetPlan — AI Meal Plan (prototype HTML 735–786). Two steps: the QUIZ
// (diet / goal / meals-per-day segmented rows + 'Generate plan') and the
// RESULT view ('Active plan' chip + day cards with colored meal-dot rows +
// Adjust / Activate plan footer). In the app they are two sheets: the quiz
// pops its answers to the caller (which runs the real server generation) and
// the result view renders the REAL stored week plan.
// ─────────────────────────────────────────────────────────────────────────────

/// Shared sheet header (prototype HTML 738–741): 32px gradient icon box +
/// 'AI Meal Plan' + 34px close button.
Widget _planSheetHeader(BuildContext context) {
  return Row(
    children: [
      Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [ZveltTokens.brand2, ZveltTokens.brandDeep],
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child:
            const Icon(AppIcons.sparkles, size: 17, color: ZveltTokens.onBrand),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: Text('AI Meal Plan',
            style:
                ZType.h4.copyWith(fontSize: 19, fontWeight: FontWeight.w800)),
      ),
      Semantics(
        button: true,
        label: 'Close meal plan',
        child: Tooltip(
          message: 'Close',
          child: SizedBox(
            width: 48,
            height: 48,
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              customBorder: const CircleBorder(),
              child: Center(
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ZveltTokens.chip,
                    border: Border.all(color: ZveltTokens.border),
                  ),
                  child: Icon(AppIcons.cross_small,
                      size: 16, color: ZveltTokens.text2),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _PlanQuizSheet extends StatefulWidget {
  const _PlanQuizSheet({required this.goals});

  final NutritionGoals goals;

  @override
  State<_PlanQuizSheet> createState() => _PlanQuizSheetState();
}

class _PlanQuizSheetState extends State<_PlanQuizSheet> {
  late String _diet;
  late String _goal;
  late String _activity;
  late int _meals;

  @override
  void initState() {
    super.initState();
    _diet = widget.goals.diet;
    _goal = widget.goals.goal;
    _activity = widget.goals.activityLevel;
    _meals = widget.goals.mealsPerDay;
  }

  /// Segmented row (prototype HTML 746–756): chip container radius 16,
  /// selected segment = brand bg radius 13.
  Widget _segRow<T>(
      List<(T, String)> opts, T current, ValueChanged<T> onSelect) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ZveltTokens.chip,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ZveltTokens.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < opts.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: InkWell(
                onTap: () => onSelect(opts[i].$1),
                borderRadius: BorderRadius.circular(13),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: current == opts[i].$1 ? ZveltTokens.brand : null,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  // Five activity options share one row. Scale only when a
                  // user's text setting or a long label needs the space; the
                  // value must remain readable rather than becoming "Modera…".
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(opts[i].$2,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: ZType.bodyS.copyWith(
                            fontSize: 13,
                            fontWeight: current == opts[i].$1
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: current == opts[i].$1
                                ? ZveltTokens.onBrand
                                : ZveltTokens.text2)),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _question(String text) => Text(text,
      style: ZType.bodyS.copyWith(
          fontSize: 13, fontWeight: FontWeight.w700, color: ZveltTokens.text));

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
      decoration: BoxDecoration(
        gradient: ZveltTokens.sheetGrad,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(ZveltTokens.rSheet)),
        border: Border.all(color: ZveltTokens.border),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 34),
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
          _planSheetHeader(context),
          const SizedBox(height: 18),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _question("What's your diet?"),
                  const SizedBox(height: 10),
                  _segRow<String>(
                    const [
                      ('omnivore', 'Omnivore'),
                      ('vegetarian', 'Vegetarian'),
                      ('vegan', 'Vegan'),
                    ],
                    _diet,
                    (v) => setState(() => _diet = v),
                  ),
                  const SizedBox(height: 20),
                  _question('Your goal?'),
                  const SizedBox(height: 10),
                  _segRow<String>(
                    const [
                      ('lose', 'Lose'),
                      ('maintain', 'Maintain'),
                      ('gain', 'Gain'),
                    ],
                    _goal,
                    (v) => setState(() => _goal = v),
                  ),
                  const SizedBox(height: 20),
                  _question('Daily activity?'),
                  const SizedBox(height: 10),
                  _segRow<String>(
                    const [
                      ('sedentary', 'Low'),
                      ('light', 'Light'),
                      ('moderate', 'Moderate'),
                      ('active', 'Active'),
                      ('very_active', 'High'),
                    ],
                    _activity,
                    (v) => setState(() => _activity = v),
                  ),
                  const SizedBox(height: 20),
                  _question('Meals per day?'),
                  const SizedBox(height: 10),
                  _segRow<int>(
                    const [(3, '3 meals'), (4, '4 meals')],
                    _meals,
                    (v) => setState(() => _meals = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          InkWell(
            onTap: () => Navigator.of(context).pop((
              diet: _diet,
              goal: _goal,
              activity: _activity,
              meals: _meals,
            )),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                color: ZveltTokens.brand,
                borderRadius: BorderRadius.circular(16),
                boxShadow: ZveltTokens.glowMd,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(AppIcons.sparkles,
                      size: 16, color: ZveltTokens.onBrand),
                  const SizedBox(width: 7),
                  Text('Generate plan',
                      style: ZType.bodyM.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: ZveltTokens.onBrand)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanResultSheet extends StatelessWidget {
  const _PlanResultSheet({
    required this.weekPlan,
    required this.summary,
    required this.onDayTap,
    required this.onAdjust,
    required this.onActivate,
  });

  final List<NutritionPlanDay> weekPlan;
  final String summary;
  final void Function(NutritionPlanDay day) onDayTap;
  final VoidCallback onAdjust;
  final VoidCallback onActivate;

  // Prototype dotColors (JS 1920): Breakfast=accent, Lunch/Dinner/Snack fixed.
  static Color _dotColor(String mealKey) => switch (mealKey.toLowerCase()) {
        'breakfast' => ZveltTokens.brand,
        'lunch' => const Color(0xFFE8A33D),
        'dinner' => const Color(0xFFC9822F),
        _ => const Color(0xFF5F5346),
      };

  static String _mealTypeLabel(String mealKey) =>
      switch (mealKey.toLowerCase()) {
        'breakfast' => 'Breakfast',
        'lunch' => 'Lunch',
        'dinner' => 'Dinner',
        _ => 'Snack',
      };

  static String _dow(String ymd) {
    final d = DateTime.tryParse(ymd);
    if (d == null) return ymd;
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[d.weekday - 1];
  }

  Widget _mealRow(NutritionPlannedMeal meal) {
    final name = meal.items
        .map((i) => i.text.trim())
        .where((t) => t.isNotEmpty)
        .join(', ');
    var kcal = 0;
    for (final item in meal.items) {
      kcal += item.macros?.calories ?? 0;
    }
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
              shape: BoxShape.circle, color: _dotColor(meal.mealKey)),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 64,
          child: Text(_mealTypeLabel(meal.mealKey),
              style: ZType.bodyS.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: ZveltTokens.text3)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ZType.bodyS.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ZveltTokens.text)),
        ),
        if (kcal > 0) ...[
          const SizedBox(width: 10),
          Text('$kcal',
              style: ZType.bodyS
                  .copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ],
    );
  }

  Widget _dayCard(NutritionPlanDay day) {
    final meals = day.mealPlan?.meals ?? const <NutritionPlannedMeal>[];
    return InkWell(
      onTap: () => onDayTap(day),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: ZveltTokens.surface2Grad,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ZveltTokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_dow(day.day),
                style: ZType.bodyM
                    .copyWith(fontSize: 14, fontWeight: FontWeight.w800)),
            if (meals.isEmpty) ...[
              const SizedBox(height: 11),
              // Macros-only day (no AI meal lines stored) — honest targets.
              Text(
                '${day.calories} kcal · P${day.proteinG} C${day.carbsG} F${day.fatG}',
                style: ZType.bodyS
                    .copyWith(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ] else ...[
              const SizedBox(height: 11),
              for (var i = 0; i < meals.length; i++) ...[
                if (i > 0) const SizedBox(height: 9),
                _mealRow(meals[i]),
              ],
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
      decoration: BoxDecoration(
        gradient: ZveltTokens.sheetGrad,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(ZveltTokens.rSheet)),
        border: Border.all(color: ZveltTokens.border),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 34),
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
          _planSheetHeader(context),
          const SizedBox(height: 16),
          // 'Active plan' summary chip (HTML 762–764).
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: ZveltTokens.chip,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ZveltTokens.border),
            ),
            child: Column(
              children: [
                Text('Active plan',
                    style: ZType.bodyS
                        .copyWith(fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(summary,
                    style: ZType.bodyM
                        .copyWith(fontSize: 13.5, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: weekPlan.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _dayCard(weekPlan[i]),
            ),
          ),
          const SizedBox(height: 16),
          // Footer (HTML 782–785): Adjust reopens the quiz (regenerate
          // options), Activate plan closes — the shown plan IS the week's
          // active plan (already stored server-side).
          Row(
            children: [
              Expanded(
                flex: 46,
                child: InkWell(
                  onTap: onAdjust,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: ZveltTokens.chip,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: ZveltTokens.borderStrong),
                    ),
                    child: Center(
                      child: Text('Adjust',
                          style: ZType.bodyM.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: ZveltTokens.text)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                flex: 54,
                child: InkWell(
                  onTap: onActivate,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: ZveltTokens.brand,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: ZveltTokens.glowMd,
                    ),
                    child: Center(
                      child: Text('Activate plan',
                          style: ZType.bodyM.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: ZveltTokens.onBrand)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CALORIES CARD
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// ADD FOOD SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _AddFoodSheet extends StatefulWidget {
  const _AddFoodSheet({required this.meal, required this.onAdd});
  final String meal;
  final Future<void> Function(MealEntry) onAdd;

  @override
  State<_AddFoodSheet> createState() => _AddFoodSheetState();
}

class _AddFoodSheetState extends State<_AddFoodSheet> {
  static String _mealTitle(String key) => switch (key) {
        'breakfast' => 'Breakfast',
        'lunch' => 'Lunch',
        'dinner' => 'Dinner',
        _ => 'Snacks',
      };

  static const Duration _searchDebounce = Duration(milliseconds: 500);

  final _service = NutritionService.instance;
  final _searchCtrl = TextEditingController();
  List<FoodItem> _results = [];
  bool _loading = false;
  bool _hasSearched = false;
  String? _searchError;
  Timer? _debounce;
  int _searchGeneration = 0;

  Future<void> _search(String q) async {
    final trimmed = q.trim();
    if (trimmed.length < 3) {
      // Bump the generation so an in-flight search for the longer query
      // can't land after the clear and show results for text the field no
      // longer contains.
      _searchGeneration++;
      if (mounted) {
        setState(() {
          _results = [];
          _loading = false;
          _hasSearched = false;
          _searchError = null;
        });
      }
      return;
    }
    final gen = ++_searchGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _hasSearched = true;
        _searchError = null;
      });
    }
    final outcome = await _service.searchByName(trimmed);
    if (!mounted || gen != _searchGeneration) return;
    setState(() {
      _results = outcome.items;
      _searchError = outcome.errorMessage;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _selectFood(FoodItem food) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PortionSheet(
        food: food,
        meal: widget.meal,
        onAdd: (entry) async {
          Navigator.pop(context); // close portion sheet
          Navigator.pop(context); // close search sheet
          await widget.onAdd(entry);
        },
      ),
    );
  }

  // ── Tabs: Search · Recent · Favorites · Custom · Meals · Recipes ─────────
  static const List<String> _tabLabels = [
    'Search',
    'Recent',
    'Favorites',
    'Custom',
    'Meals',
    'Recipes'
  ];
  int _tab = 0;
  bool _tabLoading = false;
  List<FoodItem> _recent = [];
  List<FoodItem> _favorites = [];
  List<FoodItem> _custom = [];
  List<MealTemplate> _templates = [];
  List<Recipe> _recipes = [];
  final Set<String> _favIds = {};
  final Set<int> _loadedTabs = {0};

  @override
  void initState() {
    super.initState();
    _refreshFavIds();
  }

  Future<void> _refreshFavIds() async {
    final favs = await _service.getFavoriteFoods();
    if (!mounted) return;
    setState(() {
      _favorites = favs;
      _favIds
        ..clear()
        ..addAll(favs.map((f) => f.id));
      _loadedTabs.add(2);
    });
  }

  Future<void> _selectTab(int tab) async {
    setState(() => _tab = tab);
    if (_loadedTabs.contains(tab)) return;
    setState(() => _tabLoading = true);
    try {
      if (tab == 1) {
        _recent = await _service.getRecentFoods();
      } else if (tab == 3) {
        _custom = await _service.getCustomFoods();
      } else if (tab == 4) {
        _templates = await _service.getMealTemplates();
      } else if (tab == 5) {
        _recipes = await _service.getRecipes();
      }
      _loadedTabs.add(tab);
    } finally {
      if (mounted) setState(() => _tabLoading = false);
    }
  }

  Future<void> _toggleFavorite(FoodItem food) async {
    final wasFav = _favIds.contains(food.id);
    setState(() {
      if (wasFav) {
        _favIds.remove(food.id);
        _favorites.removeWhere((f) => f.id == food.id);
      } else {
        _favIds.add(food.id);
        _favorites = [food, ..._favorites.where((f) => f.id != food.id)];
      }
    });
    try {
      if (wasFav) {
        await _service.removeFavorite(food.id);
      } else {
        await _service.addFavorite(food);
      }
    } catch (_) {
      if (mounted) await _refreshFavIds();
    }
  }

  Widget _foodTile(FoodItem food) {
    final brandPart = food.brand.isNotEmpty ? '${food.brand} · ' : '';
    final isFav = _favIds.contains(food.id);
    return ListTile(
      title: Text(food.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ZType.bodyM.copyWith(
              color: ZveltTokens.text,
              fontSize: 13,
              fontWeight: FontWeight.w600)),
      subtitle: Text('$brandPart${food.caloriesPer100g.round()} kcal/100g',
          style: ZType.bodyS.copyWith(color: ZveltTokens.text2, fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(isFav ? AppIcons.heart : AppIcons.heart,
                color: isFav ? ZveltTokens.brand : ZveltTokens.text3, size: 18),
            tooltip: isFav ? 'Remove from favorites' : 'Add to favorites',
            onPressed: () => _toggleFavorite(food),
          ),
          const Icon(AppIcons.plus, color: ZveltTokens.brand, size: 20),
        ],
      ),
      onTap: () => _selectFood(food),
    );
  }

  Widget _emptyHint(IconData icon, String text) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(shape: BoxShape.circle)
                  .copyWith(color: ZveltTokens.surface2),
              child: Icon(icon, color: ZveltTokens.text3, size: 28),
            ),
            const SizedBox(height: ZveltTokens.s4),
            Text(text,
                textAlign: TextAlign.center,
                style: ZType.bodyM
                    .copyWith(color: ZveltTokens.text2, fontSize: 13)),
          ],
        ),
      );

  Widget _altTabBody(ScrollController controller) {
    if (_tabLoading) {
      return const Center(
          child: CircularProgressIndicator(color: ZveltTokens.brand));
    }
    if (_tab == 1) {
      if (_recent.isEmpty) {
        return _emptyHint(AppIcons.clock, 'No recent foods yet');
      }
      return ListView.builder(
        controller: controller,
        itemCount: _recent.length,
        itemBuilder: (_, i) => _foodTile(_recent[i]),
      );
    }
    if (_tab == 2) {
      if (_favorites.isEmpty) {
        return _emptyHint(
            AppIcons.heart, 'No favorites yet. Tap the heart on a food.');
      }
      return ListView.builder(
        controller: controller,
        itemCount: _favorites.length,
        itemBuilder: (_, i) => _foodTile(_favorites[i]),
      );
    }
    if (_tab == 3) {
      return ListView(
        controller: controller,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                ZveltTokens.s4, ZveltTokens.s2, ZveltTokens.s4, ZveltTokens.s2),
            child: OutlinedButton.icon(
              onPressed: _openCustomForm,
              icon: const Icon(AppIcons.plus, size: 18),
              label: const Text('Create custom food'),
            ),
          ),
          if (_custom.isEmpty)
            Padding(
              padding: const EdgeInsets.all(ZveltTokens.s6),
              child: _emptyHint(AppIcons.restaurant, 'No custom foods yet'),
            )
          else
            for (final f in _custom) _customTile(f),
        ],
      );
    }
    if (_tab == 4) {
      // Meals (saved meal templates)
      if (_templates.isEmpty) {
        return _emptyHint(AppIcons.restaurant, 'No saved meals yet');
      }
      return ListView.builder(
        controller: controller,
        itemCount: _templates.length,
        itemBuilder: (_, i) {
          final t = _templates[i];
          return ListTile(
            title: Text(t.name,
                style: ZType.bodyM.copyWith(
                    color: ZveltTokens.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            subtitle: Text(
                '${t.itemCount} foods · ${t.totalCalories.round()} kcal',
                style: ZType.bodyS
                    .copyWith(color: ZveltTokens.text2, fontSize: 12)),
            trailing:
                const Icon(AppIcons.plus, color: ZveltTokens.brand, size: 20),
            onTap: () => _applyTemplate(t),
          );
        },
      );
    }
    // _tab == 5 — Recipes
    return ListView(
      controller: controller,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              ZveltTokens.s4, ZveltTokens.s2, ZveltTokens.s4, ZveltTokens.s2),
          child: OutlinedButton.icon(
            onPressed: () => _openRecipeBuilder(),
            icon: const Icon(AppIcons.plus, size: 18),
            label: const Text('Create recipe'),
          ),
        ),
        if (_recipes.isEmpty)
          Padding(
            padding: const EdgeInsets.all(ZveltTokens.s6),
            child: _emptyHint(AppIcons.restaurant, 'No recipes yet'),
          )
        else
          for (final r in _recipes) _recipeTile(r),
      ],
    );
  }

  Widget _recipeTile(Recipe r) {
    final perServ =
        r.servings > 0 ? r.totalCalories / r.servings : r.totalCalories;
    return ListTile(
      title: Text(r.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ZType.bodyM.copyWith(
              color: ZveltTokens.text,
              fontSize: 13,
              fontWeight: FontWeight.w600)),
      subtitle: Text(
          '${r.ingredients.length} ingr · ${perServ.round()} kcal/serving · ${r.servings} servings',
          style: ZType.bodyS.copyWith(color: ZveltTokens.text2, fontSize: 12)),
      trailing: PopupMenuButton<String>(
        icon: Icon(AppIcons.menu_dots_vertical,
            color: ZveltTokens.text3, size: 16),
        onSelected: (v) {
          if (v == 'apply') _applyRecipe(r);
          if (v == 'edit') _openRecipeBuilder(editing: r);
          if (v == 'delete') _deleteRecipe(r);
        },
        itemBuilder: (_) => const [
          PopupMenuItem<String>(value: 'apply', child: Text('Add to log')),
          PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
          PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: () => _applyRecipe(r),
    );
  }

  Future<void> _openRecipeBuilder({Recipe? editing}) async {
    final saved = await Navigator.of(context).push<Recipe>(
      MaterialPageRoute<Recipe>(
          builder: (_) => RecipeBuilderScreen(editing: editing)),
    );
    if (!mounted || saved == null) return;
    setState(() {
      _recipes = [saved, ..._recipes.where((r) => r.id != saved.id)];
    });
  }

  Future<void> _applyRecipe(Recipe r) async {
    final servings = await showDialog<double>(
      context: context,
      builder: (_) => _ServingsDialog(recipe: r),
    );
    if (!mounted || servings == null) return;
    Navigator.pop(context); // close add-food sheet
    await widget
        .onAdd(r.toMealEntry(meal: widget.meal, servingsToLog: servings));
  }

  Future<void> _deleteRecipe(Recipe r) async {
    setState(() => _recipes = _recipes.where((x) => x.id != r.id).toList());
    try {
      await _service.deleteRecipe(r.id);
    } catch (_) {/* best-effort */}
  }

  Future<void> _applyTemplate(MealTemplate t) async {
    Navigator.pop(context); // close add-food sheet
    for (final item in t.items) {
      await widget.onAdd(item.toMealEntry(widget.meal));
    }
  }

  Future<void> _openQuickAdd() async {
    final entry = await showModalBottomSheet<MealEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickAddSheet(meal: widget.meal),
    );
    if (!mounted || entry == null) return;
    Navigator.pop(context); // close add-food sheet
    await widget.onAdd(entry);
  }

  Future<void> _openCustomForm() async {
    final created = await showModalBottomSheet<FoodItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CustomFoodSheet(),
    );
    if (!mounted || created == null) return;
    setState(() => _custom = [created, ..._custom]);
    _selectFood(created);
  }

  Widget _customTile(FoodItem food) {
    final brandPart = food.brand.isNotEmpty ? '${food.brand} · ' : '';
    return ListTile(
      title: Text(food.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ZType.bodyM.copyWith(
              color: ZveltTokens.text,
              fontSize: 13,
              fontWeight: FontWeight.w600)),
      subtitle: Text('$brandPart${food.caloriesPer100g.round()} kcal/100g',
          style: ZType.bodyS.copyWith(color: ZveltTokens.text2, fontSize: 12)),
      trailing: PopupMenuButton<String>(
        icon: Icon(AppIcons.menu_dots_vertical,
            color: ZveltTokens.text3, size: 16),
        onSelected: (v) {
          if (v == 'add') _selectFood(food);
          if (v == 'edit') _editCustom(food);
          if (v == 'delete') _deleteCustom(food);
        },
        itemBuilder: (_) => const [
          PopupMenuItem<String>(value: 'add', child: Text('Add to log')),
          PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
          PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: () => _selectFood(food),
    );
  }

  Future<void> _editCustom(FoodItem food) async {
    final updated = await showModalBottomSheet<FoodItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CustomFoodSheet(editing: food),
    );
    if (!mounted || updated == null) return;
    setState(() => _custom =
        _custom.map((f) => f.id == updated.id ? updated : f).toList());
  }

  Future<void> _deleteCustom(FoodItem food) async {
    setState(() => _custom = _custom.where((f) => f.id != food.id).toList());
    try {
      await _service.deleteCustomFood(food.id);
    } catch (_) {/* best-effort */}
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          gradient: ZveltTokens.sheetGrad,
          color: ZveltTokens.surface,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(ZveltTokens.rSheet)),
          border: Border.all(color: ZveltTokens.border),
        ),
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: ZveltTokens.s3),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: ZveltTokens.track,
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
            ),
            // Prototype sheetAddFood header (HTML 681–684).
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Add to ${_mealTitle(widget.meal)}',
                            style: ZType.h4.copyWith(
                                fontSize: 19, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text('Tap a food to log it',
                            style: ZType.bodyS.copyWith(
                                fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Close food search',
                    child: Tooltip(
                      message: 'Close',
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(),
                          customBorder: const CircleBorder(),
                          child: Center(
                            child: Container(
                              width: 34,
                              height: 34,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: ZveltTokens.chip,
                                border: Border.all(color: ZveltTokens.border),
                              ),
                              child: Icon(AppIcons.cross_small,
                                  size: 16, color: ZveltTokens.text2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  ZveltTokens.s4, ZveltTokens.s1, ZveltTokens.s4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      style: ZType.bodyM.copyWith(color: ZveltTokens.text),
                      onSubmitted: (_) {
                        _debounce?.cancel();
                        _search(_searchCtrl.text);
                      },
                      onChanged: (v) {
                        _debounce?.cancel();
                        final t = _searchCtrl.text.trim();
                        if (t.length < 3) {
                          _searchGeneration++; // discard in-flight results
                          if (mounted) {
                            setState(() {
                              _results = [];
                              _loading = false;
                              _hasSearched = false;
                              _searchError = null;
                            });
                          }
                          return;
                        }
                        _debounce = Timer(
                            _searchDebounce, () => _search(_searchCtrl.text));
                      },
                      decoration: InputDecoration(
                        hintText: 'Search foods…',
                        hintStyle:
                            ZType.bodyM.copyWith(color: ZveltTokens.text3),
                        prefixIcon: Icon(AppIcons.search,
                            color: ZveltTokens.text3, size: 20),
                        filled: true,
                        fillColor: ZveltTokens.surface2,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: ZveltTokens.s3,
                            horizontal: ZveltTokens.s3),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(ZveltTokens.rPill),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(ZveltTokens.rPill),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(ZveltTokens.rPill),
                          borderSide: const BorderSide(
                              color: ZveltTokens.brand, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: ZveltTokens.s2),
                  Container(
                    decoration: BoxDecoration(
                      color: ZveltTokens.brandTint,
                      borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                    ),
                    child: IconButton(
                      icon: const Icon(AppIcons.bolt),
                      color: ZveltTokens.brand,
                      tooltip: 'Quick add calories',
                      onPressed: _openQuickAdd,
                    ),
                  ),
                  const SizedBox(width: ZveltTokens.s2),
                  Container(
                    decoration: BoxDecoration(
                      color: ZveltTokens.brandTint,
                      borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                    ),
                    child: IconButton(
                      icon: const Icon(AppIcons.barcode_scan),
                      color: ZveltTokens.brand,
                      tooltip: 'Scan barcode',
                      onPressed: () => _showBarcodeInput(),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4),
                itemCount: _tabLabels.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: ZveltTokens.s2),
                itemBuilder: (_, i) {
                  final sel = _tab == i;
                  return GestureDetector(
                    onTap: () => _selectTab(i),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                          horizontal: ZveltTokens.s4),
                      decoration: BoxDecoration(
                        color: sel ? ZveltTokens.brand : ZveltTokens.surface2,
                        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                      ),
                      child: Text(_tabLabels[i],
                          style: ZType.bodyS.copyWith(
                            color:
                                sel ? ZveltTokens.onBrand : ZveltTokens.text2,
                            fontSize: 12,
                            fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                          )),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: ZveltTokens.s2),
            if (_tab == 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    ZveltTokens.s5, 0, ZveltTokens.s5, ZveltTokens.s2),
                child: Text(
                  'USDA + Open Food Facts · type 3+ letters and wait, or scan.',
                  style: ZType.bodyS.copyWith(
                    color: ZveltTokens.text2,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ),
            if (_tab == 0 && _searchError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    ZveltTokens.s4, 0, ZveltTokens.s4, ZveltTokens.s2),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(ZveltTokens.s3),
                  decoration: BoxDecoration(
                    color: ZveltTokens.error.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(AppIcons.exclamation,
                          color: ZveltTokens.error, size: 16),
                      const SizedBox(width: ZveltTokens.s2),
                      Expanded(
                        child: Text(
                          _searchError!,
                          style: ZType.bodyS.copyWith(
                              color: ZveltTokens.text,
                              fontSize: 12,
                              height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: _tab != 0
                  ? _altTabBody(controller)
                  : _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: ZveltTokens.brand))
                      : _searchError != null
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 22),
                              child: Center(
                                child: Text(
                                  _searchError!,
                                  textAlign: TextAlign.center,
                                  style: ZType.bodyS.copyWith(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: ZveltTokens.error),
                                ),
                              ),
                            )
                          : _results.isEmpty
                              // Prototype addFoodEmpty (HTML 690) — single copy.
                              ? Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 22),
                                  child: Center(
                                    child: Text(
                                      _hasSearched
                                          ? 'No foods match your search.'
                                          : 'Search 3+ letters, scan a barcode, or choose a recent food.',
                                      textAlign: TextAlign.center,
                                      style: ZType.bodyS.copyWith(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  controller: controller,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  itemCount: _results.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 9),
                                  itemBuilder: (_, i) =>
                                      _resultRow(_results[i]),
                                ),
            ),
            // Prototype 'Done' footer (HTML 700): full-width chip button.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: ZveltTokens.chip,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: ZveltTokens.borderStrong),
                  ),
                  child: Center(
                    child: Text('Done',
                        style: ZType.bodyM.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: ZveltTokens.text)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Search result row — prototype pattern (HTML 692–697): surf2 rounded-16
  /// row, 34px icon box (r11), name 13.5/700, portion 11/500, kcal 12.5/700,
  /// 28px plus-circle in brand tint.
  Widget _resultRow(FoodItem food) {
    final sg = food.servingGrams;
    String portion;
    int kcal;
    if (sg != null && sg > 0) {
      final u = food.portionUnitKey ?? 'serving';
      portion =
          '${NutritionFoodLabels.formatUnitCount(1, u)} · ${sg.round()} g';
      kcal = (food.caloriesPer100g * sg / 100).round();
    } else {
      portion = '100 g';
      kcal = food.caloriesPer100g.round();
    }
    if (food.brand.isNotEmpty) portion = '${food.brand} · $portion';

    return InkWell(
      onTap: () => _selectFood(food),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: ZveltTokens.surface2Grad,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ZveltTokens.border),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ZveltTokens.chip,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: ZveltTokens.border),
              ),
              child:
                  Icon(AppIcons.restaurant, size: 16, color: ZveltTokens.text2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(food.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZType.bodyM.copyWith(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 1),
                  Text(portion,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZType.bodyS
                          .copyWith(fontSize: 11, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text('$kcal kcal',
                style: ZType.bodyS
                    .copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ZveltTokens.brandTint,
                border:
                    Border.all(color: ZveltTokens.brand.withValues(alpha: 0.4)),
              ),
              child:
                  const Icon(AppIcons.plus, size: 14, color: ZveltTokens.brand),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _promptManualBarcode() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter barcode'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(hintText: '5000112637922'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Search'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  void _showBarcodeInput() async {
    final mode = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: ZveltTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: ZveltTokens.s2),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ZveltTokens.border,
                borderRadius: BorderRadius.circular(ZveltTokens.rPill),
              ),
            ),
            const SizedBox(height: 6),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(ZveltTokens.s2),
                decoration: BoxDecoration(
                  color: ZveltTokens.brandTint,
                  borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                ),
                child: const Icon(AppIcons.camera,
                    color: ZveltTokens.brand, size: 18),
              ),
              title: Text('Scan with camera',
                  style:
                      ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 15)),
              subtitle: Text('EAN / UPC etc.',
                  style: ZType.bodyS
                      .copyWith(color: ZveltTokens.text2, fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'scan'),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(ZveltTokens.s2),
                decoration: BoxDecoration(
                  color: ZveltTokens.surface2,
                  borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                ),
                child: Icon(AppIcons.apps, color: ZveltTokens.text2, size: 18),
              ),
              title: Text('Enter manually',
                  style:
                      ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 15)),
              onTap: () => Navigator.pop(ctx, 'manual'),
            ),
            const SizedBox(height: ZveltTokens.s2),
          ],
        ),
      ),
    );

    if (!mounted || mode == null) return;

    String? barcode;
    if (mode == 'scan') {
      barcode = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const NutritionBarcodeScanScreen(),
        ),
      );
    } else {
      barcode = await _promptManualBarcode();
    }

    if (barcode == null || barcode.isEmpty) return;
    setState(() => _loading = true);
    final result = await _service.searchByBarcode(barcode);
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.food != null) {
      _selectFood(result.food!);
    } else if (mounted) {
      // 'Not found' ONLY when the lookup actually succeeded with no match —
      // network/USDA failures get their own honest message.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(result.errorMessage ?? 'Product not found in database.'),
        ),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PORTION SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _PortionSheet extends StatefulWidget {
  const _PortionSheet(
      {required this.food, required this.meal, required this.onAdd});
  final FoodItem food;
  final String meal;
  final Future<void> Function(MealEntry) onAdd;

  @override
  State<_PortionSheet> createState() => _PortionSheetState();
}

class _PortionSheetState extends State<_PortionSheet> {
  static const double _gramSliderMax = 500;

  /// Eggs, slices, etc. — whole-number slider steps; generic "serving" may stay fractional.
  static bool _usesWholeUnitIncrements(String unitKey) =>
      unitKey == 'egg' ||
      unitKey == 'slice' ||
      unitKey == 'waffle' ||
      unitKey == 'cookie';

  late bool _useUnits;
  late double _unitCount;
  late double _gramsDirect;
  bool _adding = false;

  bool get _hasServing =>
      widget.food.servingGrams != null && widget.food.servingGrams! > 0;

  bool get _wholeUnits => _usesWholeUnitIncrements(_unitKey);

  @override
  void initState() {
    super.initState();
    final sg = widget.food.servingGrams;
    if (sg != null && sg > 0) {
      _useUnits = true;
      _unitCount = 1;
      _gramsDirect = (sg * _unitCount).clamp(5, _gramSliderMax);
    } else {
      _useUnits = false;
      _unitCount = 1;
      _gramsDirect = 100;
    }
  }

  double get _effectiveGrams {
    if (_useUnits && _hasServing) {
      return widget.food.servingGrams! * _unitCount;
    }
    return _gramsDirect;
  }

  double get _calories => widget.food.caloriesPer100g * _effectiveGrams / 100;
  double get _protein => widget.food.proteinPer100g * _effectiveGrams / 100;
  double get _fat => widget.food.fatPer100g * _effectiveGrams / 100;
  double get _carbs => widget.food.carbsPer100g * _effectiveGrams / 100;

  String get _unitKey => widget.food.portionUnitKey ?? 'serving';

  void _syncMode({required bool toUnits}) {
    setState(() {
      if (!_hasServing) {
        _useUnits = false;
        return;
      }
      final sg = widget.food.servingGrams!;
      if (toUnits) {
        final raw = _gramsDirect / sg;
        if (_usesWholeUnitIncrements(widget.food.portionUnitKey ?? 'serving')) {
          _unitCount = raw.round().clamp(1, 24).toDouble();
        } else {
          _unitCount = raw.clamp(0.25, 80);
        }
        _useUnits = true;
      } else {
        _gramsDirect = (_unitCount * sg).clamp(5, _gramSliderMax);
        _useUnits = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final portionHint = widget.food.servingLabel;
    final sliderTheme = SliderTheme.of(context).copyWith(
      activeTrackColor: ZveltTokens.brand,
      inactiveTrackColor: ZveltTokens.surface2,
      thumbColor: ZveltTokens.brand,
      overlayColor: ZveltTokens.brand.withValues(alpha: 0.12),
    );
    return Container(
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
        boxShadow: ZveltTokens.shadowHero,
      ),
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: ZveltTokens.s3),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: ZveltTokens.border,
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                ZveltTokens.s5, ZveltTokens.s1, ZveltTokens.s5, 0),
            child: Text(widget.food.name,
                style:
                    ZType.h2.copyWith(color: ZveltTokens.text, fontSize: 18)),
          ),
          if (widget.food.brand.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: ZveltTokens.s5, top: 2),
              child: Text(widget.food.brand,
                  style: ZType.bodyS
                      .copyWith(color: ZveltTokens.text2, fontSize: 13)),
            ),
          const SizedBox(height: ZveltTokens.s4),
          if (_hasServing) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s5),
              child: Row(
                children: [
                  _PortionToggleChip(
                    label: 'Units',
                    selected: _useUnits,
                    onTap: () {
                      if (_hasServing && !_useUnits) _syncMode(toUnits: true);
                    },
                  ),
                  const SizedBox(width: ZveltTokens.s2),
                  _PortionToggleChip(
                    label: 'Grams',
                    selected: !_useUnits,
                    onTap: () {
                      if (_useUnits) _syncMode(toUnits: false);
                    },
                  ),
                ],
              ),
            ),
            if (portionHint != null && portionHint.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    ZveltTokens.s5, ZveltTokens.s2, ZveltTokens.s5, 0),
                child: Text(
                  'Label: $portionHint',
                  style: ZType.bodyS.copyWith(
                      color: ZveltTokens.text2, fontSize: 11, height: 1.3),
                ),
              ),
            const SizedBox(height: ZveltTokens.s3),
          ],
          if (_useUnits && _hasServing) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      NutritionFoodLabels.formatUnitCount(_unitCount, _unitKey),
                      style: ZType.stat
                          .copyWith(color: ZveltTokens.brand, fontSize: 15),
                    ),
                  ),
                  Text('${_effectiveGrams.round()} g total',
                      style: ZType.monoS.copyWith(
                        color: ZveltTokens.text2,
                      )),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3),
              child: SliderTheme(
                data: sliderTheme,
                child: Slider(
                  value: _wholeUnits
                      ? _unitCount.clamp(1, 24)
                      : _unitCount.clamp(0.25, 24),
                  min: _wholeUnits ? 1 : 0.25,
                  max: 24,
                  divisions: _wholeUnits ? 23 : null,
                  onChanged: (v) => setState(() {
                    _unitCount =
                        _wholeUnits ? v.round().clamp(1, 24).toDouble() : v;
                  }),
                ),
              ),
            ),
            if (_unitKey == 'egg')
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s5),
                child: Wrap(
                  spacing: ZveltTokens.s2,
                  children: [1, 2, 3, 4, 5, 6].map((n) {
                    final isSel = (_unitCount - n).abs() < 0.01;
                    return _PortionQuickChip(
                      label: '$n',
                      selected: isSel,
                      onTap: () => setState(() => _unitCount = n.toDouble()),
                    );
                  }).toList(),
                ),
              ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s5),
              child: Row(
                children: [
                  Text('Portion',
                      style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
                  const SizedBox(width: ZveltTokens.s3),
                  Expanded(
                    child: SliderTheme(
                      data: sliderTheme,
                      child: Slider(
                        value: _gramsDirect.clamp(5, _gramSliderMax),
                        min: 5,
                        max: _gramSliderMax,
                        divisions: 99,
                        onChanged: (v) => setState(() => _gramsDirect = v),
                      ),
                    ),
                  ),
                  Text('${_gramsDirect.round()}g',
                      style: ZType.stat
                          .copyWith(color: ZveltTokens.brand, fontSize: 15)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s5),
              child: Wrap(
                spacing: ZveltTokens.s2,
                children: [50, 100, 150, 200, 300].map((g) {
                  final isSel = _gramsDirect == g.toDouble();
                  return _PortionQuickChip(
                    label: '${g}g',
                    selected: isSel,
                    onTap: () => setState(() => _gramsDirect = g.toDouble()),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: ZveltTokens.s4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _NutrPreview(
                    label: 'Calories',
                    value: '${_calories.round()}',
                    unit: 'kcal',
                    color: ZveltTokens.brand),
                _NutrPreview(
                    label: 'Protein',
                    value: '${_protein.round()}',
                    unit: 'g',
                    color: ZveltTokens.strength),
                _NutrPreview(
                    label: 'Carbs',
                    value: '${_carbs.round()}',
                    unit: 'g',
                    color: ZveltTokens.brand),
                _NutrPreview(
                    label: 'Fat',
                    value: '${_fat.round()}',
                    unit: 'g',
                    color: ZveltTokens.strain),
              ],
            ),
          ),
          const SizedBox(height: ZveltTokens.s5),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                ZveltTokens.s5, 0, ZveltTokens.s5, ZveltTokens.s6),
            child: FilledButton(
              onPressed: _adding
                  ? null
                  : () async {
                      setState(() => _adding = true);
                      final entry = MealEntry(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        food: widget.food,
                        grams: _effectiveGrams,
                        meal: widget.meal,
                        loggedAt: DateTime.now(),
                      );
                      await widget.onAdd(entry);
                    },
              style: FilledButton.styleFrom(
                backgroundColor: ZveltTokens.brand,
                foregroundColor: ZveltTokens.onBrand,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                ),
              ),
              child: _adding
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: ZveltTokens.onBrand),
                    )
                  : Text('Add to diary',
                      style: ZType.h4
                          .copyWith(color: ZveltTokens.onBrand, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PortionToggleChip extends StatelessWidget {
  const _PortionToggleChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
            horizontal: ZveltTokens.s4, vertical: ZveltTokens.s2),
        decoration: BoxDecoration(
          color: selected ? ZveltTokens.brand : ZveltTokens.surface2,
          borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        ),
        child: Text(label,
            style: ZType.bodyS.copyWith(
              color: selected ? ZveltTokens.onBrand : ZveltTokens.text2,
              fontWeight: FontWeight.w700,
            )),
      ),
    );
  }
}

class _PortionQuickChip extends StatelessWidget {
  const _PortionQuickChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: ZveltTokens.s3, vertical: ZveltTokens.s2),
        decoration: BoxDecoration(
          color: selected ? ZveltTokens.brandTint : ZveltTokens.surface2,
          borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        ),
        child: Text(label,
            style: ZType.monoS.copyWith(
              color: selected ? ZveltTokens.brand : ZveltTokens.text2,
              fontWeight: FontWeight.w600,
            )),
      ),
    );
  }
}

class _NutrPreview extends StatelessWidget {
  const _NutrPreview(
      {required this.label,
      required this.value,
      required this.unit,
      required this.color});
  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: ZType.stat.copyWith(color: color, fontSize: 15)),
            const SizedBox(width: 1),
            Text(unit,
                style: ZType.monoXS.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                )),
          ],
        ),
        Text(label,
            style: ZType.monoXS.copyWith(
              color: ZveltTokens.text2,
              fontWeight: FontWeight.w500,
              height: 1.2,
            )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DAY MEAL PLAN (DeepSeek-generated, protein swaps editable)
// ─────────────────────────────────────────────────────────────────────────────

class _DayMealPlanSheet extends StatefulWidget {
  const _DayMealPlanSheet({
    required this.planDay,
    required this.onSave,
    required this.onRegenerateWeek,
  });

  final NutritionPlanDay planDay;
  final Future<void> Function(NutritionDayMealPlan plan) onSave;
  final Future<void> Function() onRegenerateWeek;

  @override
  State<_DayMealPlanSheet> createState() => _DayMealPlanSheetState();
}

class _DayMealPlanSheetState extends State<_DayMealPlanSheet> {
  NutritionDayMealPlan? _edited;
  bool _dirty = false;
  bool _saving = false;
  bool _autoSaving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.planDay.mealPlan;
    _edited = p == null ? null : NutritionDayMealPlan.deepCopy(p);
  }

  String _dowUi(String ymd) {
    final d = DateTime.tryParse(ymd);
    if (d == null) return ymd;
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${names[d.weekday - 1]} · $ymd';
  }

  String _dropdownValue(NutritionMealPlanItem item) {
    final c = item.proteinChoices!;
    final s = item.selectedProtein;
    if (s != null && s.isNotEmpty) {
      for (final x in c) {
        if (x.toLowerCase() == s.toLowerCase()) return x;
      }
    }
    return c.first;
  }

  void _patchItem(int mi, int ii, NutritionMealPlanItem next) {
    final meals = _edited!.meals;
    final meal = meals[mi];
    final nextMeal = meal.copyUpdatingItem(ii, next);
    setState(() {
      _edited = _edited!.copyUpdatingMeal(mi, nextMeal);
      _dirty = true;
    });
  }

  Future<void> _save({bool close = true}) async {
    if (!_dirty || _edited == null || _saving) return;
    setState(() => close ? _saving = true : _autoSaving = true);
    try {
      await widget.onSave(_edited!);
      if (!mounted) return;
      if (close) {
        Navigator.pop(context);
      } else {
        setState(() {
          _dirty = false;
          _autoSaving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _autoSaving = false;
        });
        if (close) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save: $e')),
          );
        }
      }
    } finally {
      if (mounted && close) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mh = MediaQuery.of(context).size.height;
    final p = widget.planDay;
    return SafeArea(
      child: SizedBox(
        height: mh * 0.9,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(ZveltTokens.rXl)),
          child: Material(
            color: ZveltTokens.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    margin:
                        const EdgeInsets.symmetric(vertical: ZveltTokens.s3),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: ZveltTokens.border,
                        borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      ZveltTokens.s5, 0, ZveltTokens.s3, ZveltTokens.s2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _dowUi(p.day),
                              style: ZType.h2.copyWith(
                                color: ZveltTokens.text,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${p.calories} kcal · P${p.proteinG} C${p.carbsG} F${p.fatG} · ${p.waterMl} ml',
                              style: ZType.monoS.copyWith(
                                color: ZveltTokens.text2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_autoSaving)
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: ZveltTokens.brand),
                              ),
                            ),
                          TextButton.icon(
                            onPressed: () async {
                              Navigator.pop(context);
                              await widget.onRegenerateWeek();
                            },
                            icon: const Icon(AppIcons.sparkles, size: 16),
                            label: const Text('Week AI'),
                            style: TextButton.styleFrom(
                                foregroundColor: ZveltTokens.brand),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: ZveltTokens.border),
                if (_edited == null || _edited!.meals.isEmpty)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(ZveltTokens.s6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(ZveltTokens.s4),
                            decoration: BoxDecoration(
                              color: ZveltTokens.surface2,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(AppIcons.restaurant,
                                color: ZveltTokens.text3, size: 32),
                          ),
                          const SizedBox(height: ZveltTokens.s4),
                          Text(
                            'No meal templates for this day yet. Regenerate the week with AI to populate meals.',
                            style: ZType.bodyS.copyWith(
                              color: ZveltTokens.text2,
                              height: 1.35,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: ZveltTokens.s5),
                          FilledButton.icon(
                            onPressed: () async {
                              Navigator.pop(context);
                              await widget.onRegenerateWeek();
                            },
                            icon: const Icon(AppIcons.sparkles, size: 16),
                            label: const Text('Regenerate week with AI'),
                            style: FilledButton.styleFrom(
                              backgroundColor: ZveltTokens.brand,
                              foregroundColor: ZveltTokens.onBrand,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(ZveltTokens.rPill),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: ZveltTokens.s5,
                                  vertical: ZveltTokens.s3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(ZveltTokens.s4,
                          ZveltTokens.s3, ZveltTokens.s4, ZveltTokens.s2),
                      children: [
                        for (var mi = 0; mi < _edited!.meals.length; mi++) ...[
                          Text(
                            _edited!.meals[mi].mealLabel,
                            style: ZType.eyebrow.copyWith(
                              color: ZveltTokens.brand,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...() {
                            final meal = _edited!.meals[mi];
                            return List.generate(meal.items.length, (ii) {
                              final item = meal.items[ii];
                              return Padding(
                                padding: const EdgeInsets.only(
                                    bottom: ZveltTokens.s3),
                                child: Container(
                                  padding: const EdgeInsets.all(ZveltTokens.s3),
                                  decoration: BoxDecoration(
                                    color: ZveltTokens.surface2,
                                    borderRadius:
                                        BorderRadius.circular(ZveltTokens.rMd),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        item.text,
                                        style: ZType.bodyS.copyWith(
                                            color: ZveltTokens.text,
                                            height: 1.35),
                                      ),
                                      if (item.portion != null &&
                                          item.portion!.trim().isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          item.portion!.trim(),
                                          style: ZType.bodyS.copyWith(
                                            color: ZveltTokens.text2,
                                            height: 1.35,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                      if (item.macros != null) ...[
                                        const SizedBox(height: 5),
                                        Text(
                                          '~${item.macros!.calories} kcal · P${item.macros!.proteinG} g '
                                          '· C${item.macros!.carbsG} g · F${item.macros!.fatG} g',
                                          style: ZType.monoXS.copyWith(
                                            color: ZveltTokens.text2,
                                            height: 1.25,
                                          ),
                                        ),
                                      ],
                                      if (item.hasProteinPicker) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          'Protein',
                                          style: ZType.eyebrow.copyWith(
                                            color: ZveltTokens.text3,
                                            fontSize: 11,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        InputDecorator(
                                          decoration: InputDecoration(
                                            filled: true,
                                            fillColor: ZveltTokens.surface,
                                            border: OutlineInputBorder(
                                              borderSide: BorderSide(
                                                  color: ZveltTokens.border),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      ZveltTokens.rSm),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderSide: BorderSide(
                                                  color: ZveltTokens.border),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      ZveltTokens.rSm),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: ZveltTokens.s3,
                                                    vertical: ZveltTokens.s1),
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              dropdownColor:
                                                  ZveltTokens.surface,
                                              value: _dropdownValue(item),
                                              isExpanded: true,
                                              style: ZType.bodyS.copyWith(
                                                  color: ZveltTokens.text),
                                              items: item.proteinChoices!
                                                  .map(
                                                    (s) => DropdownMenuItem<
                                                        String>(
                                                      value: s,
                                                      child: Text(s,
                                                          overflow: TextOverflow
                                                              .ellipsis),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: (v) {
                                                if (v == null) return;
                                                _patchItem(
                                                    mi,
                                                    ii,
                                                    item.copyWith(
                                                        selectedProtein: v));
                                                Future.microtask(
                                                    () => _save(close: false));
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            });
                          }(),
                          const SizedBox(height: 4),
                        ],
                      ],
                    ),
                  ),
                if (_edited != null && _edited!.meals.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      ZveltTokens.s4,
                      ZveltTokens.s2,
                      ZveltTokens.s4,
                      ZveltTokens.s3 +
                          MediaQuery.of(context).viewPadding.bottom +
                          MediaQuery.of(context).viewInsets.bottom,
                    ),
                    child: ZveltPrimaryButton(
                      label: _saving ? 'Saving…' : 'Save changes',
                      enabled: _dirty && !_saving,
                      onTap: _save,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GOALS SHEET
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// WATER SHEET (design parity — quick-add grid + custom input)
// ─────────────────────────────────────────────────────────────────────────────

class _WaterSheet extends StatefulWidget {
  const _WaterSheet({required this.currentMl});
  final int currentMl;

  @override
  State<_WaterSheet> createState() => _WaterSheetState();
}

class _WaterSheetState extends State<_WaterSheet> {
  late int _ml = widget.currentMl;

  Widget _quickAdd(int ml, String label) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _ml += ml),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s4),
          decoration: BoxDecoration(
            color: ZveltTokens.info.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(ZveltTokens.rMd),
          ),
          child: Column(
            children: [
              const Icon(AppIcons.water_bottle,
                  size: 18, color: ZveltTokens.recovery),
              const SizedBox(height: ZveltTokens.s1),
              Text(label,
                  style: ZType.bodyS.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ZveltTokens.recovery,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              ZveltTokens.s5, ZveltTokens.s3, ZveltTokens.s5, ZveltTokens.s4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: ZveltTokens.s4),
                decoration: BoxDecoration(
                  color: ZveltTokens.border,
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                ),
              ),
              Text('Water',
                  style:
                      ZType.h2.copyWith(color: ZveltTokens.text, fontSize: 18)),
              const SizedBox(height: ZveltTokens.s1),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('$_ml',
                      style: ZType.stat
                          .copyWith(fontSize: 34, color: ZveltTokens.recovery)),
                  const SizedBox(width: ZveltTokens.s1),
                  Text('ml',
                      style: ZType.monoS.copyWith(color: ZveltTokens.text3)),
                ],
              ),
              const SizedBox(height: ZveltTokens.s4),
              Row(
                children: [
                  _quickAdd(250, '+250ml'),
                  const SizedBox(width: ZveltTokens.s2),
                  _quickAdd(500, '+500ml'),
                  const SizedBox(width: ZveltTokens.s2),
                  _quickAdd(1000, '+1L'),
                ],
              ),
              const SizedBox(height: ZveltTokens.s3),
              TextButton(
                onPressed: () => setState(() => _ml = 0),
                child: Text('Reset to 0',
                    style: ZType.bodyS
                        .copyWith(fontSize: 12, color: ZveltTokens.text2)),
              ),
              const SizedBox(height: ZveltTokens.s1),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _ml),
                  style: FilledButton.styleFrom(
                    backgroundColor: ZveltTokens.brand,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ZveltTokens.rLg)),
                  ),
                  child: Text('Save',
                      style: ZType.bodyM.copyWith(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WEIGHT SHEET (design parity — ± stepper around the big value)
// ─────────────────────────────────────────────────────────────────────────────

class _WeightSheet extends StatefulWidget {
  const _WeightSheet({required this.initialKg});
  final double initialKg;

  @override
  State<_WeightSheet> createState() => _WeightSheetState();
}

class _WeightSheetState extends State<_WeightSheet> {
  late double _kg = widget.initialKg.clamp(30.0, 250.0);

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return Semantics(
      button: true,
      label: icon == AppIcons.plus ? 'Increase' : 'Decrease',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: ZveltTokens.surface2,
            borderRadius: BorderRadius.circular(ZveltTokens.rMd),
            border: Border.all(color: ZveltTokens.border),
          ),
          child: Icon(icon, size: 20, color: ZveltTokens.text),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              ZveltTokens.s5, ZveltTokens.s3, ZveltTokens.s5, ZveltTokens.s4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: ZveltTokens.s4),
                decoration: BoxDecoration(
                  color: ZveltTokens.border,
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                ),
              ),
              Text('Weight today',
                  style:
                      ZType.h2.copyWith(color: ZveltTokens.text, fontSize: 18)),
              const SizedBox(height: ZveltTokens.s4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _stepBtn(
                      AppIcons.minus,
                      () =>
                          setState(() => _kg = (_kg - 0.1).clamp(30.0, 250.0))),
                  const SizedBox(width: ZveltTokens.s5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(_kg.toStringAsFixed(1),
                          style: ZType.stat.copyWith(
                              fontSize: 34, color: ZveltTokens.brand)),
                      const SizedBox(width: ZveltTokens.s1),
                      Text('kg',
                          style: ZType.monoS.copyWith(
                              fontSize: 13, color: ZveltTokens.text3)),
                    ],
                  ),
                  const SizedBox(width: ZveltTokens.s5),
                  _stepBtn(
                      AppIcons.plus,
                      () =>
                          setState(() => _kg = (_kg + 0.1).clamp(30.0, 250.0))),
                ],
              ),
              const SizedBox(height: ZveltTokens.s5),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () => Navigator.pop(
                      context, double.parse(_kg.toStringAsFixed(1))),
                  style: FilledButton.styleFrom(
                    backgroundColor: ZveltTokens.brand,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ZveltTokens.rLg)),
                  ),
                  child: Text('Save',
                      style: ZType.bodyM.copyWith(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalsSheet extends StatefulWidget {
  const _GoalsSheet({required this.goals, required this.onSave});
  final NutritionGoals goals;
  final Future<void> Function(NutritionGoals) onSave;

  @override
  State<_GoalsSheet> createState() => _GoalsSheetState();
}

class _GoalsSheetState extends State<_GoalsSheet> {
  late final TextEditingController _calCtrl;
  late final TextEditingController _protCtrl;
  late final TextEditingController _fatCtrl;
  late final TextEditingController _carbsCtrl;
  late final TextEditingController _waterCtrl;

  @override
  void initState() {
    super.initState();
    _calCtrl = TextEditingController(text: widget.goals.calories.toString());
    _protCtrl = TextEditingController(text: widget.goals.proteinG.toString());
    _fatCtrl = TextEditingController(text: widget.goals.fatG.toString());
    _carbsCtrl = TextEditingController(text: widget.goals.carbsG.toString());
    _waterCtrl = TextEditingController(text: widget.goals.waterMl.toString());
  }

  @override
  void dispose() {
    _calCtrl.dispose();
    _protCtrl.dispose();
    _fatCtrl.dispose();
    _carbsCtrl.dispose();
    _waterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
        boxShadow: ZveltTokens.shadowHero,
      ),
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
              child: Container(
            margin: const EdgeInsets.symmetric(vertical: ZveltTokens.s3),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: ZveltTokens.border,
                borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
          )),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                ZveltTokens.s5, ZveltTokens.s1, ZveltTokens.s5, ZveltTokens.s4),
            child: Text('Daily goals',
                style:
                    ZType.h2.copyWith(color: ZveltTokens.text, fontSize: 18)),
          ),
          ...[
            ['Calories (kcal)', _calCtrl],
            ['Protein (g)', _protCtrl],
            ['Carbs (g)', _carbsCtrl],
            ['Fat (g)', _fatCtrl],
            ['Water (ml)', _waterCtrl],
          ].map((row) => Padding(
                padding: const EdgeInsets.fromLTRB(
                    ZveltTokens.s5, 0, ZveltTokens.s5, ZveltTokens.s3),
                child: TextField(
                  controller: row[1] as TextEditingController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: ZType.num_.copyWith(
                    color: ZveltTokens.text,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    labelText: row[0] as String,
                    labelStyle: ZType.bodyS.copyWith(color: ZveltTokens.text2),
                    filled: true,
                    fillColor: ZveltTokens.surface2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                      borderSide: const BorderSide(
                          color: ZveltTokens.brand, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
                  ),
                ),
              )),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                ZveltTokens.s5, ZveltTokens.s2, ZveltTokens.s5, ZveltTokens.s6),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () async {
                  // Validate instead of silently substituting defaults: a 0
                  // calorie goal made progress 0/0 = NaN (paint assert /
                  // garbage bar), and a cleared field used to save 2000 —
                  // a number the user never typed.
                  final cal = int.tryParse(_calCtrl.text);
                  final prot = int.tryParse(_protCtrl.text);
                  final fat = int.tryParse(_fatCtrl.text);
                  final carbs = int.tryParse(_carbsCtrl.text);
                  final water = int.tryParse(_waterCtrl.text);
                  if (cal == null ||
                      prot == null ||
                      fat == null ||
                      carbs == null ||
                      water == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Fill in every goal field.')),
                    );
                    return;
                  }
                  if (cal <= 0 ||
                      prot <= 0 ||
                      fat <= 0 ||
                      carbs <= 0 ||
                      water <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Goals must be greater than zero.')),
                    );
                    return;
                  }
                  final goals = widget.goals.copyWith(
                    calories: cal,
                    proteinG: prot,
                    fatG: fat,
                    carbsG: carbs,
                    waterMl: water,
                  );
                  await widget.onSave(goals);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: ZveltTokens.brand,
                  foregroundColor: ZveltTokens.onBrand,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                  ),
                ),
                child: Text('Save goals',
                    style: ZType.h4
                        .copyWith(color: ZveltTokens.onBrand, fontSize: 15)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared sheet scaffold + number field for the new food sheets ─────────────
Widget _sheetShell({required Widget child}) => Container(
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
      ),
      padding: const EdgeInsets.fromLTRB(
          ZveltTokens.s5, ZveltTokens.s4, ZveltTokens.s5, ZveltTokens.s6),
      child: child,
    );

Widget _sheetHandle() => Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: ZveltTokens.s4),
        decoration: BoxDecoration(
            color: ZveltTokens.border,
            borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
      ),
    );

Widget _numRow(String label, TextEditingController c, String hint) => Padding(
      padding: const EdgeInsets.only(bottom: ZveltTokens.s2),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: ZType.bodyM.copyWith(color: ZveltTokens.text))),
          SizedBox(
            width: 110,
            child: TextField(
              controller: c,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
              ],
              textAlign: TextAlign.center,
              style: ZType.num_.copyWith(color: ZveltTokens.text),
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                hintStyle: ZType.bodyS.copyWith(color: ZveltTokens.text4),
                filled: true,
                fillColor: ZveltTokens.surface2,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: ZveltTokens.s3, vertical: ZveltTokens.s3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );

double? _parseNum(TextEditingController c) =>
    double.tryParse(c.text.trim().replaceAll(',', '.'));

String _fmtNum(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// Quick-add: log a calories/macros entry without a food search.
class _QuickAddSheet extends StatefulWidget {
  const _QuickAddSheet({required this.meal});
  final String meal;
  @override
  State<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<_QuickAddSheet> {
  final _name = TextEditingController();
  final _cal = TextEditingController();
  final _p = TextEditingController();
  final _c = TextEditingController();
  final _f = TextEditingController();
  String? _error;

  @override
  void dispose() {
    for (final x in [_name, _cal, _p, _c, _f]) {
      x.dispose();
    }
    super.dispose();
  }

  void _add() {
    final cal = _parseNum(_cal);
    if (cal == null || cal <= 0) {
      setState(() => _error = 'Enter calories');
      return;
    }
    final food = FoodItem(
      id: 'quick:${DateTime.now().microsecondsSinceEpoch}',
      name: _name.text.trim().isEmpty ? 'Quick add' : _name.text.trim(),
      brand: 'Manual',
      caloriesPer100g: cal,
      proteinPer100g: _parseNum(_p) ?? 0,
      fatPer100g: _parseNum(_f) ?? 0,
      carbsPer100g: _parseNum(_c) ?? 0,
    );
    Navigator.pop(
      context,
      MealEntry(
        id: 'q${DateTime.now().microsecondsSinceEpoch}',
        food: food,
        grams: 100,
        meal: widget.meal,
        loggedAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _sheetShell(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sheetHandle(),
            Text('Quick add calories',
                style: ZType.h3.copyWith(color: ZveltTokens.text)),
            const SizedBox(height: ZveltTokens.s4),
            _numRow('Calories', _cal, 'kcal'),
            _numRow('Protein (g)', _p, 'opt'),
            _numRow('Carbs (g)', _c, 'opt'),
            _numRow('Fat (g)', _f, 'opt'),
            const SizedBox(height: ZveltTokens.s1),
            TextField(
              controller: _name,
              style: ZType.bodyM.copyWith(color: ZveltTokens.text),
              decoration: InputDecoration(
                hintText: 'Name (optional)',
                hintStyle: ZType.bodyS.copyWith(color: ZveltTokens.text3),
                filled: true,
                fillColor: ZveltTokens.surface2,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: ZveltTokens.s3, vertical: ZveltTokens.s3),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                    borderSide: BorderSide.none),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: ZveltTokens.s2),
              Text(_error!,
                  style: ZType.bodyS.copyWith(color: ZveltTokens.error)),
            ],
            const SizedBox(height: ZveltTokens.s4),
            SizedBox(
              height: 50,
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: ZveltTokens.brand,
                    foregroundColor: ZveltTokens.onBrand,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ZveltTokens.rMd))),
                onPressed: _add,
                child: Text('Add',
                    style: ZType.bodyM.copyWith(
                        color: ZveltTokens.onBrand,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Create or edit a custom food (saved to the user's catalog, synced).
class _CustomFoodSheet extends StatefulWidget {
  const _CustomFoodSheet({this.editing});
  final FoodItem? editing;
  @override
  State<_CustomFoodSheet> createState() => _CustomFoodSheetState();
}

class _CustomFoodSheetState extends State<_CustomFoodSheet> {
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _cal = TextEditingController();
  final _p = TextEditingController();
  final _c = TextEditingController();
  final _f = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _name.text = e.name;
      _brand.text = e.brand;
      _cal.text = _fmtNum(e.caloriesPer100g);
      _p.text = _fmtNum(e.proteinPer100g);
      _c.text = _fmtNum(e.carbsPer100g);
      _f.text = _fmtNum(e.fatPer100g);
    }
  }

  @override
  void dispose() {
    for (final x in [_name, _brand, _cal, _p, _c, _f]) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final cal = _parseNum(_cal);
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    if (cal == null || cal < 0) {
      setState(() => _error = 'Enter calories / 100g');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final svc = NutritionService.instance;
      final editing = widget.editing;
      final food = editing == null
          ? await svc.createCustomFood(
              name: name,
              brand: _brand.text.trim(),
              caloriesPer100g: cal,
              proteinPer100g: _parseNum(_p) ?? 0,
              carbsPer100g: _parseNum(_c) ?? 0,
              fatPer100g: _parseNum(_f) ?? 0,
            )
          : await svc.updateCustomFood(
              editing.id,
              name: name,
              brand: _brand.text.trim(),
              caloriesPer100g: cal,
              proteinPer100g: _parseNum(_p) ?? 0,
              carbsPer100g: _parseNum(_c) ?? 0,
              fatPer100g: _parseNum(_f) ?? 0,
            );
      if (!mounted) return;
      Navigator.pop(context, food);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _sheetShell(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sheetHandle(),
            Text(widget.editing == null ? 'Custom food' : 'Edit food',
                style: ZType.h3.copyWith(color: ZveltTokens.text)),
            const SizedBox(height: ZveltTokens.s1),
            Text('Values per 100g.',
                style: ZType.bodyS.copyWith(color: ZveltTokens.text3)),
            const SizedBox(height: ZveltTokens.s4),
            TextField(
              controller: _name,
              style: ZType.bodyM.copyWith(color: ZveltTokens.text),
              decoration: InputDecoration(
                hintText: 'Name',
                hintStyle: ZType.bodyS.copyWith(color: ZveltTokens.text3),
                filled: true,
                fillColor: ZveltTokens.surface2,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: ZveltTokens.s3, vertical: ZveltTokens.s3),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: ZveltTokens.s2),
            TextField(
              controller: _brand,
              style: ZType.bodyM.copyWith(color: ZveltTokens.text),
              decoration: InputDecoration(
                hintText: 'Brand (optional)',
                hintStyle: ZType.bodyS.copyWith(color: ZveltTokens.text3),
                filled: true,
                fillColor: ZveltTokens.surface2,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: ZveltTokens.s3, vertical: ZveltTokens.s3),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: ZveltTokens.s3),
            _numRow('Calories / 100g', _cal, 'kcal'),
            _numRow('Protein / 100g', _p, 'g'),
            _numRow('Carbo / 100g', _c, 'g'),
            _numRow('Fat / 100g', _f, 'g'),
            if (_error != null) ...[
              const SizedBox(height: ZveltTokens.s2),
              Text(_error!,
                  style: ZType.bodyS.copyWith(color: ZveltTokens.error)),
            ],
            const SizedBox(height: ZveltTokens.s4),
            SizedBox(
              height: 50,
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: ZveltTokens.brand,
                    foregroundColor: ZveltTokens.onBrand,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ZveltTokens.rMd))),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: ZveltTokens.onBrand))
                    : Text('Save',
                        style: ZType.bodyM.copyWith(
                            color: ZveltTokens.onBrand,
                            fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pick how many recipe servings to log → returns the servings count.
class _ServingsDialog extends StatefulWidget {
  const _ServingsDialog({required this.recipe});
  final Recipe recipe;
  @override
  State<_ServingsDialog> createState() => _ServingsDialogState();
}

class _ServingsDialogState extends State<_ServingsDialog> {
  double _servings = 1;
  @override
  Widget build(BuildContext context) {
    final perServ = widget.recipe.perServingCalories;
    return AlertDialog(
      backgroundColor: ZveltTokens.surface,
      title: Text(widget.recipe.name,
          style: ZType.h4.copyWith(color: ZveltTokens.text)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${(perServ * _servings).round()} kcal',
              style:
                  ZType.num_.copyWith(color: ZveltTokens.text, fontSize: 28)),
          Text('${_fmtNum(_servings)} servings',
              style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
          const SizedBox(height: ZveltTokens.s2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(AppIcons.minus, color: ZveltTokens.brand),
                onPressed: () => setState(
                    () => _servings = (_servings - 0.5).clamp(0.5, 20)),
              ),
              SizedBox(
                width: 56,
                child: Text(_fmtNum(_servings),
                    textAlign: TextAlign.center,
                    style: ZType.num_
                        .copyWith(color: ZveltTokens.text, fontSize: 20)),
              ),
              IconButton(
                icon: const Icon(AppIcons.plus, color: ZveltTokens.brand),
                onPressed: () => setState(
                    () => _servings = (_servings + 0.5).clamp(0.5, 20)),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: ZveltTokens.brand,
              foregroundColor: ZveltTokens.onBrand),
          onPressed: () => Navigator.pop(context, _servings),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fasting (handoff Nutrition §13d + sheetFast)
// ─────────────────────────────────────────────────────────────────────────────

/// Hero-weight fasting card: live gradient ring ("Ends in HH:MM"), Started /
/// Ends rows, Start/End control. Tap anywhere → the protocol editor sheet.
class _FastingCard extends StatelessWidget {
  const _FastingCard({
    required this.state,
    required this.onTap,
    required this.onToggle,
  });

  final FastingState state;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  static String _hm(DateTime? t) => t == null
      ? '—'
      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    // Prototype fasting card (HTML 300–312): header + window chip + pencil,
    // 212px ring, center label/time/unit (+% when active), Started/Ends
    // dotted rows, Start/End button.
    final rem = state.remaining;
    final remLabel =
        '${rem.inHours.toString().padLeft(2, '0')}:${(rem.inMinutes % 60).toString().padLeft(2, '0')}';
    final elapsed = state.elapsed;
    final elapsedLabel =
        '${elapsed.inHours.toString().padLeft(2, '0')}:${(elapsed.inMinutes % 60).toString().padLeft(2, '0')}';
    final done = state.active && rem <= Duration.zero;
    final centerLabel = !state.active
        ? 'Tap start below'
        : (done ? 'Fast complete 🎉' : 'Ends in');
    final centerTime =
        !state.active ? state.protocolLabel : (done ? elapsedLabel : remLabel);
    final centerUnit = state.active ? 'Hrs' : 'window';
    final pct = (state.progress * 100).round();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        gradient: ZveltTokens.surfaceGrad,
        borderRadius: BorderRadius.circular(ZveltTokens.rCardLg),
        border: Border.all(color: ZveltTokens.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('Fasting',
                  style: ZType.h3
                      .copyWith(fontSize: 21, fontWeight: FontWeight.w700)),
              const Spacer(),
              InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0x24F58214),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0x66F58214)),
                  ),
                  child: Text(state.protocolLabel,
                      style: ZType.bodyS.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: ZveltTokens.brand)),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ZveltTokens.chip,
                    border: Border.all(color: ZveltTokens.border),
                  ),
                  child:
                      Icon(AppIcons.edit, size: 15, color: ZveltTokens.text2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 212,
              height: 212,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      size: const Size(212, 212),
                      painter: _FastRingPainter(
                        progress: state.active ? state.progress : 0,
                        track: ZveltTokens.track,
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ZveltTokens.chip,
                          border: Border.all(color: ZveltTokens.border),
                        ),
                        child: Icon(AppIcons.stopwatch,
                            size: 19, color: ZveltTokens.text),
                      ),
                      const SizedBox(height: 8),
                      Text(centerLabel,
                          style: ZType.bodyS.copyWith(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(centerTime,
                              style: ZType.stat.copyWith(fontSize: 37)),
                          const SizedBox(width: 4),
                          Text(centerUnit,
                              style: ZType.bodyS.copyWith(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      if (state.active && !done) ...[
                        const SizedBox(height: 3),
                        Text('$pct% complete',
                            style: ZType.bodyS.copyWith(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: ZveltTokens.brand)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _dottedRow('Started:', _hm(state.startAt)),
          const SizedBox(height: 11),
          _dottedRow('Ends:', _hm(state.endsAt)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onToggle,
              style: FilledButton.styleFrom(
                backgroundColor:
                    state.active ? ZveltTokens.chip : ZveltTokens.brand,
                foregroundColor:
                    state.active ? ZveltTokens.text : ZveltTokens.onBrand,
                padding: const EdgeInsets.symmetric(vertical: 13),
                minimumSize: Size.zero,
                elevation: 0,
                side: state.active
                    ? BorderSide(color: ZveltTokens.borderStrong)
                    : BorderSide.none,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ZveltTokens.rControl)),
              ),
              child: Text(state.active ? 'End fast' : 'Start fast',
                  style: ZType.bodyM.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: state.active
                          ? ZveltTokens.text
                          : ZveltTokens.onBrand)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dottedRow(String label, String value) {
    return Row(
      children: [
        Text(label,
            style: ZType.bodyM
                .copyWith(fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(width: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => Text(
              '·' * (c.maxWidth ~/ 6),
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: ZType.monoXS.copyWith(color: ZveltTokens.text4),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(value,
            style: ZType.bodyM.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: ZveltTokens.text)),
      ],
    );
  }
}

/// Big fasting ring (prototype stroke 15 at 212px — scales with size).
class _FastRingPainter extends CustomPainter {
  const _FastRingPainter({required this.progress, required this.track});

  final double progress;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 15 / 212;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - stroke / 2 - 1;
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center, radius, trackPaint);
    if (progress <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final arc = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [ZveltTokens.brand3, ZveltTokens.brandDeep],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
        rect, -1.5708, 6.2832 * progress.clamp(0.0, 1.0), false, arc);
  }

  @override
  bool shouldRepaint(covariant _FastRingPainter old) =>
      old.progress != progress || old.track != track;
}

/// Calories ring (HTML 283): dotted 3px track + 7px gradient arc.
class _CalorieRingPainter extends CustomPainter {
  const _CalorieRingPainter({required this.progress, required this.track});

  final double progress;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    // Dotted track: dash 1.5 / gap 6.4 (prototype stroke-dasharray).
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    const dash = 1.5, gap = 6.4;
    final circumference = 2 * math.pi * radius;
    var d = 0.0;
    while (d < circumference) {
      final a0 = d / radius;
      final a1 = (d + dash) / radius;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), a0,
          a1 - a0, false, trackPaint);
      d += dash + gap;
    }
    if (progress <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final arc = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [ZveltTokens.brand3, ZveltTokens.brandDeep],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
        rect, -1.5708, 6.2832 * progress.clamp(0.0, 1.0), false, arc);
  }

  @override
  bool shouldRepaint(covariant _CalorieRingPainter old) =>
      old.progress != progress || old.track != track;
}

/// Dashed rounded border (the prototype's dashed Add-food button).
class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
          RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    const dash = 6.0, gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
            metric.extractPath(d, (d + dash).clamp(0, metric.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}

/// sheetFast — protocol select (16:8 / 18:6 / 20:4), editable start time,
/// Start/End control. Returns the new [FastingState].
class _FastingSheet extends StatefulWidget {
  const _FastingSheet({required this.state});
  final FastingState state;

  @override
  State<_FastingSheet> createState() => _FastingSheetState();
}

class _FastingSheetState extends State<_FastingSheet> {
  late int _hours = widget.state.protocolHours;
  late DateTime _start = widget.state.startAt ?? DateTime.now();
  late final bool _active = widget.state.active;

  /// While a fast is ACTIVE, window/start edits persist immediately
  /// (prototype setFastWindow/onFastStart — the ring retargets live).
  /// Inactive edits stay local and apply on 'Start fasting now'.
  Future<void> _applyLive() async {
    if (!_active) return;
    await FastingService().update(protocolHours: _hours, startAt: _start);
  }

  Future<void> _pickWindow(int h) async {
    setState(() => _hours = h);
    await _applyLive();
  }

  Future<void> _pickStart() async {
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (t == null || !mounted) return;
    final now = DateTime.now();
    var candidate = DateTime(now.year, now.month, now.day, t.hour, t.minute);
    // Never allow a start in the future (end-before-start guard).
    if (candidate.isAfter(now)) {
      candidate = candidate.subtract(const Duration(days: 1));
    }
    setState(() => _start = candidate);
    await _applyLive();
  }

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
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
            // Header — title + 'Set your window & start time' + close X
            // (prototype HTML 821–824).
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Fasting',
                          style: ZType.h4.copyWith(
                              fontSize: 19, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('Set your window & start time',
                          style: ZType.bodyS.copyWith(
                              fontSize: 12, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ZveltTokens.chip,
                      border: Border.all(color: ZveltTokens.border),
                    ),
                    child: Icon(AppIcons.cross_small,
                        size: 16, color: ZveltTokens.text2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('FASTING WINDOW', style: ZType.eyebrow),
            const SizedBox(height: 9),
            Row(
              children: [
                // Prototype fastWindows: 14:10 / 16:8 / 18:6 / 20:4.
                for (final h in const [14, 16, 18, 20]) ...[
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickWindow(h),
                      borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _hours == h
                              ? ZveltTokens.brand
                              : ZveltTokens.chip,
                          borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                          border: _hours == h
                              ? null
                              : Border.all(color: ZveltTokens.border),
                          boxShadow: _hours == h ? ZveltTokens.glowSm : null,
                        ),
                        child: Text('$h:${24 - h}',
                            style: ZType.bodyM.copyWith(
                                fontSize: 13.5,
                                fontWeight: _hours == h
                                    ? FontWeight.w800
                                    : FontWeight.w700,
                                color: _hours == h
                                    ? ZveltTokens.onBrand
                                    : ZveltTokens.text2)),
                      ),
                    ),
                  ),
                  if (h != 20) const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 18),
            Text('STARTED AT', style: ZType.eyebrow),
            const SizedBox(height: 9),
            InkWell(
              onTap: _pickStart,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                decoration: BoxDecoration(
                  color: ZveltTokens.chip,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ZveltTokens.borderStrong),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(AppIcons.clock, size: 18, color: ZveltTokens.text2),
                    const SizedBox(width: 10),
                    Text(
                        '${_start.hour.toString().padLeft(2, '0')}:${_start.minute.toString().padLeft(2, '0')}',
                        style: ZType.bodyM.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: ZveltTokens.text)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            // CTA — active: 'End fast now' as a neutral chip (chip bg +
            // borderStrong, white text); inactive: 'Start fasting now'
            // brand-filled with glow (prototype HTML 831–832).
            InkWell(
              onTap: () async {
                final svc = FastingService();
                final next = _active
                    ? await svc.end()
                    : await svc.start(protocolHours: _hours, startAt: _start);
                if (!context.mounted) return;
                Navigator.of(context).pop(next);
              },
              borderRadius: BorderRadius.circular(ZveltTokens.rControl),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _active ? ZveltTokens.chip : ZveltTokens.brand,
                  borderRadius: BorderRadius.circular(ZveltTokens.rControl),
                  border: _active
                      ? Border.all(color: ZveltTokens.borderStrong)
                      : null,
                  boxShadow: _active ? null : ZveltTokens.glowMd,
                ),
                child: Center(
                  child: Text(_active ? 'End fast now' : 'Start fasting now',
                      style: ZType.bodyM.copyWith(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: _active
                              ? ZveltTokens.text
                              : ZveltTokens.onBrand)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// sheetBasket — Shopping Basket (prototype HTML 660–676): check rows toggle,
// "Add all to list" checks everything. Items derive from the selected day's
// AI meal plan; checked state persists per day.
// ─────────────────────────────────────────────────────────────────────────────

class _BasketSheet extends StatefulWidget {
  const _BasketSheet({
    required this.items,
    required this.checked,
    required this.onChanged,
  });

  final List<({String name, String qty})> items;
  final Set<String> checked;
  final ValueChanged<Set<String>> onChanged;

  @override
  State<_BasketSheet> createState() => _BasketSheetState();
}

class _BasketSheetState extends State<_BasketSheet> {
  late final Set<String> _checked = {...widget.checked};

  void _toggle(String name) {
    setState(() {
      if (!_checked.add(name)) _checked.remove(name);
    });
    widget.onChanged(_checked);
  }

  // Prototype tCheckout (JS 2175): toast ONLY — no check-all mutation and the
  // sheet stays open.
  void _addAll() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZveltTokens.rSm)),
      content: const Text('Added to shopping list'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.84),
      decoration: BoxDecoration(
        gradient: ZveltTokens.sheetGrad,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(ZveltTokens.rSheet)),
        border: Border.all(color: ZveltTokens.border),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 34),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Shopping Basket',
                        style: ZType.h4.copyWith(
                            fontSize: 19, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('Ingredients for today’s meals',
                        style: ZType.bodyS.copyWith(
                            fontSize: 12, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              InkWell(
                onTap: () => Navigator.of(context).pop(),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ZveltTokens.chip,
                    border: Border.all(color: ZveltTokens.border),
                  ),
                  child: Icon(AppIcons.cross_small,
                      size: 16, color: ZveltTokens.text2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Center(
                child: Text(
                  'No ingredients yet — generate a meal plan first.',
                  style: ZType.bodyS
                      .copyWith(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 9),
                itemBuilder: (context, i) {
                  final item = widget.items[i];
                  final checked = _checked.contains(item.name);
                  return InkWell(
                    onTap: () => _toggle(item.name),
                    borderRadius: BorderRadius.circular(ZveltTokens.rControl),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: ZveltTokens.surface2Grad,
                        borderRadius:
                            BorderRadius.circular(ZveltTokens.rControl),
                        border: Border.all(color: ZveltTokens.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: checked ? ZveltTokens.brand : null,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: checked
                                      ? ZveltTokens.brand
                                      : ZveltTokens.borderStrong,
                                  width: 1.5),
                            ),
                            child: checked
                                ? const Icon(AppIcons.check,
                                    size: 13, color: ZveltTokens.onBrand)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ZType.bodyM.copyWith(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    decoration: checked
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: checked
                                        ? ZveltTokens.text3
                                        : ZveltTokens.text,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(item.qty,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: ZType.bodyS.copyWith(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          if (widget.items.isNotEmpty) ...[
            const SizedBox(height: 16),
            InkWell(
              onTap: _addAll,
              borderRadius: BorderRadius.circular(ZveltTokens.rControl),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: ZveltTokens.brand,
                  borderRadius: BorderRadius.circular(ZveltTokens.rControl),
                  boxShadow: ZveltTokens.glowMd,
                ),
                child: Center(
                  child: Text('Add all to list',
                      style: ZType.bodyM.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: ZveltTokens.onBrand)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// sheetCal — Select date (prototype HTML 704–732): month grid with dots on
// logged days, prev/next month, Today shortcut. Pops the picked date.
// ─────────────────────────────────────────────────────────────────────────────

class _CalendarSheet extends StatefulWidget {
  const _CalendarSheet({required this.selected, required this.loggedDayKeys});

  final DateTime selected;
  final Set<String> loggedDayKeys;

  @override
  State<_CalendarSheet> createState() => _CalendarSheetState();
}

class _CalendarSheetState extends State<_CalendarSheet> {
  late DateTime _month =
      DateTime(widget.selected.year, widget.selected.month, 1);

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _navBtn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ZveltTokens.chip,
            border: Border.all(color: ZveltTokens.border),
          ),
          child: Icon(icon, size: 15, color: ZveltTokens.text2),
        ),
      );

  @override
  Widget build(BuildContext context) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final today = DateUtils.dateOnly(DateTime.now());
    final firstWd = DateTime(_month.year, _month.month, 1).weekday % 7;
    final daysIn = DateUtils.getDaysInMonth(_month.year, _month.month);

    return Container(
      decoration: BoxDecoration(
        gradient: ZveltTokens.sheetGrad,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(ZveltTokens.rSheet)),
        border: Border.all(color: ZveltTokens.border),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: ZveltTokens.track,
              borderRadius: BorderRadius.circular(ZveltTokens.rPill),
            ),
          ),
          Row(
            children: [
              Text('Select date',
                  style: ZType.h4
                      .copyWith(fontSize: 19, fontWeight: FontWeight.w800)),
              const Spacer(),
              InkWell(
                onTap: () => Navigator.of(context).pop(),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ZveltTokens.chip,
                    border: Border.all(color: ZveltTokens.border),
                  ),
                  child: Icon(AppIcons.cross_small,
                      size: 16, color: ZveltTokens.text2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _navBtn(
                  AppIcons.angle_small_left,
                  () => setState(() =>
                      _month = DateTime(_month.year, _month.month - 1, 1))),
              Text('${months[_month.month - 1]} ${_month.year}',
                  style: ZType.bodyL
                      .copyWith(fontSize: 16, fontWeight: FontWeight.w800)),
              _navBtn(
                  AppIcons.angle_small_right,
                  () => setState(() =>
                      _month = DateTime(_month.year, _month.month + 1, 1))),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final d in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                Expanded(
                  child: Text(d,
                      textAlign: TextAlign.center,
                      style: ZType.monoXS.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: ZveltTokens.text3)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Prototype calCells (HTML 725–729 + JS 1935–1941): 40px-tall cells,
          // 5px gaps; selected = rounded-12 brand gradient + glow.
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 5,
              crossAxisSpacing: 5,
              mainAxisExtent: 40,
            ),
            children: [
              for (var i = 0; i < firstWd; i++) const SizedBox.shrink(),
              for (var d = 1; d <= daysIn; d++)
                _dayCell(DateTime(_month.year, _month.month, d)),
            ],
          ),
          const SizedBox(height: 18),
          InkWell(
            onTap: () => Navigator.of(context).pop(today),
            borderRadius: BorderRadius.circular(ZveltTokens.rControl),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: ZveltTokens.chip,
                borderRadius: BorderRadius.circular(ZveltTokens.rControl),
                border: Border.all(color: ZveltTokens.borderStrong),
              ),
              child: Center(
                child: Text('Today',
                    style: ZType.bodyM.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: ZveltTokens.text)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Prototype cell (JS 1935–1941): selected = height-40 rounded-12 cell with
  // the FFA630→EE6E08 gradient + drop shadow; NO separate 'today' outline —
  // the prototype only differentiates selected vs normal (+ logged dot).
  Widget _dayCell(DateTime date) {
    final isSel = DateUtils.isSameDay(date, widget.selected);
    final hasDot = widget.loggedDayKeys.contains(_ymd(date));

    return InkWell(
      onTap: () => Navigator.of(context).pop(date),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: isSel
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [ZveltTokens.brand2, ZveltTokens.brandDeep],
                ),
                boxShadow: ZveltTokens.glowSm,
              )
            : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${date.day}',
                style: ZType.bodyS.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: isSel ? ZveltTokens.onBrand : ZveltTokens.text)),
            if (hasDot && !isSel)
              Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.only(top: 3),
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: ZveltTokens.brand),
              ),
          ],
        ),
      ),
    );
  }
}
