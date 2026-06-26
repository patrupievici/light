import 'dart:async';
import 'package:zvelt_app/theme/app_icons.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/z/z_card.dart';
import '../../widgets/z/z_eyebrow.dart';
import '../../services/_crash_reporter.dart' show reportError;
import '../../services/auth_service.dart';
import '../../services/nutrition_service.dart';
import '../../services/onboarding_service.dart';
import '../../services/profile_service.dart';
import '../../services/nutrition_food_labels.dart';
import '../../widgets/zvelt_primary_button.dart';
import '../../widgets/zvelt_main_nav_bar.dart';
import '../../widgets/zvelt_error_state.dart';
import '../social/notifications_screen.dart';
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

String _mealEntrySubtitle(MealEntry entry) {
  final sg = entry.food.servingGrams;
  final macros = 'P${entry.protein.round()} C${entry.carbs.round()} F${entry.fat.round()}';
  if (sg != null && sg > 0) {
    final n = entry.grams / sg;
    if (n > 0) {
      final key = entry.food.portionUnitKey ?? 'serving';
      final portion = NutritionFoodLabels.formatUnitCount(n, key);
      return '$portion · ${entry.grams.round()}g · $macros';
    }
  }
  return '${entry.grams.round()}g · $macros';
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
  double? _profileBodyweightKg;
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

  static double? _bodyweightFromProfileMap(Map<String, dynamic>? profile) {
    if (profile == null) return null;
    final bwRaw =
        profile['bodyweightKg'] ?? profile['bodweightKg'] ?? profile['bodyweight_kg'];
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
        _service.getDay(_today).catchError((_) => DailyNutrition.empty),
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
      profileBw = signedIn
          ? _bodyweightFromProfileMap(me?['profile'] as Map<String, dynamic>?)
          : null;
      if (signedIn && profileBw == null) {
        try {
          await _onboardingService.syncSavedQuestionnaireToProfile();
          final meRetry =
              await _profileService.getMe().catchError((_) => null);
          profileBw = _bodyweightFromProfileMap(
              meRetry?['profile'] as Map<String, dynamic>?);
        } catch (_) {/* non-fatal */}
      }
      profileBw ??= await _onboardingService.getSavedWeightKg();
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
          _profileBodyweightKg = profileBw;
          _signedIn = signedIn;
          // Only treat as a hard failure on the FIRST load (nothing usable on
          // screen yet). A background refresh that throws keeps the existing
          // data rather than blanking the tab into an error surface.
          _loadFailed = failed && showSpinner;
          _loading = false;
        });
      }
    }
    // Auto-generate the weekly meal plan the first time Nutrition opens with no
    // plan yet (e.g. right after onboarding set the goal) so the tab isn't
    // empty. One-shot per session to avoid repeated 30-120s AI calls.
    if (mounted && _signedIn && _weekPlan.isEmpty && !_autoBootstrapTried) {
      _autoBootstrapTried = true;
      unawaited(_bootstrapWeekPlan());
    }
  }

  Future<void> _bootstrapWeekPlan() async {
    if (!_signedIn) return;
    final bearer = await _auth.getAccessToken();
    if (bearer == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No valid server session. Check your connection or sign in again.'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _weekPlan.isEmpty
                ? 'Could not create a plan (backend, network, or account).'
                : 'Weekly plan created.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showPlanError(context, e);
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
        : 'Nu am putut crea planul săptămânal. Încearcă din nou.';
    final messenger = ScaffoldMessenger.of(ctx);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: ZveltTokens.error,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        content: Text(friendly, style: ZType.bodyS.copyWith(color: Colors.white)),
        action: SnackBarAction(
          label: 'REÎNCEARCĂ',
          textColor: Colors.white,
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
        const SnackBar(content: Text('Sign in again to regenerate the plan on the server.')),
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
            child: CircularProgressIndicator(color: ZveltTokens.brand, strokeWidth: 2.5),
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
      builder: (_) => _AddFoodSheet(
        meal: meal,
        onAdd: (entry) async {
          await _service.addEntry(entry);
          // Local mutation already persisted to prefs + pushed — apply the
          // exact next state directly instead of a full _load() reload (which
          // flashes the spinner and re-hits the network).
          if (mounted) {
            setState(() {
              _setDay(DailyNutrition(
                entries: List<MealEntry>.from(_day.entries)..add(entry),
                waterMl: _day.waterMl,
                weightKg: _day.weightKg,
              ));
            });
          }
        },
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZveltTokens.rSm)),
    ));
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anulează')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ZveltTokens.brand, foregroundColor: ZveltTokens.onBrand),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Salvează'),
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: ZveltTokens.s2),
            _sheetHandle(),
            ListTile(
              leading: const Icon(AppIcons.restaurant, color: ZveltTokens.brand),
              title: Text('Salvează ziua ca masă', style: ZType.bodyM.copyWith(color: ZveltTokens.text)),
              onTap: () => Navigator.pop(context, 'save'),
            ),
            ListTile(
              leading: const Icon(AppIcons.calendar, color: ZveltTokens.brand),
              title: Text('Copiază dintr-o altă zi', style: ZType.bodyM.copyWith(color: ZveltTokens.text)),
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
      _toast('Ziua e goală — nimic de salvat');
      return;
    }
    final name = await _promptName('Nume masă');
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
      _toast('Masă salvată');
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
        _toast('Ziua aleasă e goală');
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
      _toast('Copiat ${day.entries.length} alimente');
    } catch (e) {
      if (mounted) _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showWaterDialog() async {
    // ── Design parity: bottom sheet (not AlertDialog) with the 3-column
    // quick-add grid (+250ml / +500ml / +1L) plus custom input.
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WaterSheet(currentMl: _day.waterMl),
    );
    if (result != null) {
      await _service.updateWater(result, _today);
      // Persisted + pushed already — apply the new water value directly
      // instead of a full _load() (spinner + network re-fetch).
      if (mounted) {
        setState(() {
          _setDay(DailyNutrition(
            entries: _day.entries,
            waterMl: result,
            weightKg: _day.weightKg,
          ));
        });
      }
    }
  }

  void _showWeightDialog() async {
    // ── Design parity: bottom sheet with ± stepper around the big value.
    final result = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WeightSheet(
        initialKg: _day.weightKg ?? _profileBodyweightKg ?? 75,
      ),
    );
    if (result != null) {
      // Spec mandates bodyweight 30-250 kg — this value feeds the SR
      // strength-ranking math, so 0.5 or 9999 must not reach the server.
      if (result < 30 || result > 250) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter a weight between 30 and 250 kg.')),
          );
        }
        return;
      }
      await _service.updateWeight(result, _today);
      // Persisted + pushed already — apply the new weight directly instead of
      // a full _load() (spinner + network re-fetch).
      if (mounted) {
        setState(() {
          _setDay(DailyNutrition(
            entries: _day.entries,
            waterMl: _day.waterMl,
            weightKg: result,
          ));
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Day rollover: the tab State survives across midnight inside the nav
    // shell. Without this, water/weight/entry writes landed on YESTERDAY's
    // key and the screen kept showing yesterday's totals as 'today'.
    final nowDay = _midnightOf(DateTime.now());
    if (nowDay != _today) {
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
            _buildNutritionHeader(context),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: ZveltTokens.brand))
                  : _loadFailed
                      ? ZveltErrorState(
                          title: "Couldn't load nutrition",
                          onRetry: _load,
                        )
                      : RefreshIndicator(
                      onRefresh: _load,
                      color: ZveltTokens.brand,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(ZveltTokens.s4, 0, ZveltTokens.s4, ZveltMainNavBar.reservedBottomHeight(context) + ZveltTokens.s4),
                        children: [
                          const SizedBox(height: ZveltTokens.s3),
                          _buildPlanBanner(),
                          const SizedBox(height: ZveltTokens.s3),
                          if (_planGenerating)
                            _buildPlanGeneratingCard()
                          else
                            _WeeklyPlanCard(
                              weekPlan: _weekPlan,
                              today: _today,
                              signedIn: _signedIn,
                              onDayTap: _openDayMealPlan,
                              onBootstrapWeek: _bootstrapWeekPlan,
                              onRegenerateWeek: _regenerateWeeklyPlanWithAi,
                            ),
                          const SizedBox(height: ZveltTokens.s3),
                          _CaloriesCard(totals: _totals, goals: _goals),
                          const SizedBox(height: ZveltTokens.s3),
                          _MacrosRow(totals: _totals, goals: _goals),
                          const SizedBox(height: ZveltTokens.s4),
                          Row(
                            children: [
                              Expanded(child: _WaterCard(waterMl: _day.waterMl, goalMl: _goals.waterMl, onTap: _showWaterDialog)),
                              const SizedBox(width: ZveltTokens.s3),
                              Expanded(
                                child: _WeightCard(
                                  displayKg: _day.weightKg ?? _profileBodyweightKg,
                                  loggedToday: _day.weightKg != null,
                                  onTap: _showWeightDialog,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: ZveltTokens.s5),
                          // NutritionXpClaimCard removed: claimDayXp() is a
                          // stub (always '+0 XP / Already claimed') since the
                          // backend nutrition-xp service was dropped. A card
                          // promising XP it can never award is fabricated
                          // data — re-add when the endpoint returns.
                          Padding(
                            padding: const EdgeInsets.only(bottom: ZveltTokens.s2),
                            child: Row(
                              children: [
                                const Expanded(child: ZEyebrow("Today's meals")),
                                GestureDetector(
                                  onTap: () => _showGoalsSheet(),
                                  child: Text(
                                    'Edit goals',
                                    style: ZType.bodyS.copyWith(
                                      color: ZveltTokens.brand,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ...['breakfast', 'lunch', 'dinner', 'snack'].map((meal) =>
                            _MealSection(
                              meal: meal,
                              // Pull this meal's entries from the once-per-day
                              // precomputed grouping (no per-rebuild .where).
                              entries: _totals.byMeal[meal] ?? const <MealEntry>[],
                              onAdd: () => _showAddFood(meal),
                              onRemove: (id) async {
                                await _service.removeEntry(id, _today);
                                // Persisted + pushed already — drop the entry
                                // from local state directly instead of a full
                                // _load() (spinner + network re-fetch).
                                if (mounted) {
                                  setState(() {
                                    _setDay(DailyNutrition(
                                      entries: _day.entries
                                          .where((e) => e.id != id)
                                          .toList(),
                                      waterMl: _day.waterMl,
                                      weightKg: _day.weightKg,
                                    ));
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: ZveltTokens.s4),
                          _buildAddFoodCta(),
                          const SizedBox(height: ZveltTokens.s1),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _foodDateLabel() {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final d = _today;
    final today = _midnightOf(DateTime.now());
    final prefix = d == today ? 'Today, ' : '';
    return '$prefix${d.day} ${months[d.month - 1]}';
  }

  Widget _buildNutritionHeader(BuildContext context) {
    // Light-redesign header (mockup 7): "Food" + "Today, <date>" — replaces the
    // old uppercase "NUTRITION" wordmark.
    return Padding(
      padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, ZveltTokens.s4, ZveltTokens.s3, ZveltTokens.s2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Food', style: ZType.h1),
                const SizedBox(height: 2),
                Text(
                  _foodDateLabel(),
                  style: ZType.bodyS.copyWith(color: ZveltTokens.text3),
                ),
              ],
            ),
          ),
          Row(
            children: [
              _NutritionHeaderBtn(
                icon: AppIcons.bell,
                semanticLabel: 'Notifications',
                // No fabricated unread dot — it was hardcoded always-on,
                // training users to ignore the badge. Re-add when wired to
                // a real unread count.
                hasDot: false,
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
                ),
              ),
              const SizedBox(width: ZveltTokens.s2),
              _NutritionHeaderBtn(
                icon: AppIcons.settings_sliders,
                semanticLabel: 'Edit goals',
                onTap: () => _showGoalsSheet(),
              ),
              const SizedBox(width: ZveltTokens.s2),
              _NutritionHeaderBtn(
                icon: AppIcons.menu_dots,
                semanticLabel: 'Acțiuni zi',
                onTap: _showDayMenu,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlanBanner() {
    // ── Design parity: the 'AI plan ready' banner card (padding 14, r18,
    // 32px tinted icon tile, title + kcal subtitle, View action). 'View'
    // opens today's day-plan sheet. Honest: only renders when a plan exists
    // (gated by the caller); the kcal subtitle uses the REAL goal.
    final today = _weekPlan.isEmpty
        ? null
        : _weekPlan[DateTime.now().weekday - 1 < _weekPlan.length
            ? DateTime.now().weekday - 1
            : 0];
    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: ZveltTokens.brandTint,
              borderRadius: BorderRadius.circular(ZveltTokens.rSm),
            ),
            child: const Icon(AppIcons.sparkles,
                color: ZveltTokens.brand, size: 15),
          ),
          const SizedBox(width: ZveltTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI plan ready',
                    style: ZType.bodyS.copyWith(
                        color: ZveltTokens.text,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 1),
                Text(
                  '${_goals.calories} kcal · tuned to your goal',
                  style: ZType.monoXS.copyWith(color: ZveltTokens.text2),
                ),
              ],
            ),
          ),
          if (today != null)
            GestureDetector(
              onTap: () => _openDayMealPlan(today),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s2, vertical: ZveltTokens.s2),
                child: Text('View',
                    style: ZType.monoXS.copyWith(
                        fontWeight: FontWeight.w600,
                        color: ZveltTokens.brand)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAddFoodCta() {
    // ── Design parity: gradient CTA (brand-deep → brand → brand-2),
    // radius 18 (not pill), orange glow shadow, padding 16/22.
    return Semantics(
      button: true,
      label: 'Add food',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => _showAddFood('breakfast'),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s4, horizontal: ZveltTokens.s6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                ZveltTokens.brandDeep,
                ZveltTokens.brand,
                ZveltTokens.brand2,
              ],
              stops: [0, 0.6, 1],
            ),
            borderRadius: BorderRadius.circular(ZveltTokens.rLg),
            boxShadow: [
              BoxShadow(
                color: ZveltTokens.brand.withValues(alpha: 0.32),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(AppIcons.plus, size: 18, color: Colors.white),
              const SizedBox(width: ZveltTokens.s2),
              Text(
                'Add food',
                style: ZType.bodyM.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGoalsSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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

class _NutritionHeaderBtn extends StatelessWidget {
  const _NutritionHeaderBtn({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.hasDot = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;
  final bool hasDot;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ZveltTokens.surface,
              border: Border.all(color: ZveltTokens.border),
              boxShadow: ZveltTokens.shadowCard,
            ),
            child: Icon(icon, color: ZveltTokens.text2, size: 18),
          ),
          if (hasDot)
            Positioned(
              top: 9,
              right: 10,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ZveltTokens.brand,
                  border: Border.all(color: ZveltTokens.surface, width: 1.5),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }
}

class _WeeklyPlanCard extends StatelessWidget {
  const _WeeklyPlanCard({
    required this.weekPlan,
    required this.today,
    required this.signedIn,
    required this.onDayTap,
    required this.onBootstrapWeek,
    required this.onRegenerateWeek,
  });
  final List<NutritionPlanDay> weekPlan;
  final DateTime today;
  final bool signedIn;
  final void Function(NutritionPlanDay day) onDayTap;
  final Future<void> Function() onBootstrapWeek;
  final Future<void> Function() onRegenerateWeek;

  bool get _hasAiMeals =>
      weekPlan.any((d) => d.mealPlan != null && d.mealPlan!.meals.isNotEmpty);

  bool _isToday(String ymd) {
    final t = '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    return ymd == t;
  }

  String _dow(String ymd) {
    final p = ymd.split('-');
    if (p.length != 3) return ymd;
    final d = DateTime.tryParse(ymd);
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    if (d == null) return ymd;
    return names[d.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    if (!signedIn) {
      return ZCard(
        padding: const EdgeInsets.all(ZveltTokens.s4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(ZveltTokens.s2),
              decoration: BoxDecoration(
                color: ZveltTokens.brandTint,
                borderRadius: BorderRadius.circular(ZveltTokens.rSm),
              ),
              child: const Icon(AppIcons.calendar,
                  color: ZveltTokens.brand, size: 20),
            ),
            const SizedBox(width: ZveltTokens.s3),
            Expanded(
              child: Text(
                'Sign in for a 7-day nutrition plan (macros + AI meal suggestions).',
                style: ZType.bodyS.copyWith(
                  color: ZveltTokens.text,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (weekPlan.isEmpty) {
      return ZCard(
        padding: const EdgeInsets.all(ZveltTokens.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(ZveltTokens.s2),
                  decoration: BoxDecoration(
                    color: ZveltTokens.brandTint,
                    borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                  ),
                  child: const Icon(AppIcons.calendar,
                      color: ZveltTokens.brand, size: 16),
                ),
                const SizedBox(width: ZveltTokens.s3),
                Expanded(
                  child: Text('Weekly plan',
                      style: ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 15)),
                ),
              ],
            ),
            const SizedBox(height: ZveltTokens.s3),
            Text(
              'No plan for this week yet. Tap to generate one with AI.',
              style: ZType.bodyS.copyWith(
                color: ZveltTokens.text2, height: 1.35,
              ),
            ),
            const SizedBox(height: ZveltTokens.s3),
            SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                onPressed: () => onBootstrapWeek(),
                icon: const Icon(AppIcons.chart_histogram, color: ZveltTokens.brand, size: 18),
                label: const Text('Create weekly plan'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ZveltTokens.brand,
                  side: const BorderSide(color: ZveltTokens.brand),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ZCard(
      padding: const EdgeInsets.all(ZveltTokens.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text('Weekly nutrition plan',
                    style: ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 15)),
              ),
              IconButton(
                tooltip: 'Regenerate week (AI)',
                icon: const Icon(AppIcons.sparkles, color: ZveltTokens.brand, size: 20),
                onPressed: () => onRegenerateWeek(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
            ],
          ),
          const SizedBox(height: ZveltTokens.s1),
          Text(
            _hasAiMeals
                ? 'Tap a day for meals + protein swap.'
                : 'Tap a day for targets. Tap the spark to regenerate with AI meal lines.',
            style: ZType.bodyS.copyWith(
              color: ZveltTokens.text2, fontSize: 11, height: 1.35,
            ),
          ),
          if (!_hasAiMeals) ...[
            const SizedBox(height: ZveltTokens.s2),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: ZveltTokens.s2),
              decoration: BoxDecoration(
                color: ZveltTokens.brandTint,
                borderRadius: BorderRadius.circular(ZveltTokens.rSm),
              ),
              child: Row(
                children: [
                  const Icon(AppIcons.bulb,
                      color: ZveltTokens.brand, size: 16),
                  const SizedBox(width: ZveltTokens.s2),
                  Expanded(
                    child: Text(
                      'Only macros showing? Tap ✨ for AI meal lines.',
                      style: ZType.bodyS.copyWith(
                        color: ZveltTokens.text, fontSize: 11, height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: ZveltTokens.s3),
          // ── Design parity (screens-nutrition.jsx week grid): 7 compact
          // square cells (aspect 1:1, radius 12, 4px gap) showing ONLY the
          // day letter + date number. Today renders as the active brand
          // cell. The kcal/macros that used to live on the big cards moved
          // where the design puts them: in the day sheet opened on tap.
          LayoutBuilder(
            builder: (context, c) {
              const gap = 4.0;
              final cell =
                  (c.maxWidth - gap * (weekPlan.length - 1)) / weekPlan.length;
              final monday = DateTime.now().subtract(
                  Duration(days: DateTime.now().weekday - 1));
              return Row(
                children: [
                  for (var i = 0; i < weekPlan.length; i++) ...[
                    if (i > 0) const SizedBox(width: gap),
                    _DayCell(
                      letter: _dow(weekPlan[i].day).substring(0, 1),
                      date: monday.add(Duration(days: i)).day,
                      active: _isToday(weekPlan[i].day),
                      size: cell,
                      onTap: () => onDayTap(weekPlan[i]),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// One compact day cell — design spec: square, radius 12, day letter 10/600,
/// date 14/800; active = brand bg + white; otherwise surface-2 + border.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.letter,
    required this.date,
    required this.active,
    required this.size,
    required this.onTap,
  });

  final String letter;
  final int date;
  final bool active;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Day $date plan',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: active ? ZveltTokens.brand : ZveltTokens.surface2,
            borderRadius: BorderRadius.circular(12),
            border: active
                ? null
                : Border.all(color: ZveltTokens.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                letter,
                style: TextStyle(
                  fontFamily: ZveltTokens.fontPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: active
                      ? Colors.white.withValues(alpha: 0.85)
                      : ZveltTokens.text2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$date',
                style: TextStyle(
                  fontFamily: ZveltTokens.fontPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  color: active ? Colors.white : ZveltTokens.text,
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
// CALORIES CARD
// ─────────────────────────────────────────────────────────────────────────────

class _CaloriesCard extends StatelessWidget {
  const _CaloriesCard({required this.totals, required this.goals});
  final _DiaryTotals totals;
  final NutritionGoals goals;

  @override
  Widget build(BuildContext context) {
    final consumed = totals.calories.round();
    final goal = goals.calories;
    final remaining = goal - consumed;
    // Guard goal==0 → consumed/goal is NaN/Infinity and .clamp() then throws /
    // renders garbage. Mirrors the _MacroRing `goal > 0 ? … : 0.0` guard.
    final progress = goal > 0 ? (consumed / goal).clamp(0.0, 1.0) : 0.0;
    final overGoal = consumed > goal;
    final accent = overGoal ? ZveltTokens.error : ZveltTokens.brand;

    // ── Design parity: padding 16, soft radial brand glow top-right.
    return Semantics(
      container: true,
      label: overGoal
          ? 'Calories: $consumed of $goal kcal, ${consumed - goal} over goal'
          : 'Calories: $consumed of $goal kcal, $remaining remaining',
      child: ZCard(
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.all(ZveltTokens.s4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ZveltTokens.rLg),
          gradient: RadialGradient(
            center: const Alignment(1.1, -1.1),
            radius: 1.2,
            colors: [
              ZveltTokens.brand.withValues(alpha: 0.10),
              Colors.transparent,
            ],
            stops: const [0, 0.6],
          ),
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ZEyebrow('Calories'),
          const SizedBox(height: ZveltTokens.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$consumed',
                // Design parity: 30px stat (was 40 — oversized vs design).
                style: ZType.stat.copyWith(
                  color: ZveltTokens.text,
                  fontSize: 28,
                  height: 1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 6),
                child: Text(
                  '/ $goal kcal',
                  style: ZType.monoS.copyWith(
                    color: ZveltTokens.text2,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: ZveltTokens.s1),
                decoration: BoxDecoration(
                  color: overGoal ? ZveltTokens.error.withValues(alpha: 0.12) : ZveltTokens.brandTint,
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                ),
                child: Text(
                  overGoal ? '+${consumed - goal} over' : '$remaining left',
                  style: ZType.monoXS.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZveltTokens.s4),
          ClipRRect(
            borderRadius: BorderRadius.circular(ZveltTokens.rPill),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: ZveltTokens.surface2,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
              minHeight: 6,
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
// MACROS ROW
// ─────────────────────────────────────────────────────────────────────────────

class _MacrosRow extends StatelessWidget {
  const _MacrosRow({required this.totals, required this.goals});
  final _DiaryTotals totals;
  final NutritionGoals goals;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _MacroCard(
          label: 'Protein', value: totals.protein, goal: goals.proteinG.toDouble(),
          color: ZveltTokens.strength,
        )),
        const SizedBox(width: ZveltTokens.s3),
        Expanded(child: _MacroCard(
          label: 'Carbs', value: totals.carbs, goal: goals.carbsG.toDouble(),
          color: ZveltTokens.brand,
        )),
        const SizedBox(width: ZveltTokens.s3),
        Expanded(child: _MacroCard(
          label: 'Fat', value: totals.fat, goal: goals.fatG.toDouble(),
          color: ZveltTokens.strain,
        )),
      ],
    );
  }
}

class _MacroCard extends StatelessWidget {
  const _MacroCard({required this.label, required this.value, required this.goal, required this.color});
  final String label;
  final double value;
  final double goal;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // ── Design parity: circular 56px progress ring (4px stroke) with the
    // gram value centered inside and the label underneath — replaces the
    // old horizontal bar layout.
    final progress = goal > 0 ? (value / goal).clamp(0.0, 1.0) : 0.0;
    return Semantics(
      container: true,
      label: '$label: ${value.round()} of ${goal.round()} grams',
      excludeSemantics: true,
      child: ZCard(
      padding: const EdgeInsets.all(ZveltTokens.s4),
      child: Column(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 4,
                    strokeCap: StrokeCap.round,
                    color: color,
                    backgroundColor: ZveltTokens.surface3,
                  ),
                ),
                Text(
                  '${value.round()}',
                  style: ZType.stat.copyWith(
                      color: ZveltTokens.text, fontSize: 13, height: 1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(
                fontFamily: ZveltTokens.fontPrimary,
                color: ZveltTokens.text3,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              )),
          const SizedBox(height: 2),
          Text('of ${goal.round()}g',
              style: TextStyle(
                fontFamily: ZveltTokens.fontMono,
                color: ZveltTokens.text3,
                fontSize: 11,
              )),
        ],
      ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WATER CARD
// ─────────────────────────────────────────────────────────────────────────────

class _WaterCard extends StatelessWidget {
  const _WaterCard({required this.waterMl, required this.goalMl, required this.onTap});
  final int waterMl;
  final int goalMl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = goalMl > 0 ? (waterMl / goalMl).clamp(0.0, 1.0) : 0.0;
    return Semantics(
      button: true,
      label: 'Water: $waterMl of $goalMl millilitres. Tap to log water.',
      excludeSemantics: true,
      child: ZCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16), // design: 16
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: ZveltTokens.info.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(ZveltTokens.rSm),
            ),
            child: const Icon(AppIcons.water_bottle,
                color: ZveltTokens.recovery, size: 18), // design: 18
          ),
          const SizedBox(height: ZveltTokens.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$waterMl',
                style: ZType.stat.copyWith(color: ZveltTokens.recovery, fontSize: 20),
              ),
              const SizedBox(width: 2),
              Text('ml',
                  style: ZType.monoXS.copyWith(
                    color: ZveltTokens.recovery,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
          Text('/ ${goalMl}ml goal',
              style: ZType.monoXS.copyWith(
                color: ZveltTokens.text2,
              )),
          const SizedBox(height: ZveltTokens.s2),
          ClipRRect(
            borderRadius: BorderRadius.circular(ZveltTokens.rPill),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: ZveltTokens.surface2,
              valueColor: const AlwaysStoppedAnimation<Color>(ZveltTokens.recovery),
              minHeight: 4,
            ),
          ),
        ],
      ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WEIGHT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _WeightCard extends StatelessWidget {
  const _WeightCard({
    required this.displayKg,
    required this.loggedToday,
    required this.onTap,
  });

  /// Greutate afișată: log azi sau, dacă lipsește, bodyweight din profil (onboarding).
  final double? displayKg;
  final bool loggedToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = loggedToday
        ? 'logged today'
        : (displayKg != null ? 'from profile · tap to log' : 'tap to log');
    final hasValue = displayKg != null;
    return Semantics(
      button: true,
      label: hasValue
          ? 'Weight: ${displayKg!.toStringAsFixed(1)} kg, $subtitle'
          : 'Weight not logged. Tap to log.',
      excludeSemantics: true,
      child: ZCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16), // design: 16
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: ZveltTokens.brandTint,
              borderRadius: BorderRadius.circular(ZveltTokens.rSm),
            ),
            child: const Icon(AppIcons.balance_scale_left,
                color: ZveltTokens.brand, size: 18), // design: 18
          ),
          const SizedBox(height: ZveltTokens.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                hasValue ? displayKg!.toStringAsFixed(1) : '—',
                style: ZType.stat.copyWith(
                  color: hasValue ? ZveltTokens.brand : ZveltTokens.text3,
                  fontSize: 20,
                ),
              ),
              const SizedBox(width: 2),
              Text('kg',
                  style: ZType.monoXS.copyWith(
                    color: hasValue ? ZveltTokens.brand : ZveltTokens.text3,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
          Text(
            subtitle,
            style: ZType.bodyS.copyWith(
              color: ZveltTokens.text2,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: ZveltTokens.s2),
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: ZveltTokens.surface2,
              borderRadius: BorderRadius.circular(ZveltTokens.rPill),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MEAL SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _MealSection extends StatelessWidget {
  const _MealSection({
    required this.meal,
    required this.entries,
    required this.onAdd,
    required this.onRemove,
  });
  final String meal;
  final List<MealEntry> entries;
  final VoidCallback onAdd;
  final void Function(String) onRemove;

  String get _label {
    switch (meal) {
      case 'breakfast': return 'Breakfast';
      case 'lunch': return 'Lunch';
      case 'dinner': return 'Dinner';
      default: return 'Snacks';
    }
  }

  /// Design parity: meals use emoji glyphs (🌅 🥗 🍝 🍿), not stroke icons.
  String get _emoji {
    switch (meal) {
      case 'breakfast': return '🌅';
      case 'lunch': return '🥗';
      case 'dinner': return '🍝';
      default: return '🍿';
    }
  }

  double get _totalCalories => entries.fold(0, (s, e) => s + e.calories);

  @override
  Widget build(BuildContext context) {
    // ── Design parity: uniform 16px card padding (was EdgeInsets.zero with
    // ad-hoc insets), emoji meal glyph, brand-tinted 28px add tile (r9).
    return Padding(
      padding: const EdgeInsets.only(bottom: ZveltTokens.s3),
      child: ZCard(
        padding: const EdgeInsets.all(ZveltTokens.s4),
        child: Column(
          children: [
            Row(
              children: [
                Text(_emoji, style: const TextStyle(fontSize: 15, height: 1)),
                const SizedBox(width: ZveltTokens.s3),
                Text(_label,
                    style: ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 13)),
                const Spacer(),
                if (entries.isNotEmpty)
                  Text('${_totalCalories.round()} kcal',
                      style: ZType.monoS.copyWith(
                        color: ZveltTokens.text2,
                        fontWeight: FontWeight.w600,
                      )),
                const SizedBox(width: ZveltTokens.s3),
                Semantics(
                  button: true,
                  label: 'Add $_label entry',
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: onAdd,
                    // 28px visual tile per design, padded hit area ≥44.
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: ZveltTokens.brandTint,
                          borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                        ),
                        child: const Icon(AppIcons.plus,
                            size: 16, color: ZveltTokens.brand),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (entries.isNotEmpty) ...[
              const SizedBox(height: ZveltTokens.s2),
              ...entries.map((e) =>
                  _EntryRow(entry: e, onRemove: () => onRemove(e.id))),
            ],
          ],
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.onRemove});
  final MealEntry entry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: ZveltTokens.s4),
        color: ZveltTokens.error.withValues(alpha: 0.12),
        child: const Icon(AppIcons.trash, color: ZveltTokens.error),
      ),
      onDismissed: (_) => onRemove(),
      child: Padding(
        // Card now carries the 16px inset — rows only space vertically.
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.food.name,
                      style: ZType.bodyS.copyWith(
                        color: ZveltTokens.text, fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(_mealEntrySubtitle(entry),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: ZType.bodyS.copyWith(
                        color: ZveltTokens.text2,
                        fontSize: 11,
                      )),
                ],
              ),
            ),
            Text('${entry.calories.round()} kcal',
                style: ZType.num_.copyWith(
                    color: ZveltTokens.brand,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

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
  static const Duration _searchDebounce = Duration(milliseconds: 500);

  final _service = NutritionService.instance;
  final _searchCtrl = TextEditingController();
  List<FoodItem> _results = [];
  bool _loading = false;
  String? _searchError;
  Timer? _debounce;
  int _searchGeneration = 0;
  // Query whose results are currently displayed — 'No results' is only an
  // honest claim when a search for the VISIBLE query actually completed
  // (it used to flash during the debounce window before any search ran).
  String? _completedQuery;

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
          _searchError = null;
          _completedQuery = null;
        });
      }
      return;
    }
    final gen = ++_searchGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _searchError = null;
      });
    }
    final outcome = await _service.searchByName(trimmed);
    if (!mounted || gen != _searchGeneration) return;
    setState(() {
      _results = outcome.items;
      _searchError = outcome.errorMessage;
      _completedQuery = trimmed;
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

  // ── Tabs: Caută · Recente · Favorite · Custom · Mese ───────────────────────
  static const List<String> _tabLabels = ['Caută', 'Recente', 'Favorite', 'Custom', 'Mese', 'Rețete'];
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
          style: ZType.bodyM.copyWith(color: ZveltTokens.text, fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text('$brandPart${food.caloriesPer100g.round()} kcal/100g',
          style: ZType.bodyS.copyWith(color: ZveltTokens.text2, fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(isFav ? AppIcons.heart : AppIcons.heart,
                color: isFav ? ZveltTokens.brand : ZveltTokens.text3, size: 18),
            tooltip: isFav ? 'Scoate de la favorite' : 'Adaugă la favorite',
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
              decoration: const BoxDecoration(shape: BoxShape.circle).copyWith(color: ZveltTokens.surface2),
              child: Icon(icon, color: ZveltTokens.text3, size: 28),
            ),
            const SizedBox(height: ZveltTokens.s4),
            Text(text, textAlign: TextAlign.center, style: ZType.bodyM.copyWith(color: ZveltTokens.text2, fontSize: 13)),
          ],
        ),
      );

  Widget _altTabBody(ScrollController controller) {
    if (_tabLoading) {
      return const Center(child: CircularProgressIndicator(color: ZveltTokens.brand));
    }
    if (_tab == 1) {
      if (_recent.isEmpty) return _emptyHint(AppIcons.clock, 'Niciun aliment recent încă');
      return ListView.builder(
        controller: controller,
        itemCount: _recent.length,
        itemBuilder: (_, i) => _foodTile(_recent[i]),
      );
    }
    if (_tab == 2) {
      if (_favorites.isEmpty) return _emptyHint(AppIcons.heart, 'Niciun favorit. Atinge inima pe un aliment.');
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
            padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s2, ZveltTokens.s4, ZveltTokens.s2),
            child: OutlinedButton.icon(
              onPressed: _openCustomForm,
              icon: const Icon(AppIcons.plus, size: 18),
              label: const Text('Creează aliment custom'),
            ),
          ),
          if (_custom.isEmpty)
            Padding(
              padding: const EdgeInsets.all(ZveltTokens.s6),
              child: _emptyHint(AppIcons.restaurant, 'Niciun aliment custom încă'),
            )
          else
            for (final f in _custom) _customTile(f),
        ],
      );
    }
    if (_tab == 4) {
      // Mese (saved meal templates)
      if (_templates.isEmpty) return _emptyHint(AppIcons.restaurant, 'Nicio masă salvată încă');
      return ListView.builder(
        controller: controller,
        itemCount: _templates.length,
        itemBuilder: (_, i) {
          final t = _templates[i];
          return ListTile(
            title: Text(t.name,
                style: ZType.bodyM.copyWith(color: ZveltTokens.text, fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text('${t.itemCount} alimente · ${t.totalCalories.round()} kcal',
                style: ZType.bodyS.copyWith(color: ZveltTokens.text2, fontSize: 12)),
            trailing: const Icon(AppIcons.plus, color: ZveltTokens.brand, size: 20),
            onTap: () => _applyTemplate(t),
          );
        },
      );
    }
    // _tab == 5 — Rețete
    return ListView(
      controller: controller,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s2, ZveltTokens.s4, ZveltTokens.s2),
          child: OutlinedButton.icon(
            onPressed: () => _openRecipeBuilder(),
            icon: const Icon(AppIcons.plus, size: 18),
            label: const Text('Creează rețetă'),
          ),
        ),
        if (_recipes.isEmpty)
          Padding(
            padding: const EdgeInsets.all(ZveltTokens.s6),
            child: _emptyHint(AppIcons.restaurant, 'Nicio rețetă încă'),
          )
        else
          for (final r in _recipes) _recipeTile(r),
      ],
    );
  }

  Widget _recipeTile(Recipe r) {
    final perServ = r.servings > 0 ? r.totalCalories / r.servings : r.totalCalories;
    return ListTile(
      title: Text(r.name,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: ZType.bodyM.copyWith(color: ZveltTokens.text, fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text('${r.ingredients.length} ingr · ${perServ.round()} kcal/porție · ${r.servings} porții',
          style: ZType.bodyS.copyWith(color: ZveltTokens.text2, fontSize: 12)),
      trailing: PopupMenuButton<String>(
        icon: Icon(AppIcons.menu_dots_vertical, color: ZveltTokens.text3, size: 16),
        onSelected: (v) {
          if (v == 'apply') _applyRecipe(r);
          if (v == 'edit') _openRecipeBuilder(editing: r);
          if (v == 'delete') _deleteRecipe(r);
        },
        itemBuilder: (_) => const [
          PopupMenuItem<String>(value: 'apply', child: Text('Adaugă în jurnal')),
          PopupMenuItem<String>(value: 'edit', child: Text('Editează')),
          PopupMenuItem<String>(value: 'delete', child: Text('Șterge')),
        ],
      ),
      onTap: () => _applyRecipe(r),
    );
  }

  Future<void> _openRecipeBuilder({Recipe? editing}) async {
    final saved = await Navigator.of(context).push<Recipe>(
      MaterialPageRoute<Recipe>(builder: (_) => RecipeBuilderScreen(editing: editing)),
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
    await widget.onAdd(r.toMealEntry(meal: widget.meal, servingsToLog: servings));
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
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: ZType.bodyM.copyWith(color: ZveltTokens.text, fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text('$brandPart${food.caloriesPer100g.round()} kcal/100g',
          style: ZType.bodyS.copyWith(color: ZveltTokens.text2, fontSize: 12)),
      trailing: PopupMenuButton<String>(
        icon: Icon(AppIcons.menu_dots_vertical, color: ZveltTokens.text3, size: 16),
        onSelected: (v) {
          if (v == 'add') _selectFood(food);
          if (v == 'edit') _editCustom(food);
          if (v == 'delete') _deleteCustom(food);
        },
        itemBuilder: (_) => const [
          PopupMenuItem<String>(value: 'add', child: Text('Adaugă în jurnal')),
          PopupMenuItem<String>(value: 'edit', child: Text('Editează')),
          PopupMenuItem<String>(value: 'delete', child: Text('Șterge')),
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
    setState(() => _custom = _custom.map((f) => f.id == updated.id ? updated : f).toList());
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
          color: ZveltTokens.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
          boxShadow: ZveltTokens.shadowHero,
        ),
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: ZveltTokens.s3),
              width: 40, height: 4,
              decoration: BoxDecoration(color: ZveltTokens.border, borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s1, ZveltTokens.s4, 6),
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
                              _searchError = null;
                              _completedQuery = null;
                            });
                          }
                          return;
                        }
                        _debounce = Timer(_searchDebounce, () => _search(_searchCtrl.text));
                      },
                      decoration: InputDecoration(
                        hintText: 'Search food…',
                        hintStyle: ZType.bodyM.copyWith(color: ZveltTokens.text3),
                        prefixIcon: Icon(AppIcons.search, color: ZveltTokens.text3, size: 20),
                        filled: true,
                        fillColor: ZveltTokens.surface2,
                        contentPadding: const EdgeInsets.symmetric(vertical: ZveltTokens.s3, horizontal: ZveltTokens.s3),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                          borderSide: const BorderSide(color: ZveltTokens.brand, width: 1.5),
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
                      tooltip: 'Adaugă rapid calorii',
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
                separatorBuilder: (_, __) => const SizedBox(width: ZveltTokens.s2),
                itemBuilder: (_, i) {
                  final sel = _tab == i;
                  return GestureDetector(
                    onTap: () => _selectTab(i),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4),
                      decoration: BoxDecoration(
                        color: sel ? ZveltTokens.brand : ZveltTokens.surface2,
                        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                      ),
                      child: Text(_tabLabels[i],
                          style: ZType.bodyS.copyWith(
                            color: sel ? ZveltTokens.onBrand : ZveltTokens.text2,
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
                padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, 0, ZveltTokens.s5, ZveltTokens.s2),
                child: Text(
                  'USDA + Open Food Facts · scrie 3+ litere și așteaptă, sau scanează.',
                  style: ZType.bodyS.copyWith(
                    color: ZveltTokens.text2,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ),
            if (_tab == 0 && _searchError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, 0, ZveltTokens.s4, ZveltTokens.s2),
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
                              color: ZveltTokens.text, fontSize: 12, height: 1.35),
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
                  ? const Center(child: CircularProgressIndicator(color: ZveltTokens.brand))
                  : _results.isEmpty &&
                          _searchError == null &&
                          _completedQuery == _searchCtrl.text.trim() &&
                          _completedQuery != null
                      ? Center(
                          child: Text('No results',
                              style: ZType.bodyM.copyWith(color: ZveltTokens.text2)))
                      : _results.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: ZveltTokens.surface2,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(AppIcons.search,
                                        color: ZveltTokens.text3, size: 28),
                                  ),
                                  const SizedBox(height: ZveltTokens.s4),
                                  Text(
                                    'Search food or scan a barcode',
                                    style: ZType.bodyM.copyWith(
                                        color: ZveltTokens.text2, fontSize: 13),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              controller: controller,
                              itemCount: _results.length,
                              itemBuilder: (_, i) {
                                final food = _results[i];
                                final brandPart = food.brand.isNotEmpty ? '${food.brand} · ' : '';
                                var sub = '$brandPart${food.caloriesPer100g.round()} kcal/100g';
                                final sg = food.servingGrams;
                                if (sg != null && sg > 0) {
                                  final u = food.portionUnitKey ?? 'serving';
                                  final oneLabel = NutritionFoodLabels.formatUnitCount(1, u);
                                  sub += ' · ~${sg.round()} g / $oneLabel';
                                }
                                return ListTile(
                                  title: Text(food.name,
                                      style: ZType.bodyM.copyWith(
                                          color: ZveltTokens.text,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                  subtitle: Text(
                                    sub,
                                    style: ZType.bodyS.copyWith(
                                        color: ZveltTokens.text2, fontSize: 12),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        icon: Icon(AppIcons.heart,
                                            color: _favIds.contains(food.id)
                                                ? ZveltTokens.brand
                                                : ZveltTokens.text3,
                                            size: 18),
                                        tooltip: 'Favorite',
                                        onPressed: () => _toggleFavorite(food),
                                      ),
                                      const Icon(AppIcons.plus, color: ZveltTokens.brand, size: 20),
                                    ],
                                  ),
                                  onTap: () => _selectFood(food),
                                );
                              },
                            ),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: ZveltTokens.s2),
            Container(
              width: 40, height: 4,
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
                  style: ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 15)),
              subtitle: Text('EAN / UPC etc.',
                  style: ZType.bodyS.copyWith(color: ZveltTokens.text2, fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'scan'),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(ZveltTokens.s2),
                decoration: BoxDecoration(
                  color: ZveltTokens.surface2,
                  borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                ),
                child: Icon(AppIcons.apps,
                    color: ZveltTokens.text2, size: 18),
              ),
              title: Text('Enter manually',
                  style: ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 15)),
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
          content: Text(result.errorMessage ?? 'Product not found in database.'),
        ),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PORTION SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _PortionSheet extends StatefulWidget {
  const _PortionSheet({required this.food, required this.meal, required this.onAdd});
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
      unitKey == 'egg' || unitKey == 'slice' || unitKey == 'waffle' || unitKey == 'cookie';

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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
        boxShadow: ZveltTokens.shadowHero,
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: ZveltTokens.s3),
              width: 40, height: 4,
              decoration: BoxDecoration(color: ZveltTokens.border, borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, ZveltTokens.s1, ZveltTokens.s5, 0),
            child: Text(widget.food.name,
                style: ZType.h2.copyWith(color: ZveltTokens.text, fontSize: 18)),
          ),
          if (widget.food.brand.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: ZveltTokens.s5, top: 2),
              child: Text(widget.food.brand,
                  style: ZType.bodyS.copyWith(color: ZveltTokens.text2, fontSize: 13)),
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
                padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, ZveltTokens.s2, ZveltTokens.s5, 0),
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
                      style: ZType.stat.copyWith(
                          color: ZveltTokens.brand, fontSize: 15),
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
                    _unitCount = _wholeUnits ? v.round().clamp(1, 24).toDouble() : v;
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
                      style: ZType.bodyS.copyWith(
                          color: ZveltTokens.text2)),
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
                      style: ZType.stat.copyWith(
                          color: ZveltTokens.brand, fontSize: 15)),
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
                _NutrPreview(label: 'Calories', value: '${_calories.round()}', unit: 'kcal', color: ZveltTokens.brand),
                _NutrPreview(label: 'Protein', value: '${_protein.round()}', unit: 'g', color: ZveltTokens.strength),
                _NutrPreview(label: 'Carbs', value: '${_carbs.round()}', unit: 'g', color: ZveltTokens.brand),
                _NutrPreview(label: 'Fat', value: '${_fat.round()}', unit: 'g', color: ZveltTokens.strain),
              ],
            ),
          ),
          const SizedBox(height: ZveltTokens.s5),
          Padding(
            padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, 0, ZveltTokens.s5, ZveltTokens.s6),
            child: FilledButton(
              onPressed: _adding ? null : () async {
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
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                ),
              ),
              child: _adding
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text('Add to diary',
                      style: ZType.h4.copyWith(
                          color: Colors.white, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PortionToggleChip extends StatelessWidget {
  const _PortionToggleChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s2),
        decoration: BoxDecoration(
          color: selected ? ZveltTokens.brand : ZveltTokens.surface2,
          borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        ),
        child: Text(label,
            style: ZType.bodyS.copyWith(
              color: selected ? Colors.white : ZveltTokens.text2,
              fontWeight: FontWeight.w700,
            )),
      ),
    );
  }
}

class _PortionQuickChip extends StatelessWidget {
  const _PortionQuickChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: ZveltTokens.s2),
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
  const _NutrPreview({required this.label, required this.value, required this.unit, required this.color});
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
            Text(value,
                style: ZType.stat.copyWith(color: color, fontSize: 15)),
            const SizedBox(width: 1),
            Text(unit,
                style: TextStyle(
                  fontFamily: ZveltTokens.fontMono,
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
        Text(label,
            style: TextStyle(
              fontFamily: ZveltTokens.fontPrimary,
              color: ZveltTokens.text2,
              fontSize: 11,
              fontWeight: FontWeight.w500,
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
          child: Material(
            color: ZveltTokens.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: ZveltTokens.s3),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: ZveltTokens.border, borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, 0, ZveltTokens.s3, ZveltTokens.s2),
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
                                child: CircularProgressIndicator(strokeWidth: 2, color: ZveltTokens.brand),
                              ),
                            ),
                          TextButton.icon(
                            onPressed: () async {
                              Navigator.pop(context);
                              await widget.onRegenerateWeek();
                            },
                            icon: const Icon(AppIcons.sparkles, size: 16),
                            label: const Text('Week AI'),
                            style: TextButton.styleFrom(foregroundColor: ZveltTokens.brand),
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
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s5, vertical: ZveltTokens.s3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s3, ZveltTokens.s4, ZveltTokens.s2),
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
                                padding: const EdgeInsets.only(bottom: ZveltTokens.s3),
                                child: Container(
                                  padding: const EdgeInsets.all(ZveltTokens.s3),
                                  decoration: BoxDecoration(
                                    color: ZveltTokens.surface2,
                                    borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        item.text,
                                        style: ZType.bodyS.copyWith(
                                            color: ZveltTokens.text, height: 1.35),
                                      ),
                                      if (item.portion != null && item.portion!.trim().isNotEmpty) ...[
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
                                              borderSide: BorderSide(color: ZveltTokens.border),
                                              borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderSide: BorderSide(color: ZveltTokens.border),
                                              borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                                            ),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: ZveltTokens.s1),
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              dropdownColor: ZveltTokens.surface,
                                              value: _dropdownValue(item),
                                              isExpanded: true,
                                              style: ZType.bodyS.copyWith(color: ZveltTokens.text),
                                              items: item.proteinChoices!
                                                  .map(
                                                    (s) => DropdownMenuItem<String>(
                                                      value: s,
                                                      child: Text(s, overflow: TextOverflow.ellipsis),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: (v) {
                                                if (v == null) return;
                                                _patchItem(mi, ii, item.copyWith(selectedProtein: v));
                                                Future.microtask(() => _save(close: false));
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
                      ZveltTokens.s3 + MediaQuery.of(context).viewPadding.bottom + MediaQuery.of(context).viewInsets.bottom,
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
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, ZveltTokens.s3, ZveltTokens.s5, ZveltTokens.s4),
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
                  style: ZType.h2.copyWith(color: ZveltTokens.text, fontSize: 18)),
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
                      style: ZType.monoS.copyWith(
                          color: ZveltTokens.text3)),
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
                    style: ZType.bodyS.copyWith(fontSize: 12, color: ZveltTokens.text2)),
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
                      style: ZType.bodyM.copyWith(
                          fontWeight: FontWeight.w700)),
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
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, ZveltTokens.s3, ZveltTokens.s5, ZveltTokens.s4),
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
                  style: ZType.h2.copyWith(color: ZveltTokens.text, fontSize: 18)),
              const SizedBox(height: ZveltTokens.s4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _stepBtn(AppIcons.minus,
                      () => setState(() => _kg = (_kg - 0.1).clamp(30.0, 250.0))),
                  const SizedBox(width: ZveltTokens.s5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(_kg.toStringAsFixed(1),
                          style: ZType.stat
                              .copyWith(fontSize: 34, color: ZveltTokens.brand)),
                      const SizedBox(width: ZveltTokens.s1),
                      Text('kg',
                          style: ZType.monoS.copyWith(
                              fontSize: 13,
                              color: ZveltTokens.text3)),
                    ],
                  ),
                  const SizedBox(width: ZveltTokens.s5),
                  _stepBtn(AppIcons.plus,
                      () => setState(() => _kg = (_kg + 0.1).clamp(30.0, 250.0))),
                ],
              ),
              const SizedBox(height: ZveltTokens.s5),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, double.parse(_kg.toStringAsFixed(1))),
                  style: FilledButton.styleFrom(
                    backgroundColor: ZveltTokens.brand,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ZveltTokens.rLg)),
                  ),
                  child: Text('Save',
                      style: ZType.bodyM.copyWith(
                          fontWeight: FontWeight.w700)),
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
    _calCtrl.dispose(); _protCtrl.dispose(); _fatCtrl.dispose();
    _carbsCtrl.dispose(); _waterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
        boxShadow: ZveltTokens.shadowHero,
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Container(
            margin: const EdgeInsets.symmetric(vertical: ZveltTokens.s3),
            width: 40, height: 4,
            decoration: BoxDecoration(color: ZveltTokens.border, borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
          )),
          Padding(
            padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, ZveltTokens.s1, ZveltTokens.s5, ZveltTokens.s4),
            child: Text('Daily goals',
                style: ZType.h2.copyWith(color: ZveltTokens.text, fontSize: 18)),
          ),
          ...[
            ['Calories (kcal)', _calCtrl],
            ['Protein (g)', _protCtrl],
            ['Carbs (g)', _carbsCtrl],
            ['Fat (g)', _fatCtrl],
            ['Water (ml)', _waterCtrl],
          ].map((row) => Padding(
            padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, 0, ZveltTokens.s5, ZveltTokens.s3),
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
                  borderSide: const BorderSide(color: ZveltTokens.brand, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
              ),
            ),
          )),
          Padding(
            padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, ZveltTokens.s2, ZveltTokens.s5, ZveltTokens.s6),
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
                  if (cal == null || prot == null || fat == null ||
                      carbs == null || water == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Fill in every goal field.')),
                    );
                    return;
                  }
                  if (cal <= 0 || prot <= 0 || fat <= 0 || carbs <= 0 || water <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Goals must be greater than zero.')),
                    );
                    return;
                  }
                  final goals = NutritionGoals(
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
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                  ),
                ),
                child: Text('Save goals',
                    style: ZType.h4.copyWith(
                        color: Colors.white, fontSize: 15)),
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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
      ),
      padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, ZveltTokens.s4, ZveltTokens.s5, ZveltTokens.s6),
      child: child,
    );

Widget _sheetHandle() => Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: ZveltTokens.s4),
        decoration: BoxDecoration(color: ZveltTokens.border, borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
      ),
    );

Widget _numRow(String label, TextEditingController c, String hint) => Padding(
      padding: const EdgeInsets.only(bottom: ZveltTokens.s2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: ZType.bodyM.copyWith(color: ZveltTokens.text))),
          SizedBox(
            width: 110,
            child: TextField(
              controller: c,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              textAlign: TextAlign.center,
              style: ZType.num_.copyWith(color: ZveltTokens.text),
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                hintStyle: ZType.bodyS.copyWith(color: ZveltTokens.text4),
                filled: true,
                fillColor: ZveltTokens.surface2,
                contentPadding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: ZveltTokens.s3),
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

double? _parseNum(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

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
      setState(() => _error = 'Introdu caloriile');
      return;
    }
    final food = FoodItem(
      id: 'quick:${DateTime.now().microsecondsSinceEpoch}',
      name: _name.text.trim().isEmpty ? 'Adaos rapid' : _name.text.trim(),
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
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _sheetShell(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sheetHandle(),
            Text('Adaugă rapid calorii', style: ZType.h3.copyWith(color: ZveltTokens.text)),
            const SizedBox(height: ZveltTokens.s4),
            _numRow('Calorii', _cal, 'kcal'),
            _numRow('Proteine (g)', _p, 'opț'),
            _numRow('Carbo (g)', _c, 'opț'),
            _numRow('Grăsimi (g)', _f, 'opț'),
            const SizedBox(height: ZveltTokens.s1),
            TextField(
              controller: _name,
              style: ZType.bodyM.copyWith(color: ZveltTokens.text),
              decoration: InputDecoration(
                hintText: 'Nume (opțional)',
                hintStyle: ZType.bodyS.copyWith(color: ZveltTokens.text3),
                filled: true,
                fillColor: ZveltTokens.surface2,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: ZveltTokens.s3),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(ZveltTokens.rSm), borderSide: BorderSide.none),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: ZveltTokens.s2),
              Text(_error!, style: ZType.bodyS.copyWith(color: ZveltTokens.error)),
            ],
            const SizedBox(height: ZveltTokens.s4),
            SizedBox(
              height: 50,
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: ZveltTokens.brand,
                    foregroundColor: ZveltTokens.onBrand,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZveltTokens.rMd))),
                onPressed: _add,
                child: Text('Adaugă', style: ZType.bodyM.copyWith(color: ZveltTokens.onBrand, fontWeight: FontWeight.w600)),
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
      setState(() => _error = 'Introdu un nume');
      return;
    }
    if (cal == null || cal < 0) {
      setState(() => _error = 'Introdu caloriile / 100g');
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
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _sheetShell(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sheetHandle(),
            Text(widget.editing == null ? 'Aliment custom' : 'Editează aliment',
                style: ZType.h3.copyWith(color: ZveltTokens.text)),
            const SizedBox(height: ZveltTokens.s1),
            Text('Valori per 100g.', style: ZType.bodyS.copyWith(color: ZveltTokens.text3)),
            const SizedBox(height: ZveltTokens.s4),
            TextField(
              controller: _name,
              style: ZType.bodyM.copyWith(color: ZveltTokens.text),
              decoration: InputDecoration(
                hintText: 'Nume',
                hintStyle: ZType.bodyS.copyWith(color: ZveltTokens.text3),
                filled: true,
                fillColor: ZveltTokens.surface2,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: ZveltTokens.s3),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(ZveltTokens.rSm), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: ZveltTokens.s2),
            TextField(
              controller: _brand,
              style: ZType.bodyM.copyWith(color: ZveltTokens.text),
              decoration: InputDecoration(
                hintText: 'Brand (opțional)',
                hintStyle: ZType.bodyS.copyWith(color: ZveltTokens.text3),
                filled: true,
                fillColor: ZveltTokens.surface2,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: ZveltTokens.s3),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(ZveltTokens.rSm), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: ZveltTokens.s3),
            _numRow('Calorii / 100g', _cal, 'kcal'),
            _numRow('Proteine / 100g', _p, 'g'),
            _numRow('Carbo / 100g', _c, 'g'),
            _numRow('Grăsimi / 100g', _f, 'g'),
            if (_error != null) ...[
              const SizedBox(height: ZveltTokens.s2),
              Text(_error!, style: ZType.bodyS.copyWith(color: ZveltTokens.error)),
            ],
            const SizedBox(height: ZveltTokens.s4),
            SizedBox(
              height: 50,
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: ZveltTokens.brand,
                    foregroundColor: ZveltTokens.onBrand,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZveltTokens.rMd))),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: ZveltTokens.onBrand))
                    : Text('Salvează', style: ZType.bodyM.copyWith(color: ZveltTokens.onBrand, fontWeight: FontWeight.w600)),
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
      title: Text(widget.recipe.name, style: ZType.h4.copyWith(color: ZveltTokens.text)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${(perServ * _servings).round()} kcal',
              style: ZType.num_.copyWith(color: ZveltTokens.text, fontSize: 28)),
          Text('${_fmtNum(_servings)} porții', style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
          const SizedBox(height: ZveltTokens.s2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(AppIcons.minus, color: ZveltTokens.brand),
                onPressed: () => setState(() => _servings = (_servings - 0.5).clamp(0.5, 20)),
              ),
              SizedBox(
                width: 56,
                child: Text(_fmtNum(_servings),
                    textAlign: TextAlign.center, style: ZType.num_.copyWith(color: ZveltTokens.text, fontSize: 20)),
              ),
              IconButton(
                icon: const Icon(AppIcons.plus, color: ZveltTokens.brand),
                onPressed: () => setState(() => _servings = (_servings + 0.5).clamp(0.5, 20)),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anulează')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: ZveltTokens.brand, foregroundColor: ZveltTokens.onBrand),
          onPressed: () => Navigator.pop(context, _servings),
          child: const Text('Adaugă'),
        ),
      ],
    );
  }
}
