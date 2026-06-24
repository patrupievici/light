import 'dart:async';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/zvelt_tokens.dart';
import '../../services/ai_chat_service.dart';
import '../../services/app_data_cache.dart';
import '../../services/planned_workouts_service.dart';
import '../../services/workout_service.dart';
import 'workout_tracker_screen.dart';

// ─── Phase enum ──────────────────────────────────────────────────────────────

enum _Phase { input, loading, result, error }

// ─── Main screen ─────────────────────────────────────────────────────────────

class ProgramBuilderScreen extends StatefulWidget {
  const ProgramBuilderScreen({super.key});

  @override
  State<ProgramBuilderScreen> createState() => _ProgramBuilderScreenState();
}

class _ProgramBuilderScreenState extends State<ProgramBuilderScreen> {
  // ─── Phase ───────────────────────────────────────────────────────────────
  _Phase _phase = _Phase.input;
  int _step = 0;

  // ─── Step 0 — About You ──────────────────────────────────────────────────
  String _goal = 'build_muscle';
  String _level = 'intermediate';
  final TextEditingController _weightCtrl = TextEditingController();
  final TextEditingController _heightCtrl = TextEditingController();
  final TextEditingController _ageCtrl = TextEditingController();
  String _gender = '';

  // ─── Step 1 — Training ───────────────────────────────────────────────────
  int _daysPerWeek = 4;
  int _sessionMinutes = 45;
  List<String> _equipment = ['gym'];
  String _workoutType = 'strength';

  // ─── Step 2 — Nutrition & Notes ──────────────────────────────────────────
  List<String> _dietaryPref = [];
  final TextEditingController _allergiesCtrl = TextEditingController();
  final TextEditingController _caloriesCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();

  // ─── Result & Error ──────────────────────────────────────────────────────
  Map<String, dynamic>? _plan;
  String _errorMsg = '';

  // ─── Expanded day cards ──────────────────────────────────────────────────
  final Set<int> _expandedDays = {0};

  @override
  void dispose() {
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _ageCtrl.dispose();
    _allergiesCtrl.dispose();
    _caloriesCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ─── Generate ────────────────────────────────────────────────────────────

  Future<void> _generate() async {
    setState(() => _phase = _Phase.loading);
    try {
      final double? weightKg = _weightCtrl.text.isNotEmpty
          ? double.tryParse(_weightCtrl.text)
          : null;
      final double? heightCm = _heightCtrl.text.isNotEmpty
          ? double.tryParse(_heightCtrl.text)
          : null;
      final int? age =
          _ageCtrl.text.isNotEmpty ? int.tryParse(_ageCtrl.text) : null;
      final int? targetCalories = _caloriesCtrl.text.isNotEmpty
          ? int.tryParse(_caloriesCtrl.text)
          : null;

      final inputs = <String, dynamic>{
        'goal': _goal,
        'level': _level,
        'daysPerWeek': _daysPerWeek,
        'sessionMinutes': _sessionMinutes,
        'equipment': _equipment,
        'workoutType': _workoutType,
        if (weightKg != null) 'weightKg': weightKg,
        if (heightCm != null) 'heightCm': heightCm,
        if (age != null) 'age': age,
        if (_gender.isNotEmpty) 'gender': _gender,
        if (_dietaryPref.isNotEmpty) 'dietaryPreference': _dietaryPref,
        if (_allergiesCtrl.text.isNotEmpty) 'allergies': _allergiesCtrl.text,
        if (targetCalories != null) 'targetCalories': targetCalories,
        if (_notesCtrl.text.isNotEmpty) 'notes': _notesCtrl.text,
      };

      final data = await AiChatService().generateWeeklyPlan(inputs);
      final plan = data['plan'] as Map<String, dynamic>;
      setState(() {
        _plan = plan;
        _phase = _Phase.result;
        _expandedDays
          ..clear()
          ..add(0);
      });
    } catch (e) {
      setState(() {
        _errorMsg = e.toString().replaceFirst('Exception: ', '');
        _phase = _Phase.error;
      });
    }
  }

  Future<void> _savePlan() async {
    final plan = _plan;
    if (plan == null) return;
    setState(() => _phase = _Phase.loading);
    // Track each step independently so the snackbar reflects what *actually*
    // happened. Previously the calendar sync was swallowed silently and the
    // user was told it succeeded.
    bool localOk = false;
    bool calendarOk = false;
    String? calendarError;
    try {
      await AppDataCache.instance.saveProgramBuilderPlan(plan);
      localOk = true;
    } catch (e) {
      if (!mounted) return;
      setState(() => _phase = _Phase.result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e'), backgroundColor: ZveltTokens.error),
      );
      return;
    }
    try {
      await PlannedWorkoutsService().generateWeekly(force: true);
      calendarOk = true;
    } catch (e) {
      calendarError = e.toString().replaceFirst('Exception: ', '');
    }
    if (!mounted) return;
    setState(() => _phase = _Phase.result);
    if (calendarOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan saved and synced to your calendar.')),
      );
    } else if (localOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Plan saved locally. Calendar sync failed: $calendarError"),
          backgroundColor: ZveltTokens.warn,
        ),
      );
    }
  }

  Future<void> _startTodaysWorkout() async {
    try {
      WorkoutDto created;
      try {
        created = await WorkoutService().createWorkoutFromSuggestion();
      } catch (_) {
        created = await WorkoutService().createWorkout();
      }
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => WorkoutTrackerScreen(workoutId: created.id),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  // ─── Navigation helpers ──────────────────────────────────────────────────

  void _nextStep() {
    if (_step < 2) {
      setState(() => _step++);
    } else {
      _generate();
    }
  }

  void _prevStep() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _Phase.input => _buildInputPhase(),
      _Phase.loading => _buildLoadingPhase(),
      _Phase.result => _buildResultPhase(),
      _Phase.error => _buildErrorPhase(),
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE: INPUT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildInputPhase() {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        backgroundColor: ZveltTokens.bg,
        elevation: 0,
        title: const Text('Weekly Plan'),
        leading: _step == 0
            ? IconButton(
                icon: const Icon(AppIcons.cross_small),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : IconButton(
                icon: const Icon(AppIcons.arrow_small_left),
                onPressed: _prevStep,
              ),
      ),
      body: Column(
        children: [
          _StepIndicator(currentStep: _step, totalSteps: 3),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  ZveltTokens.s5, ZveltTokens.s5, ZveltTokens.s5, 100),
              child: _buildStepContent(),
            ),
          ),
          _buildInputBottomBar(),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    return switch (_step) {
      0 => _buildStep0(),
      1 => _buildStep1(),
      2 => _buildStep2(),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _buildInputBottomBar() {
    final isLastStep = _step == 2;
    return Container(
      padding: const EdgeInsets.fromLTRB(
          ZveltTokens.s5, ZveltTokens.s3, ZveltTokens.s5, ZveltTokens.s8),
      decoration: BoxDecoration(
        color: ZveltTokens.bg,
        border: Border(top: BorderSide(color: ZveltTokens.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLastStep) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _generate,
                icon: const Icon(AppIcons.sparkles, size: 18),
                label: const Text('Generate My Plan'),
                style: FilledButton.styleFrom(
                  backgroundColor: ZveltTokens.brand,
                  foregroundColor: ZveltTokens.onBrand,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ZveltTokens.rXl),
                  ),
                  minimumSize: const Size(double.infinity, 52),
                ),
              ),
            ),
            const SizedBox(height: ZveltTokens.s2),
            Text(
              'General fitness guidance. Not medical advice.',
              textAlign: TextAlign.center,
              style: ZType.bodyS.copyWith(fontSize: 11),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _nextStep,
                style: FilledButton.styleFrom(
                  backgroundColor: ZveltTokens.brand,
                  foregroundColor: ZveltTokens.onBrand,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ZveltTokens.rXl),
                  ),
                  minimumSize: const Size(double.infinity, 52),
                ),
                child: const Text('Continue →'),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Step 0 ───────────────────────────────────────────────────────────────

  Widget _buildStep0() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Goal'),
        const SizedBox(height: 10),
        _GoalGrid(
          selected: _goal,
          options: const [
            _GoalOption('lose_weight', 'Lose Weight', AppIcons.arrow_trend_down),
            _GoalOption('build_muscle', 'Build Muscle', AppIcons.gym),
            _GoalOption('improve_fitness', 'Improve Fitness', AppIcons.running),
            _GoalOption('maintain', 'Maintain', AppIcons.balance_scale_left),
          ],
          onSelect: (v) => setState(() => _goal = v),
        ),
        const SizedBox(height: ZveltTokens.s6),
        const _SectionLabel('Level'),
        const SizedBox(height: 10),
        _ChipRow(
          options: const ['beginner', 'intermediate', 'advanced'],
          labels: const ['Beginner', 'Intermediate', 'Advanced'],
          selected: [_level],
          multiSelect: false,
          onTap: (v) => setState(() => _level = v),
        ),
        const SizedBox(height: ZveltTokens.s6),
        const _SectionLabel('Body (optional)'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _weightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}\.?\d{0,1}')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Weight (kg)',
                  hintText: 'e.g. 80',
                ),
              ),
            ),
            const SizedBox(width: ZveltTokens.s3),
            Expanded(
              child: TextField(
                controller: _heightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}\.?\d{0,1}')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Height (cm)',
                  hintText: 'e.g. 175',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: ZveltTokens.s4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 90,
              child: TextField(
                controller: _ageCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                decoration: const InputDecoration(
                  labelText: 'Age',
                  hintText: 'e.g. 28',
                ),
              ),
            ),
            const SizedBox(width: ZveltTokens.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gender (optional)',
                    style: ZType.bodyS.copyWith(
                      color: ZveltTokens.text2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _ChipRow(
                    options: const ['male', 'female', 'other', 'prefer_not_to_say'],
                    labels: const ['Male', 'Female', 'Other', 'N/A'],
                    selected: _gender.isNotEmpty ? [_gender] : [],
                    multiSelect: false,
                    onTap: (v) => setState(() => _gender = _gender == v ? '' : v),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Step 1 ───────────────────────────────────────────────────────────────

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Training days per week'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _daysPerWeek.toDouble(),
                min: 1,
                max: 7,
                divisions: 6,
                label: '$_daysPerWeek',
                onChanged: (v) => setState(() => _daysPerWeek = v.round()),
              ),
            ),
            Container(
              width: 44,
              alignment: Alignment.center,
              child: Text(
                '$_daysPerWeek',
                style: ZType.num_.copyWith(
                  color: ZveltTokens.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        Text(
          '$_daysPerWeek day${_daysPerWeek == 1 ? '' : 's'} per week',
          style: ZType.bodyS.copyWith(
            color: ZveltTokens.text2,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: ZveltTokens.s6),
        const _SectionLabel('Session duration'),
        const SizedBox(height: 10),
        Wrap(
          spacing: ZveltTokens.s2,
          runSpacing: ZveltTokens.s2,
          children: [
            for (final entry in [
              (20, '20 min'),
              (30, '30 min'),
              (45, '45 min'),
              (60, '60 min'),
              (90, '90 min+'),
            ])
              _SelectChip(
                label: entry.$2,
                selected: _sessionMinutes == entry.$1,
                onTap: () => setState(() => _sessionMinutes = entry.$1),
              ),
          ],
        ),
        const SizedBox(height: ZveltTokens.s6),
        const _SectionLabel('Equipment'),
        const SizedBox(height: 10),
        _ChipRow(
          options: const ['gym', 'home', 'bodyweight', 'dumbbells', 'resistance_bands'],
          labels: const ['Gym', 'Home', 'Bodyweight', 'Dumbbells', 'Resistance Bands'],
          selected: _equipment,
          multiSelect: true,
          onTap: (v) => setState(() {
            if (_equipment.contains(v)) {
              _equipment = List.from(_equipment)..remove(v);
            } else {
              _equipment = List.from(_equipment)..add(v);
            }
          }),
        ),
        const SizedBox(height: ZveltTokens.s6),
        const _SectionLabel('Workout type'),
        const SizedBox(height: 10),
        _ChipRow(
          options: const ['strength', 'cardio', 'hybrid', 'mobility', 'sport_specific'],
          labels: const ['Strength', 'Cardio', 'Hybrid', 'Mobility', 'Sport-specific'],
          selected: [_workoutType],
          multiSelect: false,
          onTap: (v) => setState(() => _workoutType = v),
        ),
      ],
    );
  }

  // ─── Step 2 ───────────────────────────────────────────────────────────────

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Dietary preference'),
        const SizedBox(height: 10),
        _ChipRow(
          options: const [
            'none',
            'vegetarian',
            'vegan',
            'pescatarian',
            'keto',
            'low_carb',
            'halal',
            'kosher',
          ],
          labels: const [
            'None',
            'Vegetarian',
            'Vegan',
            'Pescatarian',
            'Keto',
            'Low-carb',
            'Halal',
            'Kosher',
          ],
          selected: _dietaryPref,
          multiSelect: true,
          onTap: (v) => setState(() {
            if (v == 'none') {
              _dietaryPref = ['none'];
            } else {
              _dietaryPref = List.from(_dietaryPref)..remove('none');
              if (_dietaryPref.contains(v)) {
                _dietaryPref.remove(v);
              } else {
                _dietaryPref.add(v);
              }
            }
          }),
        ),
        const SizedBox(height: ZveltTokens.s6),
        const _SectionLabel('Allergies (optional)'),
        const SizedBox(height: 10),
        TextField(
          controller: _allergiesCtrl,
          decoration: const InputDecoration(
            hintText: 'e.g. nuts, dairy, gluten',
          ),
        ),
        const SizedBox(height: ZveltTokens.s6),
        const _SectionLabel('Daily calorie target (optional)'),
        const SizedBox(height: 10),
        TextField(
          controller: _caloriesCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            hintText: 'Leave blank to auto-calculate',
            suffixText: 'kcal',
          ),
        ),
        const SizedBox(height: ZveltTokens.s6),
        const _SectionLabel('Extra notes (optional)'),
        const SizedBox(height: 10),
        TextField(
          controller: _notesCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText:
                'e.g. bad knee, morning workouts, prefer compound movements',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: ZveltTokens.s4),
        Text(
          'Your plan is generated using your profile data and these preferences.',
          style: ZType.bodyS.copyWith(
            color: ZveltTokens.text2,
            fontSize: 12,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE: LOADING
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLoadingPhase() {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: SafeArea(
        child: _LoadingBody(
          onCancel: () => setState(() => _phase = _Phase.input),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE: RESULT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildResultPhase() {
    final plan = _plan ?? {};
    final days = (plan['days'] as List<dynamic>?)
            ?.map((d) => d as Map<String, dynamic>)
            .toList() ??
        [];
    final weekSummary = plan['weekSummary'] as String? ?? '';
    final totalWorkoutDays = plan['totalWorkoutDays'] as int? ?? 0;
    final avgDailyCalories = plan['avgDailyCalories'] as int? ?? 0;

    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        backgroundColor: ZveltTokens.bg,
        elevation: 0,
        title: const Text('Weekly Plan'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(
            onPressed: () => setState(() {
              _phase = _Phase.input;
            }),
            icon: const Icon(AppIcons.sparkles, size: 15),
            label: const Text('Regenerate'),
            style: TextButton.styleFrom(
              foregroundColor: ZveltTokens.text2,
            ),
          ),
          const SizedBox(width: ZveltTokens.s1),
          Padding(
            padding: const EdgeInsets.only(right: ZveltTokens.s3),
            child: FilledButton(
              onPressed: _savePlan,
              style: FilledButton.styleFrom(
                backgroundColor: ZveltTokens.brand,
                foregroundColor: ZveltTokens.onBrand,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(
                    horizontal: ZveltTokens.s4, vertical: 0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ZveltTokens.rLg),
                ),
                textStyle: ZType.bodyS.copyWith(fontWeight: FontWeight.w700),
              ),
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(
                ZveltTokens.s4, 0, ZveltTokens.s4, 120),
            children: [
              // Header card
              if (weekSummary.isNotEmpty || totalWorkoutDays > 0) ...[
                _WeekHeaderCard(
                  weekSummary: weekSummary,
                  totalWorkoutDays: totalWorkoutDays,
                  avgDailyCalories: avgDailyCalories,
                ),
                const SizedBox(height: ZveltTokens.s4),
              ],
              // Week strip
              if (days.isNotEmpty) ...[
                _WeekStrip(days: days),
                const SizedBox(height: ZveltTokens.s4),
              ],
              // Day cards
              for (int i = 0; i < days.length; i++) ...[
                _DayCard(
                  dayData: days[i],
                  dayIndex: i,
                  isExpanded: _expandedDays.contains(i),
                  onToggle: () => setState(() {
                    if (_expandedDays.contains(i)) {
                      _expandedDays.remove(i);
                    } else {
                      _expandedDays.add(i);
                    }
                  }),
                ),
                const SizedBox(height: ZveltTokens.s3),
              ],
            ],
          ),
          // Sticky bottom bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ResultBottomBar(
              onStart: _startTodaysWorkout,
              totalDays: days.length,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PHASE: ERROR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildErrorPhase() {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(ZveltTokens.s8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Icon(
                      AppIcons.sparkles,
                      size: 48,
                      color: ZveltTokens.text2,
                    ),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: ZveltTokens.error,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        AppIcons.cross_small,
                        size: 14,
                        color: ZveltTokens.onBrand,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ZveltTokens.s5),
                Text(
                  "Couldn't generate your plan",
                  textAlign: TextAlign.center,
                  style: ZType.clean.copyWith(fontSize: 15),
                ),
                const SizedBox(height: ZveltTokens.s2),
                Text(
                  _errorMsg,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ZType.bodyS,
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _generate,
                    style: FilledButton.styleFrom(
                      backgroundColor: ZveltTokens.brand,
                      foregroundColor: ZveltTokens.onBrand,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ZveltTokens.rXl),
                      ),
                    ),
                    child: const Text('Try Again'),
                  ),
                ),
                const SizedBox(height: ZveltTokens.s3),
                TextButton(
                  onPressed: () => setState(() {
                    _phase = _Phase.input;
                    _step = 0;
                  }),
                  style: TextButton.styleFrom(
                    foregroundColor: ZveltTokens.text2,
                  ),
                  child: const Text('Change preferences'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SMALL WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

// ─── Step indicator ───────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.currentStep, required this.totalSteps});
  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: ZveltTokens.s5, vertical: ZveltTokens.s2),
      child: Row(
        children: [
          for (int i = 0; i < totalSteps; i++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 3,
                decoration: BoxDecoration(
                  color: i <= currentStep
                      ? ZveltTokens.brand
                      : ZveltTokens.border,
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                ),
              ),
            ),
            if (i < totalSteps - 1) const SizedBox(width: ZveltTokens.s1),
          ],
        ],
      ),
    );
  }
}

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: ZType.clean.copyWith(
        fontSize: 13,
        letterSpacing: 0.4,
      ),
    );
  }
}

// ─── Chip row / multi-select ──────────────────────────────────────────────────

class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.options,
    required this.labels,
    required this.selected,
    required this.multiSelect,
    required this.onTap,
  });

  final List<String> options;
  final List<String> labels;
  final List<String> selected;
  final bool multiSelect;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: ZveltTokens.s2,
      runSpacing: ZveltTokens.s2,
      children: [
        for (int i = 0; i < options.length; i++)
          _SelectChip(
            label: labels[i],
            selected: selected.contains(options[i]),
            onTap: () => onTap(options[i]),
          ),
      ],
    );
  }
}

class _SelectChip extends StatelessWidget {
  const _SelectChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

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
          color: selected ? ZveltTokens.surface : ZveltTokens.bg2,
          borderRadius: BorderRadius.circular(ZveltTokens.rPill),
          border: Border.all(
            color: selected ? ZveltTokens.brand : ZveltTokens.border,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: ZType.bodyS.copyWith(
            color: ZveltTokens.text,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ─── Goal grid (2×2) ─────────────────────────────────────────────────────────

class _GoalOption {
  const _GoalOption(this.value, this.label, this.icon);
  final String value;
  final String label;
  final IconData icon;
}

class _GoalGrid extends StatelessWidget {
  const _GoalGrid({
    required this.selected,
    required this.options,
    required this.onSelect,
  });

  final String selected;
  final List<_GoalOption> options;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.8,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      children: [
        for (final opt in options)
          GestureDetector(
            onTap: () => onSelect(opt.value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                  horizontal: ZveltTokens.s4, vertical: 10),
              decoration: BoxDecoration(
                color: opt.value == selected
                    ? ZveltTokens.surface
                    : ZveltTokens.bg2,
                borderRadius: BorderRadius.circular(ZveltTokens.rLg),
                border: Border.all(
                  color: opt.value == selected
                      ? ZveltTokens.brand
                      : ZveltTokens.border,
                  width: opt.value == selected ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    opt.icon,
                    size: 16,
                    color: opt.value == selected
                        ? ZveltTokens.text
                        : ZveltTokens.text2,
                  ),
                  const SizedBox(width: ZveltTokens.s2),
                  Flexible(
                    child: Text(
                      opt.label,
                      style: ZType.bodyS.copyWith(
                        color: ZveltTokens.text,
                        fontWeight: opt.value == selected
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LOADING BODY
// ═══════════════════════════════════════════════════════════════════════════════

class _LoadingBody extends StatefulWidget {
  const _LoadingBody({required this.onCancel});
  final VoidCallback onCancel;

  @override
  State<_LoadingBody> createState() => _LoadingBodyState();
}

class _LoadingBodyState extends State<_LoadingBody>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  Timer? _subtitleTimer;
  int _subtitleIndex = 0;

  static const _subtitles = [
    'Analysing your goals',
    'Selecting exercises for your level',
    'Balancing your training load',
    'Planning your nutrition',
    'Finalising rest and recovery',
  ];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _subtitleTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) {
      if (mounted) {
        setState(() {
          _subtitleIndex = (_subtitleIndex + 1) % _subtitles.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _subtitleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FadeTransition(
          opacity: _pulseAnim,
          child: Icon(
            AppIcons.sparkles,
            size: 36,
            color: ZveltTokens.text2,
          ),
        ),
        const SizedBox(height: ZveltTokens.s6),
        Text(
          'Building your weekly plan\u2026',
          style: ZType.clean.copyWith(fontSize: 15),
        ),
        const SizedBox(height: ZveltTokens.s2),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: Text(
            _subtitles[_subtitleIndex],
            key: ValueKey<int>(_subtitleIndex),
            textAlign: TextAlign.center,
            style: ZType.bodyS,
          ),
        ),
        const SizedBox(height: ZveltTokens.s5),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 60),
          child: LinearProgressIndicator(
            color: ZveltTokens.brand,
            backgroundColor: ZveltTokens.border,
            minHeight: 2,
          ),
        ),
        const SizedBox(height: ZveltTokens.s10),
        TextButton(
          onPressed: widget.onCancel,
          style: TextButton.styleFrom(
            foregroundColor: ZveltTokens.text2,
          ),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RESULT WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

// ─── Week header card ─────────────────────────────────────────────────────────

class _WeekHeaderCard extends StatelessWidget {
  const _WeekHeaderCard({
    required this.weekSummary,
    required this.totalWorkoutDays,
    required this.avgDailyCalories,
  });

  final String weekSummary;
  final int totalWorkoutDays;
  final int avgDailyCalories;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (weekSummary.isNotEmpty) ...[
            Text(
              weekSummary,
              style: ZType.bodyS.copyWith(height: 1.5),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              if (totalWorkoutDays > 0)
                _StatChip('$totalWorkoutDays workout day${totalWorkoutDays == 1 ? '' : 's'}'),
              if (totalWorkoutDays > 0 && avgDailyCalories > 0)
                const SizedBox(width: ZveltTokens.s2),
              if (avgDailyCalories > 0)
                _StatChip('~$avgDailyCalories kcal/day'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: ZveltTokens.bg2,
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        border: Border.all(color: ZveltTokens.border),
      ),
      child: Text(
        label,
        style: ZType.bodyS.copyWith(
          color: ZveltTokens.text2,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ─── Week strip ───────────────────────────────────────────────────────────────

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.days});
  final List<Map<String, dynamic>> days;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().weekday; // 1=Mon, 7=Sun
    final activeIndex = (today - 1).clamp(0, days.length - 1);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < days.length; i++)
            _WeekDot(
              label: _dayAbbr(days[i]['dayName'] as String? ?? 'Day ${i + 1}'),
              isActive: i == activeIndex,
              isWorkout: (days[i]['type'] as String? ?? '') != 'rest',
            ),
        ],
      ),
    );
  }

  static String _dayAbbr(String name) {
    if (name.length >= 3) return name.substring(0, 3);
    return name;
  }
}

class _WeekDot extends StatelessWidget {
  const _WeekDot({
    required this.label,
    required this.isActive,
    required this.isWorkout,
  });

  final String label;
  final bool isActive;
  final bool isWorkout;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: ZveltTokens.s3),
      child: Column(
        children: [
          Text(
            label,
            style: ZType.bodyS.copyWith(
              color: isActive ? ZveltTokens.text : ZveltTokens.text2,
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isWorkout ? ZveltTokens.text : ZveltTokens.border,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 2),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 2,
            width: 24,
            color: isActive ? ZveltTokens.brand : Colors.transparent,
          ),
        ],
      ),
    );
  }
}

// ─── Day card ─────────────────────────────────────────────────────────────────

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.dayData,
    required this.dayIndex,
    required this.isExpanded,
    required this.onToggle,
  });

  final Map<String, dynamic> dayData;
  final int dayIndex;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final dayName = dayData['dayName'] as String? ?? 'Day ${dayIndex + 1}';
    final type = dayData['type'] as String? ?? 'rest';
    final isWorkout = type == 'workout';
    final isActive = type == 'active_recovery';
    final workoutTitle = dayData['workoutTitle'] as String? ?? '';
    final estimatedDuration = dayData['estimatedDuration'] as int? ?? 0;
    final exercises = (dayData['exercises'] as List<dynamic>?)
            ?.map((e) => e as Map<String, dynamic>)
            .toList() ??
        [];
    final nutrition = dayData['nutrition'] as Map<String, dynamic>?;
    final aiExplanation = dayData['aiExplanation'] as String? ?? '';

    final firstThreeExercises = exercises.take(3).map((e) {
      return e['name'] as String? ?? '';
    }).where((n) => n.isNotEmpty).join(' · ');

    final calories = nutrition?['calories'] as int? ?? 0;
    final protein = (nutrition?['protein'] as num?)?.toDouble() ?? 0;
    final carbs = (nutrition?['carbs'] as num?)?.toDouble() ?? 0;
    final fat = (nutrition?['fat'] as num?)?.toDouble() ?? 0;

    String typeBadgeText;
    Color typeBadgeColor;
    if (isWorkout) {
      typeBadgeText = 'Workout';
      typeBadgeColor = ZveltTokens.text;
    } else if (isActive) {
      typeBadgeText = 'Active Recovery';
      typeBadgeColor = ZveltTokens.warn;
    } else {
      typeBadgeText = 'Rest';
      typeBadgeColor = ZveltTokens.text2;
    }

    return Container(
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(ZveltTokens.rLg),
            child: Padding(
              padding: const EdgeInsets.all(ZveltTokens.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Day ${dayIndex + 1} · $dayName',
                          style: ZType.clean.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _TypeBadge(
                        label: typeBadgeText,
                        color: typeBadgeColor,
                      ),
                      const SizedBox(width: ZveltTokens.s2),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          AppIcons.angle_small_down,
                          size: 20,
                          color: ZveltTokens.text2,
                        ),
                      ),
                    ],
                  ),
                  // Workout subtitle
                  if (isWorkout && workoutTitle.isNotEmpty) ...[
                    const SizedBox(height: ZveltTokens.s1),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            workoutTitle,
                            style: ZType.bodyS,
                          ),
                        ),
                        if (estimatedDuration > 0)
                          Text(
                            '~$estimatedDuration min',
                            style: ZType.num_.copyWith(
                              color: ZveltTokens.text2,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ],
                  // Exercise preview
                  if (firstThreeExercises.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      firstThreeExercises,
                      style: ZType.bodyS.copyWith(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // Macro bar
                  if (calories > 0) ...[
                    const SizedBox(height: 10),
                    _MacroBar(
                      protein: protein,
                      carbs: carbs,
                      fat: fat,
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Expanded content
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: isExpanded
                ? _DayCardExpanded(
                    dayData: dayData,
                    aiExplanation: aiExplanation,
                    exercises: exercises,
                    nutrition: nutrition,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s2, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: ZType.bodyS.copyWith(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MacroBar extends StatelessWidget {
  const _MacroBar({
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  final double protein;
  final double carbs;
  final double fat;

  @override
  Widget build(BuildContext context) {
    final total = protein + carbs + fat;
    if (total <= 0) return const SizedBox.shrink();
    final pFrac = protein / total;
    final cFrac = carbs / total;
    final fFrac = fat / total;

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 4,
        child: Row(
          children: [
            Expanded(
              flex: (pFrac * 100).round(),
              child: const ColoredBox(color: ZveltTokens.success),
            ),
            Expanded(
              flex: (cFrac * 100).round(),
              child: const ColoredBox(color: ZveltTokens.warn),
            ),
            Expanded(
              flex: (fFrac * 100).round(),
              child: const ColoredBox(color: ZveltTokens.error),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Expanded day card content ────────────────────────────────────────────────

class _DayCardExpanded extends StatelessWidget {
  const _DayCardExpanded({
    required this.dayData,
    required this.aiExplanation,
    required this.exercises,
    required this.nutrition,
  });

  final Map<String, dynamic> dayData;
  final String aiExplanation;
  final List<Map<String, dynamic>> exercises;
  final Map<String, dynamic>? nutrition;

  @override
  Widget build(BuildContext context) {
    final meals = (nutrition?['meals'] as List<dynamic>?)
            ?.map((m) => m as Map<String, dynamic>)
            .toList() ??
        [];
    final calories = nutrition?['calories'] as int? ?? 0;
    final protein = (nutrition?['protein'] as num?)?.toInt() ?? 0;
    final carbs = (nutrition?['carbs'] as num?)?.toInt() ?? 0;
    final fat = (nutrition?['fat'] as num?)?.toInt() ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          ZveltTokens.s4, 0, ZveltTokens.s4, ZveltTokens.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, color: ZveltTokens.border),
          const SizedBox(height: ZveltTokens.s3),
          // AI explanation
          if (aiExplanation.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: ZveltTokens.brand,
                    width: 1,
                  ),
                ),
              ),
              child: Text(
                aiExplanation,
                style: ZType.bodyS.copyWith(
                  fontStyle: FontStyle.italic,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: ZveltTokens.s4),
          ],
          // Workout section
          if (exercises.isNotEmpty) ...[
            const _SectionDivider('Workout'),
            const SizedBox(height: 10),
            for (final ex in exercises) _ExerciseRow(exercise: ex),
            const SizedBox(height: ZveltTokens.s4),
          ],
          // Nutrition section
          if (nutrition != null && calories > 0) ...[
            const _SectionDivider('Nutrition'),
            const SizedBox(height: 10),
            _NutritionTotals(
              calories: calories,
              protein: protein,
              carbs: carbs,
              fat: fat,
            ),
            if (meals.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final meal in meals) _MealRow(meal: meal),
            ],
          ],
        ],
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: ZType.eyebrow.copyWith(color: ZveltTokens.text2),
        ),
        const SizedBox(width: ZveltTokens.s2),
        Expanded(
          child: Divider(height: 1, color: ZveltTokens.border),
        ),
      ],
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.exercise});
  final Map<String, dynamic> exercise;

  @override
  Widget build(BuildContext context) {
    final name = exercise['name'] as String? ?? '';
    final sets = exercise['sets'] as int? ?? 0;
    final reps = exercise['reps'] as String? ?? '';
    final rest = exercise['rest'] as String? ?? '';
    final notes = exercise['notes'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: ZveltTokens.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: ZType.clean.copyWith(fontSize: 13),
                ),
                Row(
                  children: [
                    Text(
                      'Sets: $sets × $reps',
                      style: ZType.num_.copyWith(
                        color: ZveltTokens.text2,
                        fontSize: 12,
                      ),
                    ),
                    if (rest.isNotEmpty) ...[
                      const SizedBox(width: ZveltTokens.s2),
                      _RestChip(rest),
                    ],
                  ],
                ),
                if (notes.isNotEmpty)
                  Text(
                    notes,
                    style: ZType.bodyS.copyWith(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RestChip extends StatelessWidget {
  const _RestChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: ZveltTokens.bg2,
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        border: Border.all(color: ZveltTokens.border),
      ),
      child: Text(
        label,
        style: ZType.monoS.copyWith(fontSize: 11),
      ),
    );
  }
}

class _NutritionTotals extends StatelessWidget {
  const _NutritionTotals({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  final int calories;
  final int protein;
  final int carbs;
  final int fat;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _MacroCell(value: '$calories', label: 'kcal')),
        Expanded(child: _MacroCell(value: '${protein}g', label: 'protein')),
        Expanded(child: _MacroCell(value: '${carbs}g', label: 'carbs')),
        Expanded(child: _MacroCell(value: '${fat}g', label: 'fat')),
      ],
    );
  }
}

class _MacroCell extends StatelessWidget {
  const _MacroCell({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: ZType.num_.copyWith(
            color: ZveltTokens.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: ZType.bodyS.copyWith(fontSize: 11),
        ),
      ],
    );
  }
}

class _MealRow extends StatelessWidget {
  const _MealRow({required this.meal});
  final Map<String, dynamic> meal;

  @override
  Widget build(BuildContext context) {
    final name = meal['name'] as String? ?? '';
    final time = meal['time'] as String? ?? '';
    final foods = (meal['foods'] as List<dynamic>?)
            ?.map((f) => f.toString())
            .toList() ??
        [];
    final mealProtein = (meal['protein'] as num?)?.toInt() ?? 0;
    final mealCarbs = (meal['carbs'] as num?)?.toInt() ?? 0;
    final mealFat = (meal['fat'] as num?)?.toInt() ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: ZType.clean.copyWith(fontSize: 13),
                ),
              ),
              if (time.isNotEmpty)
                Text(
                  time,
                  style: ZType.bodyS.copyWith(fontSize: 12),
                ),
            ],
          ),
          if (foods.isNotEmpty) ...[
            const SizedBox(height: 2),
            for (final food in foods)
              Padding(
                padding: const EdgeInsets.only(left: ZveltTokens.s2),
                child: Text(
                  '• $food',
                  style: ZType.bodyS.copyWith(fontSize: 12, height: 1.6),
                ),
              ),
          ],
          if (mealProtein > 0 || mealCarbs > 0 || mealFat > 0) ...[
            const SizedBox(height: ZveltTokens.s1),
            Wrap(
              spacing: 6,
              children: [
                if (mealProtein > 0) _RestChip('P ${mealProtein}g'),
                if (mealCarbs > 0) _RestChip('C ${mealCarbs}g'),
                if (mealFat > 0) _RestChip('F ${mealFat}g'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Result bottom bar ────────────────────────────────────────────────────────

class _ResultBottomBar extends StatelessWidget {
  const _ResultBottomBar({
    required this.onStart,
    required this.totalDays,
  });

  final VoidCallback onStart;
  final int totalDays;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          ZveltTokens.s5, ZveltTokens.s3, ZveltTokens.s5, ZveltTokens.s8),
      decoration: BoxDecoration(
        color: ZveltTokens.bg,
        border: Border(top: BorderSide(color: ZveltTokens.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onStart,
              style: FilledButton.styleFrom(
                backgroundColor: ZveltTokens.brand,
                foregroundColor: ZveltTokens.onBrand,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ZveltTokens.rXl),
                ),
                minimumSize: const Size(double.infinity, 52),
              ),
              child: const Text("Start Today's Workout"),
            ),
          ),
          if (totalDays > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Day 1 of $totalDays',
              style: ZType.bodyS.copyWith(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
