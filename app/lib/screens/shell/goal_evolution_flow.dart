import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../../services/ai_chat_service.dart';
import '../../services/training_profile_service.dart';
import '../../theme/zvelt_tokens.dart';

/// Full-screen state machine for the Goal Evolution feature.
///
/// Stages:
///   1. editing       — text editor pre-filled with current goal
///   2. regenerating  — PATCH new goal + POST /v1/ai/weekly-plan with
///                      previousGoalText so the AI returns a
///                      goalChangeRationale describing what shifted
///   3. result        — show old → new goal + AI rationale + Done
///   4. failed        — surfaces error with retry
///
/// We deliberately skip the GoalInterpretOverlay reveal between editing and
/// regenerating to keep this flow short (~10s end-to-end). The "AI got me"
/// moment already happened in onboarding; this one is about *showing the
/// shift*, not re-validating understanding.
class GoalEvolutionFlow extends StatefulWidget {
  const GoalEvolutionFlow({super.key, required this.currentGoal});

  /// The user's existing goal text — pre-fills the editor and is sent as
  /// `previousGoalText` to the backend.
  final String currentGoal;

  static Route<void> route({required String currentGoal}) {
    return PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, __, ___) => GoalEvolutionFlow(currentGoal: currentGoal),
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<GoalEvolutionFlow> createState() => _GoalEvolutionFlowState();
}

enum _Stage { editing, regenerating, result, failed }

class _GoalEvolutionFlowState extends State<GoalEvolutionFlow> {
  late final TextEditingController _controller;
  _Stage _stage = _Stage.editing;
  String? _rationale;
  String? _errorMessage;
  String _committedNewGoal = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentGoal);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveAndRegenerate() async {
    final newText = _controller.text.trim();
    if (newText.isEmpty) return;
    if (newText.toLowerCase() == widget.currentGoal.trim().toLowerCase()) {
      // No change — just close. No need to call the AI.
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _stage = _Stage.regenerating;
      _committedNewGoal = newText;
      _errorMessage = null;
    });

    // 1. Persist the new goal text on the server.
    final goalSaved = await TrainingProfileService().updateGoalText(newText);
    if (!mounted) return;
    if (!goalSaved) {
      setState(() {
        _stage = _Stage.failed;
        _errorMessage = 'Could not save the new goal. Check your connection and try again.';
      });
      return;
    }

    // 2. Trigger plan regeneration with previousGoalText so backend returns
    //    a goalChangeRationale describing the shift.
    try {
      final response = await AiChatService().generateWeeklyPlan({
        'goalText': newText,
        'previousGoalText': widget.currentGoal,
        'applyDailyTargets': true,
      });
      if (!mounted) return;
      final rationale = (response['goalChangeRationale'] as String?)?.trim();
      setState(() {
        _stage = _Stage.result;
        _rationale = (rationale != null && rationale.isNotEmpty)
            ? rationale
            : "Your plan has been refreshed for the new goal. The coach didn't return a written summary this time.";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _errorMessage = 'Plan regeneration failed: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxW = mq.size.width > 520 ? 480.0 : mq.size.width - 24;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxW,
              maxHeight: mq.size.height - mq.padding.top - mq.padding.bottom - 24,
            ),
            child: Material(
              color: ZveltTokens.surface,
              elevation: 16,
              shadowColor: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(ZveltTokens.rLg),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, ZveltTokens.s6, ZveltTokens.s5, ZveltTokens.s4),
                child: _buildStageBody(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStageBody(BuildContext context) {
    switch (_stage) {
      case _Stage.editing:
        return _buildEditing();
      case _Stage.regenerating:
        return _buildRegenerating();
      case _Stage.result:
        return _buildResult();
      case _Stage.failed:
        return _buildFailed();
    }
  }

  Widget _buildEditing() {
    final canSubmit = _controller.text.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(ZveltTokens.s2),
              decoration: BoxDecoration(
                color: ZveltTokens.brand.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(ZveltTokens.rSm),
              ),
              child: const Icon(AppIcons.flag, color: ZveltTokens.brand, size: 18),
            ),
            const SizedBox(width: ZveltTokens.s3),
            Expanded(
              child: Text(
                'UPDATE YOUR GOAL',
                style: TextStyle(
                  color: ZveltTokens.text2,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(AppIcons.cross_small),
              color: ZveltTokens.text2,
              onPressed: () => Navigator.of(context).maybePop(),
              tooltip: 'Cancel',
            ),
          ],
        ),
        const SizedBox(height: ZveltTokens.s2),
        Text(
          'Rewrite your goal — your plan, advice and coach reads will reshape around it.',
          style: ZType.bodyS.copyWith(
            color: ZveltTokens.text2,
            height: 1.4,
          ),
        ),
        const SizedBox(height: ZveltTokens.s5),
        TextField(
          controller: _controller,
          maxLines: 4,
          minLines: 3,
          maxLength: 1500,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'e.g. "I want to deadlift 200kg by autumn" or "Better leg endurance for boxing"',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: ZveltTokens.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: ZveltTokens.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: ZveltTokens.brand, width: 1.5),
            ),
            filled: true,
            fillColor: ZveltTokens.bg,
          ),
          style: TextStyle(color: ZveltTokens.text, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: canSubmit ? _saveAndRegenerate : null,
            icon: const Icon(AppIcons.sparkles),
            label: const Text('Save & regenerate plan'),
            style: FilledButton.styleFrom(
              backgroundColor: ZveltTokens.brand,
              foregroundColor: ZveltTokens.onBrand,
              disabledBackgroundColor: ZveltTokens.brand.withValues(alpha: 0.28),
              disabledForegroundColor: ZveltTokens.onBrand.withValues(alpha: 0.55),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZveltTokens.rMd)),
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          style: TextButton.styleFrom(
            foregroundColor: ZveltTokens.text2.withValues(alpha: 0.7),
            minimumSize: const Size(double.infinity, 36),
          ),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildRegenerating() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 42,
            height: 42,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: ZveltTokens.brand,
            ),
          ),
          const SizedBox(height: ZveltTokens.s6),
          Text(
            'Reshaping your plan…',
            style: ZType.clean.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: ZveltTokens.s2),
          Text(
            'Your coach is rebuilding the week around your new goal. Takes ~10 seconds.',
            textAlign: TextAlign.center,
            style: ZType.bodyS.copyWith(
              color: ZveltTokens.text2,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    final oldGoal = widget.currentGoal.trim();
    final newGoal = _committedNewGoal.trim();
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(ZveltTokens.s2),
                decoration: BoxDecoration(
                  color: ZveltTokens.success.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                ),
                child: const Icon(AppIcons.check, color: ZveltTokens.success, size: 18),
              ),
              const SizedBox(width: ZveltTokens.s3),
              Expanded(
                child: Text(
                  'PLAN UPDATED',
                  style: TextStyle(
                    color: ZveltTokens.text2,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZveltTokens.s5),
          _BeforeAfterRow(oldGoal: oldGoal, newGoal: newGoal),
          const SizedBox(height: ZveltTokens.s5),
          Container(
            padding: const EdgeInsets.all(ZveltTokens.s4),
            decoration: BoxDecoration(
              color: ZveltTokens.brand.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(ZveltTokens.rMd),
              border: Border.all(color: ZveltTokens.brand.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      AppIcons.brain_circuit,
                      color: ZveltTokens.brand.withValues(alpha: 0.95),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "COACH'S NOTE ON THE CHANGE",
                      style: TextStyle(
                        color: ZveltTokens.brand,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ZveltTokens.s2),
                Text(
                  _rationale ?? '',
                  style: ZType.bodyS.copyWith(
                    color: ZveltTokens.text,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: ZveltTokens.s5),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(AppIcons.check),
              label: const Text('Done'),
              style: FilledButton.styleFrom(
                backgroundColor: ZveltTokens.brand,
                foregroundColor: ZveltTokens.onBrand,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZveltTokens.rMd)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailed() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(ZveltTokens.s2),
                decoration: BoxDecoration(
                  color: ZveltTokens.error.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                ),
                child: const Icon(AppIcons.exclamation, color: ZveltTokens.error, size: 18),
              ),
              const SizedBox(width: ZveltTokens.s3),
              Expanded(
                child: Text(
                  'COULDN\'T UPDATE',
                  style: TextStyle(
                    color: ZveltTokens.text2,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'Something went wrong.',
            style: TextStyle(
              color: ZveltTokens.text,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _stage = _Stage.editing),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ZveltTokens.text,
                    side: BorderSide(color: ZveltTokens.border),
                    minimumSize: const Size(0, 44),
                  ),
                  child: const Text('Edit goal'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _saveAndRegenerate,
                  style: FilledButton.styleFrom(
                    backgroundColor: ZveltTokens.brand,
                    foregroundColor: ZveltTokens.onBrand,
                    minimumSize: const Size(0, 44),
                  ),
                  child: const Text('Retry'),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: TextButton.styleFrom(
              foregroundColor: ZveltTokens.text2.withValues(alpha: 0.7),
              minimumSize: const Size(double.infinity, 36),
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// Renders the old goal text and the new goal text stacked with an arrow
/// between them, so the user sees the shift at a glance.
class _BeforeAfterRow extends StatelessWidget {
  const _BeforeAfterRow({required this.oldGoal, required this.newGoal});

  final String oldGoal;
  final String newGoal;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _goalCard(
          label: 'BEFORE',
          text: oldGoal,
          labelColor: ZveltTokens.text2,
          textColor: ZveltTokens.text2.withValues(alpha: 0.85),
          borderColor: ZveltTokens.border,
        ),
        const SizedBox(height: 6),
        Center(
          child: Icon(
            AppIcons.arrow_small_down,
            color: ZveltTokens.text2.withValues(alpha: 0.55),
            size: 18,
          ),
        ),
        const SizedBox(height: 6),
        _goalCard(
          label: 'AFTER',
          text: newGoal,
          labelColor: ZveltTokens.brand,
          textColor: ZveltTokens.text,
          borderColor: ZveltTokens.brand.withValues(alpha: 0.45),
        ),
      ],
    );
  }

  Widget _goalCard({
    required String label,
    required String text,
    required Color labelColor,
    required Color textColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s3),
      decoration: BoxDecoration(
        color: ZveltTokens.bg,
        borderRadius: BorderRadius.circular(ZveltTokens.rSm),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
