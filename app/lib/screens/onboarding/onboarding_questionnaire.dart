import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../models/onboarding_models.dart';
import '../../models/training_profile_models.dart';
import '../../services/onboarding_service.dart';
import '../../services/ai_chat_service.dart';
import '../../services/training_profile_service.dart';
import '../../services/nutrition_service.dart';
import '../../widgets/zvelt_primary_button.dart';

const String kOnboardingQuestionnaireCompletedKey = 'onboarding_questionnaire_completed';

// ─────────────────────────────────────────────────────────────────────────────
// EXTENDED STATE
// ─────────────────────────────────────────────────────────────────────────────

class ExtendedQuestionnaireState extends QuestionnaireState {
  ActivityLevel? activityLevel;
  /// API-aligned primary goal; also sets [goal] for legacy nutrition math.
  PrimaryTrainingGoal? primaryTrainingGoal;
  Set<SecondaryTrainingGoal> secondaryTrainingGoals = {};
  UserTrainingLevel? userTrainingLevel;
  int? trainingDaysPerWeek;
  int? sessionMinutes;
  final Set<String> equipmentTags = {};
  String injuriesLimitations = '';
  String gymExperience = '';
  TrainingSplitPreference? splitPreference;

  // Cardio assessment
  int? runMinutes;      // how many minutes can run without stopping
  int? restingHeartRate;
  // Strength assessment
  int? pushUps;         // max push-ups in one set
  int? bodyweightSquats; // max bodyweight squats
  int? pullUps;         // max pull-ups (0 = none)

  // ── Calculated results ──────────────────────────────────────────────────
  int get bmr {
    if (weightKg == 0 || heightCm == 0 || age == 0 || gender == null) return 0;
    // Mifflin-St Jeor
    if (gender == Gender.male) {
      return (10 * weightKg + 6.25 * heightCm - 5 * age + 5).round();
    } else {
      return (10 * weightKg + 6.25 * heightCm - 5 * age - 161).round();
    }  }

  int get tdee {
    if (activityLevel == null) return bmr;
    return (bmr * activityLevel!.multiplier).round();
  }

  int get targetCalories {
    if (goal == null) return tdee;
    switch (goal!) {
      case FitnessGoal.weightLoss:      return (tdee * 0.80).round(); // -20%
      case FitnessGoal.hypertrophy:     return (tdee * 1.10).round(); // +10%
      case FitnessGoal.generalFitness:  return tdee;
      case FitnessGoal.explosivePower:  return tdee;
      case FitnessGoal.strength:        return (tdee * 1.08).round(); // +8%
    }
  }

  int get proteinG {
    // 2.0g per kg for muscle gain/strength, 1.8g for others
    final multiplier = (goal == FitnessGoal.hypertrophy || goal == FitnessGoal.strength) ? 2.0 : 1.8;
    return (weightKg * multiplier).round();
  }

  int get fatG => ((targetCalories * 0.25) / 9).round();
  int get carbsG => ((targetCalories - (proteinG * 4) - (fatG * 9)) / 4).round();

  String get initialRank {
    final score = _strengthScore;
    if (score >= 80) return 'Gold';
    if (score >= 60) return 'Silver';
    if (score >= 40) return 'Bronze';
    return 'Recruit';
  }

  String get cardioLevel {
    final mins = runMinutes ?? 0;
    if (mins >= 30) return 'Advanced';
    if (mins >= 15) return 'Intermediate';
    if (mins >= 5)  return 'Beginner';
    return 'Starter';
  }

  int get _strengthScore {
    int score = 0;
    // Push-ups scoring
    final p = pushUps ?? 0;
    if (p >= 30) {
      score += 35;
    } else if (p >= 20) score += 25;
    else if (p >= 10) score += 15;
    else score += 5;
    // Squats scoring
    final s = bodyweightSquats ?? 0;
    if (s >= 40) {
      score += 35;
    } else if (s >= 25) score += 25;
    else if (s >= 15) score += 15;
    else score += 5;
    // Pull-ups scoring
    final pu = pullUps ?? 0;
    if (pu >= 10) {
      score += 30;
    } else if (pu >= 5) score += 20;
    else if (pu >= 1) score += 10;
    return score;
  }

  // Estimated starting weights
  double get estimatedDeadlift {
    final base = weightKg * 0.8;
    final modifier = _strengthScore / 100.0;
    return (base + base * modifier * 0.5).roundToDouble();
  }

  double get estimatedBench {
    final base = weightKg * 0.5;
    final modifier = _strengthScore / 100.0;
    return (base + base * modifier * 0.4).roundToDouble();
  }

  double get estimatedSquat {
    final base = weightKg * 0.7;
    final modifier = _strengthScore / 100.0;
    return (base + base * modifier * 0.4).roundToDouble();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN FLOW
// ─────────────────────────────────────────────────────────────────────────────

class OnboardingQuestionnaireFlow extends StatefulWidget {
  const OnboardingQuestionnaireFlow({super.key, required this.onComplete, this.completionKey});
  final VoidCallback onComplete;
  final String? completionKey;

  @override
  State<OnboardingQuestionnaireFlow> createState() => _OnboardingQuestionnaireFlowState();
}

class _OnboardingQuestionnaireFlowState extends State<OnboardingQuestionnaireFlow> {
  final _state = ExtendedQuestionnaireState();
  int _step = 0;
  Map<String, dynamic>? _aiInterpretation;
  bool _aiInterpretationLoading = false;
  // 0–9: units → … → strength | 10–16: training profile | 17: results
  static const int _totalSteps = 18;

  void _next() {
    if (_step == 16) {
      _prefetchOnboardingInterpretation();
    }
    if (_step < _totalSteps) {
      setState(() => _step++);
    } else {
      _complete();
    }
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  Future<void> _prefetchOnboardingInterpretation() async {
    if (_aiInterpretation != null || _aiInterpretationLoading) return;
    final inj = _state.injuriesLimitations.trim();
    final gym = _state.gymExperience.trim();
    final safeGym = gym.isNotEmpty ? (gym.length > 500 ? gym.substring(0, 500) : gym) : null;
    final safeInj = inj.isNotEmpty ? (inj.length > 4000 ? inj.substring(0, 4000) : inj) : null;
    if (safeGym == null && safeInj == null) return;

    setState(() => _aiInterpretationLoading = true);
    try {
      final interpreted = await AiChatService().interpretOnboarding(
        gymExperience: safeGym,
        injuriesLimitations: safeInj,
      );
      if (!mounted) return;
      final interpretation = interpreted['interpretation'];
      if (interpretation is Map) {
        setState(() => _aiInterpretation = Map<String, dynamic>.from(interpretation));
      }
    } catch (_) {
      // Non-fatal: onboarding can continue without AI interpretation.
    } finally {
      if (mounted) setState(() => _aiInterpretationLoading = false);
    }
  }

  Future<void> _complete() async {
    final service = OnboardingService();
    await service.save(_state);

    final primaryApi = _state.primaryTrainingGoal?.apiValue ??
        mapFitnessGoalToPrimaryGoal(_state.goal);
    final days = _state.trainingDaysPerWeek ??
        TrainingProfileService.suggestedDaysFromActivity(_state.activityLevel);
    final inj = _state.injuriesLimitations.trim();
    final gym = _state.gymExperience.trim();
    final safeGym = gym.isNotEmpty ? (gym.length > 500 ? gym.substring(0, 500) : gym) : null;
    final safeInj = inj.isNotEmpty ? (inj.length > 4000 ? inj.substring(0, 4000) : inj) : null;
    String? inferredPrimaryGoal;
    String? inferredTrainingLevel;
    final interpretation = _aiInterpretation;
    if (interpretation != null) {
      final p = interpretation['inferredPrimaryGoal'];
      final lv = interpretation['experienceLevelHint'];
      if (p is String && p.isNotEmpty) inferredPrimaryGoal = p;
      if (lv is String && lv.isNotEmpty) inferredTrainingLevel = lv;
    }

    await TrainingProfileService().patch({
      if (primaryApi != null) 'primaryGoal': primaryApi,
      if (primaryApi == null && inferredPrimaryGoal != null)
        'primaryGoal': inferredPrimaryGoal,
      'secondaryGoals':
          _state.secondaryTrainingGoals.map((e) => e.apiValue).toList(),
      if (_state.userTrainingLevel != null)
        'trainingLevel': _state.userTrainingLevel!.apiValue,
      if (_state.userTrainingLevel == null && inferredTrainingLevel != null)
        'trainingLevel': inferredTrainingLevel,
      if (safeGym != null) 'gymExperience': safeGym,
      if (days != null) 'daysPerWeek': days,
      if (_state.sessionMinutes != null) 'sessionMinutes': _state.sessionMinutes,
      'equipment': _state.equipmentTags.toList(),
      if (safeInj != null) 'injuriesLimitations': safeInj,
      if (_state.splitPreference != null)
        'splitPreference': _state.splitPreference!.apiValue,
      'onboardingCompleted': true,
    });

    await service.patchDailyNutritionTargets(
      dailyCalories: _state.targetCalories,
      dailyProtein: _state.proteinG,
      dailyCarbs: _state.carbsG,
      dailyFat: _state.fatG,
    );
    try {
      await NutritionService.instance.generateWeeklyPlan(force: true);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(widget.completionKey ?? kOnboardingQuestionnaireCompletedKey, true);
    if (!mounted) return;
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            if (_step < _totalSteps)
              _ProgressHeader(step: _step, total: _totalSteps, onBack: _step > 0 ? _back : null),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _buildStep(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:  return _StepUnits(key: const ValueKey(0), state: _state, onNext: _next);
      case 1:  return _StepMuscleGroups(key: const ValueKey(1), state: _state, onNext: _next);
      case 2:  return _StepGoal(key: const ValueKey(2), state: _state, onNext: _next);
      case 3:  return _StepGender(key: const ValueKey(3), state: _state, onNext: _next);
      case 4:  return _StepHeight(key: const ValueKey(4), state: _state, onNext: _next);
      case 5:  return _StepWeight(key: const ValueKey(5), state: _state, onNext: _next);
      case 6:  return _StepAge(key: const ValueKey(6), state: _state, onNext: _next);
      case 7:  return _StepActivityLevel(key: const ValueKey(7), state: _state, onNext: _next);
      case 8:  return _StepCardioAssessment(key: const ValueKey(8), state: _state, onNext: _next);
      case 9:  return _StepStrengthAssessment(key: const ValueKey(9), state: _state, onNext: _next);
      case 10: return _StepSecondaryGoals(key: const ValueKey(10), state: _state, onNext: _next);
      case 11: return _StepTrainingLevel(key: const ValueKey(11), state: _state, onNext: _next);
      case 12: return _StepTrainingDays(key: const ValueKey(12), state: _state, onNext: _next);
      case 13: return _StepSessionLength(key: const ValueKey(13), state: _state, onNext: _next);
      case 14: return _StepEquipment(key: const ValueKey(14), state: _state, onNext: _next);
      case 15: return _StepInjuriesExperience(key: const ValueKey(15), state: _state, onNext: _next);
      case 16: return _StepSplitPreference(key: const ValueKey(16), state: _state, onNext: _next);
      case 17: return _StepResults(
        key: const ValueKey(17),
        state: _state,
        interpretation: _aiInterpretation,
        interpretationLoading: _aiInterpretationLoading,
        onComplete: _complete,
      );
      default: return const SizedBox.shrink();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED UI
// ─────────────────────────────────────────────────────────────────────────────

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.step, required this.total, this.onBack});
  final int step;
  final int total;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          if (onBack != null)
            GestureDetector(
              onTap: onBack,
              child: Icon(Icons.arrow_back_ios, color: AppTheme.textSecondary, size: 20),
            )
          else
            const SizedBox(width: 20),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: (step + 1) / (total + 1),
                backgroundColor: AppTheme.border,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accentAmber),
                minHeight: 4,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('${step + 1}/$total',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _StepShell extends StatelessWidget {
  const _StepShell({
    required this.title,
    required this.subtitle,
    required this.content,
    required this.ctaLabel,
    required this.onCta,
    this.ctaEnabled = true,
  });
  final String title;
  final String subtitle;
  final Widget content;
  final String ctaLabel;
  final VoidCallback onCta;
  final bool ctaEnabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(title,
              style: TextStyle(
                  color: AppTheme.textPrimary, fontSize: 26, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(subtitle,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
        ),
        const SizedBox(height: 28),
        Expanded(child: content),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: FilledButton(
            onPressed: ctaEnabled ? onCta : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              backgroundColor: ctaEnabled ? AppTheme.accentAmber : AppTheme.border,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
            ),
            child: Text(ctaLabel,
                style: TextStyle(
                    color: AppTheme.bgPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

class _SelectCard extends StatelessWidget {
  const _SelectCard({
    required this.label,
    this.subtitle,
    this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accentAmberGlow : AppTheme.bgElevated,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(
            color: selected ? AppTheme.accentAmber : AppTheme.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: selected ? AppTheme.accentAmber : AppTheme.textSecondary, size: 22),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      )),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: AppTheme.accentAmber, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 0 — UNITS
// ─────────────────────────────────────────────────────────────────────────────

class _StepUnits extends StatefulWidget {
  const _StepUnits({super.key, required this.state, required this.onNext});
  final ExtendedQuestionnaireState state;
  final VoidCallback onNext;

  @override
  State<_StepUnits> createState() => _StepUnitsState();
}

class _StepUnitsState extends State<_StepUnits> {
  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'Units',
      subtitle: 'Which measurement system do you prefer?',
      ctaLabel: 'Continue',
      onCta: widget.onNext,
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            _SelectCard(
              label: 'Metric',
              subtitle: 'kg, cm',
              icon: Icons.straighten,
              selected: widget.state.units == UnitSystem.metric,
              onTap: () => setState(() => widget.state.units = UnitSystem.metric),
            ),
            const SizedBox(height: 12),
            _SelectCard(
              label: 'Imperial',
              subtitle: 'lbs, ft/in',
              icon: Icons.straighten,
              selected: widget.state.units == UnitSystem.imperial,
              onTap: () => setState(() => widget.state.units = UnitSystem.imperial),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 1 — MUSCLE GROUPS
// ─────────────────────────────────────────────────────────────────────────────

class _StepMuscleGroups extends StatefulWidget {
  const _StepMuscleGroups({super.key, required this.state, required this.onNext});
  final ExtendedQuestionnaireState state;
  final VoidCallback onNext;

  @override
  State<_StepMuscleGroups> createState() => _StepMuscleGroupsState();
}

class _StepMuscleGroupsState extends State<_StepMuscleGroups> {
  @override
  Widget build(BuildContext context) {
    final hasSelection = widget.state.muscleGroups.isNotEmpty;
    return _StepShell(
      title: 'Focus areas',
      subtitle: 'Which muscle groups are your priority? Pick one or more.',
      ctaLabel: 'Continue',
      ctaEnabled: hasSelection,
      onCta: widget.onNext,
      content: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: MuscleGroup.values.map((g) {
          final selected = widget.state.muscleGroups.contains(g);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SelectCard(
              label: g.label,
              icon: g.icon,
              selected: selected,
              onTap: () => setState(() {
                if (g == MuscleGroup.fullBody) {
                  widget.state.muscleGroups = selected ? {} : {MuscleGroup.fullBody};
                } else {
                  widget.state.muscleGroups.remove(MuscleGroup.fullBody);
                  if (selected) {
                    widget.state.muscleGroups.remove(g);
                  } else {
                    widget.state.muscleGroups.add(g);
                  }
                }
              }),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 2 — GOAL
// ─────────────────────────────────────────────────────────────────────────────

class _StepGoal extends StatefulWidget {
  const _StepGoal({super.key, required this.state, required this.onNext});
  final ExtendedQuestionnaireState state;
  final VoidCallback onNext;

  @override
  State<_StepGoal> createState() => _StepGoalState();
}

class _StepGoalState extends State<_StepGoal> {
  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'Main goal',
      subtitle: 'Pick one primary adaptation — this drives your future program style.',
      ctaLabel: 'Continue',
      ctaEnabled: widget.state.primaryTrainingGoal != null,
      onCta: widget.onNext,
      content: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: PrimaryTrainingGoal.values.map((g) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SelectCard(
              label: g.label,
              subtitle: g.subtitle,
              selected: widget.state.primaryTrainingGoal == g,
              onTap: () => setState(() {
                widget.state.primaryTrainingGoal = g;
                widget.state.goal = legacyFitnessGoalFromPrimary(g);
              }),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 3 — GENDER (Male / Female only)
// ─────────────────────────────────────────────────────────────────────────────

class _StepGender extends StatefulWidget {
  const _StepGender({super.key, required this.state, required this.onNext});
  final ExtendedQuestionnaireState state;
  final VoidCallback onNext;

  @override
  State<_StepGender> createState() => _StepGenderState();
}

class _StepGenderState extends State<_StepGender> {
  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'About you',
      subtitle: 'Used to personalise your calorie and rank benchmarks.',
      ctaLabel: 'Continue',
      ctaEnabled: widget.state.gender != null,
      onCta: widget.onNext,
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            Expanded(
              child: _GenderCard(
                label: 'Male',
                icon: Icons.male,
                selected: widget.state.gender == Gender.male,
                onTap: () => setState(() => widget.state.gender = Gender.male),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _GenderCard(
                label: 'Female',
                icon: Icons.female,
                selected: widget.state.gender == Gender.female,
                onTap: () => setState(() => widget.state.gender = Gender.female),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenderCard extends StatelessWidget {
  const _GenderCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accentAmberGlow : AppTheme.bgElevated,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(
            color: selected ? AppTheme.accentAmber : AppTheme.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 52,
                color: selected ? AppTheme.accentAmber : AppTheme.textSecondary),
            const SizedBox(height: 12),
            Text(label,
                style: TextStyle(
                  color: selected ? AppTheme.accentAmber : AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                )),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 4 — HEIGHT
// ─────────────────────────────────────────────────────────────────────────────

class _StepHeight extends StatefulWidget {
  const _StepHeight({super.key, required this.state, required this.onNext});
  final ExtendedQuestionnaireState state;
  final VoidCallback onNext;

  @override
  State<_StepHeight> createState() => _StepHeightState();
}

class _StepHeightState extends State<_StepHeight> {
  bool get _isMetric => widget.state.units == UnitSystem.metric;

  @override
  Widget build(BuildContext context) {
    final value = _isMetric ? widget.state.heightCm : widget.state.heightIn;
    final unit = _isMetric ? 'cm' : 'in';
    final min = _isMetric ? 140.0 : 55.0;
    final max = _isMetric ? 220.0 : 87.0;

    return _StepShell(
      title: 'Your height',
      subtitle: 'Used to calculate your BMR and strength ratios.',
      ctaLabel: 'Continue',
      onCta: widget.onNext,
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 32),
            Text('${value.round()} $unit',
                style: const TextStyle(
                    color: AppTheme.accentAmber, fontSize: 52, fontWeight: FontWeight.w700)),
            const SizedBox(height: 40),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppTheme.accentAmber,
                inactiveTrackColor: AppTheme.border,
                thumbColor: AppTheme.accentAmber,
                overlayColor: AppTheme.accentAmberGlow,
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: (max - min).round(),
                onChanged: (v) => setState(() {
                  if (_isMetric) {
                    widget.state.heightCm = v;
                  } else {
                    widget.state.heightIn = v;
                  }
                }),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${min.round()} $unit',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                Text('${max.round()} $unit',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 5 — WEIGHT
// ─────────────────────────────────────────────────────────────────────────────

class _StepWeight extends StatefulWidget {
  const _StepWeight({super.key, required this.state, required this.onNext});
  final ExtendedQuestionnaireState state;
  final VoidCallback onNext;

  @override
  State<_StepWeight> createState() => _StepWeightState();
}

class _StepWeightState extends State<_StepWeight> {
  bool get _isMetric => widget.state.units == UnitSystem.metric;

  @override
  Widget build(BuildContext context) {
    final value = _isMetric ? widget.state.weightKg : widget.state.weightLbs;
    final unit = _isMetric ? 'kg' : 'lbs';
    final min = _isMetric ? 30.0 : 66.0;
    final max = _isMetric ? 250.0 : 551.0;

    return _StepShell(
      title: 'Your weight',
      subtitle: 'Needed to calculate your strength rankings.',
      ctaLabel: 'Continue',
      onCta: widget.onNext,
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 32),
            Text('${value.round()} $unit',
                style: const TextStyle(
                    color: AppTheme.accentAmber, fontSize: 52, fontWeight: FontWeight.w700)),
            const SizedBox(height: 40),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppTheme.accentAmber,
                inactiveTrackColor: AppTheme.border,
                thumbColor: AppTheme.accentAmber,
                overlayColor: AppTheme.accentAmberGlow,
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: (max - min).round(),
                onChanged: (v) => setState(() {
                  if (_isMetric) {
                    widget.state.weightKg = v;
                  } else {
                    widget.state.weightLbs = v;
                  }
                }),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${min.round()} $unit',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                Text('${max.round()} $unit',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 6 — AGE
// ─────────────────────────────────────────────────────────────────────────────

class _StepAge extends StatefulWidget {
  const _StepAge({super.key, required this.state, required this.onNext});
  final ExtendedQuestionnaireState state;
  final VoidCallback onNext;

  @override
  State<_StepAge> createState() => _StepAgeState();
}

class _StepAgeState extends State<_StepAge> {
  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'Your age',
      subtitle: 'Helps personalise your calorie needs.',
      ctaLabel: 'Continue',
      onCta: widget.onNext,
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 32),
            Text('${widget.state.age}',
                style: const TextStyle(
                    color: AppTheme.accentAmber, fontSize: 72, fontWeight: FontWeight.w700)),
            Text('years old',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
            const SizedBox(height: 40),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppTheme.accentAmber,
                inactiveTrackColor: AppTheme.border,
                thumbColor: AppTheme.accentAmber,
                overlayColor: AppTheme.accentAmberGlow,
              ),
              child: Slider(
                value: widget.state.age.toDouble(),
                min: 13,
                max: 90,
                divisions: 77,
                onChanged: (v) => setState(() => widget.state.age = v.round()),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('13', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                Text('90', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 7 — ACTIVITY LEVEL (NEW)
// ─────────────────────────────────────────────────────────────────────────────

class _StepActivityLevel extends StatefulWidget {
  const _StepActivityLevel({super.key, required this.state, required this.onNext});
  final ExtendedQuestionnaireState state;
  final VoidCallback onNext;

  @override
  State<_StepActivityLevel> createState() => _StepActivityLevelState();
}

class _StepActivityLevelState extends State<_StepActivityLevel> {
  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'Activity level',
      subtitle: 'How active are you on a typical week?',
      ctaLabel: 'Continue',
      ctaEnabled: widget.state.activityLevel != null,
      onCta: widget.onNext,
      content: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: ActivityLevel.values.map((a) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SelectCard(
              label: a.label,
              subtitle: a.subtitle,
              selected: widget.state.activityLevel == a,
              onTap: () => setState(() => widget.state.activityLevel = a),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 8 — CARDIO ASSESSMENT (NEW)
// ─────────────────────────────────────────────────────────────────────────────

class _StepCardioAssessment extends StatefulWidget {
  const _StepCardioAssessment({super.key, required this.state, required this.onNext});
  final ExtendedQuestionnaireState state;
  final VoidCallback onNext;

  @override
  State<_StepCardioAssessment> createState() => _StepCardioAssessmentState();
}

class _StepCardioAssessmentState extends State<_StepCardioAssessment> {
  @override
  void initState() {
    super.initState();
    widget.state.runMinutes ??= 5;
    widget.state.restingHeartRate ??= 70;
  }

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'Cardio assessment',
      subtitle: 'Honest answers give you a better starting rank.',
      ctaLabel: 'Continue',
      onCta: widget.onNext,
      content: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          // Run time
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.bgElevated,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How long can you run without stopping?',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('At a comfortable pace',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    widget.state.runMinutes! < 60
                        ? '${widget.state.runMinutes} min'
                        : '${widget.state.runMinutes! ~/ 60}h ${widget.state.runMinutes! % 60}min',
                    style: const TextStyle(
                        color: AppTheme.accentAmber, fontSize: 36, fontWeight: FontWeight.w700),
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppTheme.accentAmber,
                    inactiveTrackColor: AppTheme.border,
                    thumbColor: AppTheme.accentAmber,
                    overlayColor: AppTheme.accentAmberGlow,
                  ),
                  child: Slider(
                    value: widget.state.runMinutes!.toDouble(),
                    min: 1,
                    max: 120,
                    divisions: 119,
                    onChanged: (v) => setState(() => widget.state.runMinutes = v.round()),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('1 min', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    Text('2 hours', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Resting heart rate
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.bgElevated,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Resting heart rate',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Beats per minute when calm (check wearable or pulse)',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                const SizedBox(height: 16),
                Center(
                  child: Text('${widget.state.restingHeartRate} bpm',
                      style: const TextStyle(
                          color: AppTheme.accentAmber, fontSize: 36, fontWeight: FontWeight.w700)),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppTheme.accentAmber,
                    inactiveTrackColor: AppTheme.border,
                    thumbColor: AppTheme.accentAmber,
                    overlayColor: AppTheme.accentAmberGlow,
                  ),
                  child: Slider(
                    value: widget.state.restingHeartRate!.toDouble(),
                    min: 40,
                    max: 110,
                    divisions: 70,
                    onChanged: (v) => setState(() => widget.state.restingHeartRate = v.round()),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('40 bpm', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    Text('110 bpm', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  ],
                ),
                // HR guide
                const SizedBox(height: 8),
                _HrGuide(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HrGuide extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = [
      ('< 60', 'Athletic'),
      ('60–70', 'Good'),
      ('71–85', 'Average'),
      ('> 85', 'High'),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: items.map((e) => Column(
        children: [
          Text(e.$1, style: const TextStyle(color: AppTheme.accentAmber, fontSize: 11, fontWeight: FontWeight.w600)),
          Text(e.$2, style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        ],
      )).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 9 — STRENGTH ASSESSMENT (NEW)
// ─────────────────────────────────────────────────────────────────────────────

class _StepStrengthAssessment extends StatefulWidget {
  const _StepStrengthAssessment({super.key, required this.state, required this.onNext});
  final ExtendedQuestionnaireState state;
  final VoidCallback onNext;

  @override
  State<_StepStrengthAssessment> createState() => _StepStrengthAssessmentState();
}

class _StepStrengthAssessmentState extends State<_StepStrengthAssessment> {
  @override
  void initState() {
    super.initState();
    widget.state.pushUps ??= 10;
    widget.state.bodyweightSquats ??= 15;
    widget.state.pullUps ??= 0;
  }

  Widget _assessmentCard({
    required String title,
    required String subtitle,
    required int value,
    required int max,
    required ValueChanged<int> onChanged,
    required String unit,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgElevated,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 16),
          Center(
            child: Text('$value $unit',
                style: const TextStyle(
                    color: AppTheme.accentAmber, fontSize: 36, fontWeight: FontWeight.w700)),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppTheme.accentAmber,
              inactiveTrackColor: AppTheme.border,
              thumbColor: AppTheme.accentAmber,
              overlayColor: AppTheme.accentAmberGlow,
            ),
            child: Slider(
              value: value.toDouble(),
              min: 0,
              max: max.toDouble(),
              divisions: max,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              Text('$max+', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'Strength assessment',
      subtitle: 'Max reps in one set — no rest. Be honest!',
      ctaLabel: 'Calculate my profile',
      onCta: widget.onNext,
      content: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          _assessmentCard(
            title: 'Push-ups',
            subtitle: 'Full range, chest to floor',
            value: widget.state.pushUps!,
            max: 50,
            unit: 'reps',
            onChanged: (v) => setState(() => widget.state.pushUps = v),
          ),
          const SizedBox(height: 12),
          _assessmentCard(
            title: 'Bodyweight squats',
            subtitle: 'Below parallel, no weight',
            value: widget.state.bodyweightSquats!,
            max: 60,
            unit: 'reps',
            onChanged: (v) => setState(() => widget.state.bodyweightSquats = v),
          ),
          const SizedBox(height: 12),
          _assessmentCard(
            title: 'Pull-ups',
            subtitle: 'Full hang to chin above bar (0 = none)',
            value: widget.state.pullUps!,
            max: 20,
            unit: 'reps',
            onChanged: (v) => setState(() => widget.state.pullUps = v),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEPS 10–16 — TRAINING PROFILE (API → UserTrainingProfile)
// ─────────────────────────────────────────────────────────────────────────────

class _StepSecondaryGoals extends StatefulWidget {
  const _StepSecondaryGoals({super.key, required this.state, required this.onNext});
  final ExtendedQuestionnaireState state;
  final VoidCallback onNext;

  @override
  State<_StepSecondaryGoals> createState() => _StepSecondaryGoalsState();
}

class _StepSecondaryGoalsState extends State<_StepSecondaryGoals> {
  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'Secondary focus',
      subtitle: 'Optional — we keep volume sensible for these on the side.',
      ctaLabel: 'Continue',
      onCta: widget.onNext,
      content: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: SecondaryTrainingGoal.values.map((g) {
          final sel = widget.state.secondaryTrainingGoals.contains(g);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SelectCard(
              label: g.label,
              selected: sel,
              onTap: () => setState(() {
                if (sel) {
                  widget.state.secondaryTrainingGoals.remove(g);
                } else {
                  widget.state.secondaryTrainingGoals.add(g);
                }
              }),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StepTrainingLevel extends StatefulWidget {
  const _StepTrainingLevel({super.key, required this.state, required this.onNext});
  final ExtendedQuestionnaireState state;
  final VoidCallback onNext;

  @override
  State<_StepTrainingLevel> createState() => _StepTrainingLevelState();
}

class _StepTrainingLevelState extends State<_StepTrainingLevel> {
  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'Training level',
      subtitle: 'Honest level helps us keep volume and complexity right.',
      ctaLabel: 'Continue',
      ctaEnabled: widget.state.userTrainingLevel != null,
      onCta: widget.onNext,
      content: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: UserTrainingLevel.values.map((lv) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SelectCard(
              label: lv.label,
              subtitle: lv.subtitle,
              selected: widget.state.userTrainingLevel == lv,
              onTap: () => setState(() => widget.state.userTrainingLevel = lv),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StepTrainingDays extends StatefulWidget {
  const _StepTrainingDays({super.key, required this.state, required this.onNext});
  final ExtendedQuestionnaireState state;
  final VoidCallback onNext;

  @override
  State<_StepTrainingDays> createState() => _StepTrainingDaysState();
}

class _StepTrainingDaysState extends State<_StepTrainingDays> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.state.trainingDaysPerWeek == null &&
          widget.state.activityLevel != null) {
        setState(() {
          widget.state.trainingDaysPerWeek =
              TrainingProfileService.suggestedDaysFromActivity(
                  widget.state.activityLevel);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'Days per week',
      subtitle: 'How many days can you train? Pre-filled from your activity — adjust if needed.',
      ctaLabel: 'Continue',
      ctaEnabled: widget.state.trainingDaysPerWeek != null,
      onCta: widget.onNext,
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: List.generate(7, (i) {
                final d = i + 1;
                final sel = widget.state.trainingDaysPerWeek == d;
                return GestureDetector(
                  onTap: () => setState(() => widget.state.trainingDaysPerWeek = d),
                  child: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: sel ? AppTheme.accentAmberGlow : AppTheme.bgElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: sel ? AppTheme.accentAmber : AppTheme.border,
                        width: sel ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      '$d',
                      style: TextStyle(
                        color: sel ? AppTheme.accentAmber : AppTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepSessionLength extends StatefulWidget {
  const _StepSessionLength({super.key, required this.state, required this.onNext});
  final ExtendedQuestionnaireState state;
  final VoidCallback onNext;

  @override
  State<_StepSessionLength> createState() => _StepSessionLengthState();
}

class _StepSessionLengthState extends State<_StepSessionLength> {
  static const _options = [30, 45, 60, 75, 90, 120];

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'Session length',
      subtitle: 'Typical time per workout (warm-up included).',
      ctaLabel: 'Continue',
      ctaEnabled: widget.state.sessionMinutes != null,
      onCta: widget.onNext,
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            ..._options.map((m) {
              final sel = widget.state.sessionMinutes == m;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SelectCard(
                  label: '$m minutes',
                  selected: sel,
                  onTap: () => setState(() => widget.state.sessionMinutes = m),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _StepEquipment extends StatefulWidget {
  const _StepEquipment({super.key, required this.state, required this.onNext});
  final ExtendedQuestionnaireState state;
  final VoidCallback onNext;

  @override
  State<_StepEquipment> createState() => _StepEquipmentState();
}

class _StepEquipmentState extends State<_StepEquipment> {
  @override
  Widget build(BuildContext context) {
    final has = widget.state.equipmentTags.isNotEmpty;
    return _StepShell(
      title: 'Equipment',
      subtitle: 'What do you have access to? Pick all that apply.',
      ctaLabel: 'Continue',
      ctaEnabled: has,
      onCta: widget.onNext,
      content: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: kTrainingEquipmentPresets.map((p) {
          final sel = widget.state.equipmentTags.contains(p.id);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SelectCard(
              label: p.label,
              selected: sel,
              onTap: () => setState(() {
                if (sel) {
                  widget.state.equipmentTags.remove(p.id);
                } else {
                  widget.state.equipmentTags.add(p.id);
                }
              }),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StepInjuriesExperience extends StatefulWidget {
  const _StepInjuriesExperience({super.key, required this.state, required this.onNext});
  final ExtendedQuestionnaireState state;
  final VoidCallback onNext;

  @override
  State<_StepInjuriesExperience> createState() => _StepInjuriesExperienceState();
}

class _StepInjuriesExperienceState extends State<_StepInjuriesExperience> {
  late final TextEditingController _injCtrl;
  late final TextEditingController _expCtrl;

  @override
  void initState() {
    super.initState();
    _injCtrl = TextEditingController(text: widget.state.injuriesLimitations);
    _expCtrl = TextEditingController(text: widget.state.gymExperience);
  }

  @override
  void dispose() {
    _injCtrl.dispose();
    _expCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      borderSide: BorderSide(color: AppTheme.border),
    );
    return _StepShell(
      title: 'Experience & limits',
      subtitle: 'Injuries or pain we should programme around, plus your gym background.',
      ctaLabel: 'Continue',
      onCta: () {
        widget.state.injuriesLimitations = _injCtrl.text;
        widget.state.gymExperience = _expCtrl.text;
        widget.onNext();
      },
      content: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          Text(
            'Injuries / limitations',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _injCtrl,
            maxLines: 4,
            maxLength: 2000,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'e.g. sore left shoulder overhead — optional',
              hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.7)),
              filled: true,
              fillColor: AppTheme.bgElevated,
              border: border,
              enabledBorder: border,
              focusedBorder: border.copyWith(
                borderSide: const BorderSide(color: AppTheme.accentAmber),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          Text(
            'Gym / sport experience',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _expCtrl,
            maxLines: 3,
            maxLength: 500,
            style: TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'e.g. 2 years powerlifting, new to calisthenics',
              hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.7)),
              filled: true,
              fillColor: AppTheme.bgElevated,
              border: border,
              enabledBorder: border,
              focusedBorder: border.copyWith(
                borderSide: const BorderSide(color: AppTheme.accentAmber),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }
}

class _StepSplitPreference extends StatefulWidget {
  const _StepSplitPreference({super.key, required this.state, required this.onNext});
  final ExtendedQuestionnaireState state;
  final VoidCallback onNext;

  @override
  State<_StepSplitPreference> createState() => _StepSplitPreferenceState();
}

class _StepSplitPreferenceState extends State<_StepSplitPreference> {
  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: 'Program style',
      subtitle: 'How do you like to split the week?',
      ctaLabel: 'Continue',
      ctaEnabled: widget.state.splitPreference != null,
      onCta: widget.onNext,
      content: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: TrainingSplitPreference.values.map((sp) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SelectCard(
              label: sp.label,
              subtitle: sp == TrainingSplitPreference.auto
                  ? 'We match split to your days & goal'
                  : null,
              selected: widget.state.splitPreference == sp,
              onTap: () => setState(() => widget.state.splitPreference = sp),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEP 17 — RESULTS
// ─────────────────────────────────────────────────────────────────────────────

class _StepResults extends StatefulWidget {
  const _StepResults({
    super.key,
    required this.state,
    required this.onComplete,
    required this.interpretation,
    required this.interpretationLoading,
  });
  final ExtendedQuestionnaireState state;
  final Future<void> Function() onComplete;
  final Map<String, dynamic>? interpretation;
  final bool interpretationLoading;

  @override
  State<_StepResults> createState() => _StepResultsState();
}

class _StepResultsState extends State<_StepResults> {
  bool _loading = false;

  Color _rankColor(String rank) {
    switch (rank) {
      case 'Gold':    return AppTheme.accentAmber;
      case 'Silver':  return const Color(0xFFC0C0C0);
      case 'Bronze':  return const Color(0xFFCD7F32);
      default:        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final rankColor = _rankColor(s.initialRank);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          const Icon(Icons.emoji_events, color: AppTheme.accentAmber, size: 56),
          const SizedBox(height: 12),
          Text('Your profile is ready!',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 26, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text('Based on your assessment — ${s.initialRank} rank, ${s.cardioLevel} cardio',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Rank badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: rankColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: rankColor.withValues(alpha: 0.5)),
                    ),
                    child: Text('Starting rank: ${s.initialRank}',
                        style: TextStyle(
                            color: rankColor, fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 20),

                  if (widget.interpretationLoading)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(color: AppTheme.accentAmber),
                    ),
                  if (widget.interpretation != null)
                    _ResultSection(
                      title: 'AI interpreted focus',
                      icon: Icons.auto_awesome,
                      children: [
                        if ((widget.interpretation!['sportFocus'] as String?) != null)
                          _ResultRow(
                            'Sport focus',
                            (widget.interpretation!['sportFocus'] as String).replaceAll('_', ' '),
                            AppTheme.accentAmber,
                          ),
                        if ((widget.interpretation!['inferredPrimaryGoal'] as String?) != null)
                          _ResultRow(
                            'Inferred goal',
                            (widget.interpretation!['inferredPrimaryGoal'] as String).replaceAll('_', ' '),
                            AppTheme.accentAmber,
                          ),
                      ],
                    ),
                  if (widget.interpretation != null) const SizedBox(height: 12),

                  // Nutrition targets
                  _ResultSection(
                    title: 'Daily nutrition targets',
                    icon: Icons.restaurant,
                    children: [
                      _ResultRow('Calories', '${s.targetCalories} kcal', AppTheme.accentAmber),
                      _ResultRow('Protein', '${s.proteinG}g', const Color(0xFF8AB4F8)),
                      _ResultRow('Carbs', '${s.carbsG}g', const Color(0xFF3DD68C)),
                      _ResultRow('Fat', '${s.fatG}g', const Color(0xFFFF6B35)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Starting weights
                  _ResultSection(
                    title: 'Estimated starting weights',
                    icon: Icons.fitness_center,
                    children: [
                      _ResultRow('Deadlift', '${s.estimatedDeadlift.round()} kg', AppTheme.accentAmber),
                      _ResultRow('Squat', '${s.estimatedSquat.round()} kg', AppTheme.accentAmber),
                      _ResultRow('Bench press', '${s.estimatedBench.round()} kg', AppTheme.accentAmber),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Cardio
                  _ResultSection(
                    title: 'Cardio level',
                    icon: Icons.directions_run,
                    children: [
                      _ResultRow('Level', s.cardioLevel, const Color(0xFF3DD68C)),
                      _ResultRow('Run endurance', '${s.runMinutes} min', AppTheme.textSecondary),
                      _ResultRow('Resting HR', '${s.restingHeartRate} bpm', AppTheme.textSecondary),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.accentAmberGlow,
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                      border: Border.all(color: AppTheme.accentAmber.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: AppTheme.accentAmber, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'These are estimates. They update automatically as you log workouts.',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          ZveltPrimaryButton(
            label: _loading ? 'Forging...' : "Let's forge it!",
            enabled: !_loading,
            onTap: () async {
              setState(() => _loading = true);
              await widget.onComplete();
            },
          ),
        ],
      ),
    );
  }
}

class _ResultSection extends StatelessWidget {
  const _ResultSection({required this.title, required this.icon, required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgElevated,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.accentAmber, size: 16),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11,
                      fontWeight: FontWeight.w600, letterSpacing: 0.05)),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow(this.label, this.value, this.valueColor);
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const Spacer(),
          Text(value,
              style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
