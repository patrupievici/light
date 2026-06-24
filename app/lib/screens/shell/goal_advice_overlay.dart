import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../../models/training_profile_models.dart';
import '../../services/training_profile_service.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/typewriter_reveal_text.dart';
import 'goal_evolution_flow.dart';

/// Quick Action „Advice”: mesajul AI din onboarding + obiectivul liber.
/// Rută și Hero aliniate cu fluxul provocărilor ([ChallengeKindPickerPage]).
class GoalAdviceOverlay extends StatefulWidget {
  const GoalAdviceOverlay({super.key, required this.heroTag});

  static const String kHeroTag = 'zvelt_quick_action_goal_advice';

  final String heroTag;

  static Route<void> route({String heroTag = kHeroTag}) {
    return PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      barrierLabel: 'Dismiss',
      transitionDuration: const Duration(milliseconds: 800),
      reverseTransitionDuration: const Duration(milliseconds: 800),
      pageBuilder: (context, animation, secondaryAnimation) {
        return GoalAdviceOverlay(heroTag: heroTag);
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
    );
  }

  @override
  State<GoalAdviceOverlay> createState() => _GoalAdviceOverlayState();
}

class _GoalAdviceOverlayState extends State<GoalAdviceOverlay> {
  TrainingProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    final p = await TrainingProfileService().fetch(refresh: refresh);
    if (!mounted) return;
    setState(() {
      _profile = p;
      _loading = false;
    });
  }

  ShapeBorder _heroShape() => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        side: BorderSide(color: ZveltTokens.border),
      );

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final routeAnim = ModalRoute.of(context)?.animation;
    final openProgress = routeAnim != null
        ? CurvedAnimation(parent: routeAnim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)
        : const AlwaysStoppedAnimation<double>(1);

    final goal = _profile?.onboardingGoalText?.trim();
    final advice = _profile?.goalAdviceText?.trim();

    final body = _loading
        ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: ZveltTokens.brand)))
        : SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset * 0.25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (goal != null && goal.isNotEmpty) ...[
                  Text(
                    'Your goal',
                    style: ZType.eyebrow.copyWith(
                      color: ZveltTokens.text3,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    goal,
                    style: ZType.h4.copyWith(
                      color: ZveltTokens.text,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Goal Evolution entry — lets the user rewrite their goal
                  // and watch the coach reshape the plan around it.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () async {
                        await Navigator.of(context).push(
                          GoalEvolutionFlow.route(currentGoal: goal),
                        );
                        if (!mounted) return;
                        // Plan + advice may have changed — reload so the
                        // overlay shows the latest advice for the new goal.
                        await _load(refresh: true);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: ZveltTokens.s2),
                        decoration: BoxDecoration(
                          color: ZveltTokens.brandTint,
                          borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              AppIcons.edit,
                              color: ZveltTokens.brand,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Update this goal',
                              style: ZType.bodyS.copyWith(
                                color: ZveltTokens.brand,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              AppIcons.arrow_small_right,
                              color: ZveltTokens.brand,
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                Text(
                  'Guidance',
                  style: ZType.eyebrow.copyWith(
                    color: ZveltTokens.text3,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 8),
                if (advice != null && advice.isNotEmpty)
                  TypewriterRevealText(
                    key: ValueKey(advice),
                    text: advice,
                    style: ZType.bodyM.copyWith(
                      color: ZveltTokens.text,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  )
                else
                  Text(
                    goal != null && goal.isNotEmpty
                        ? 'Generate your AI plan from onboarding to unlock personalized tips for this goal, or ask Zvelt in chat.'
                        : 'Finish onboarding and describe your goal with „Generate My Plan” to see tailored tips here.',
                    style: ZType.bodyM.copyWith(
                      color: ZveltTokens.text2,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
              ],
            ),
          );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Hero(
                tag: widget.heroTag,
                transitionOnUserGestures: true,
                child: Material(
                  color: ZveltTokens.surface,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  shape: _heroShape(),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 12, 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(AppIcons.cross_small),
                              onPressed: () => Navigator.pop(context),
                              visualDensity: VisualDensity.compact,
                              style: IconButton.styleFrom(foregroundColor: ZveltTokens.text),
                            ),
                            Expanded(
                              child: Text(
                                'Advice',
                                style: ZType.h3.copyWith(
                                  color: ZveltTokens.text,
                                  fontSize: 17,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(AppIcons.refresh, size: 22),
                              tooltip: 'Reload',
                              visualDensity: VisualDensity.compact,
                              style: IconButton.styleFrom(foregroundColor: ZveltTokens.text2),
                              onPressed: () {
                                setState(() => _loading = true);
                                _load(refresh: true);
                              },
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 12, right: 8, top: 4),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(ZveltTokens.s2),
                                decoration: BoxDecoration(
                                  color: ZveltTokens.brandTint,
                                  borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                                ),
                                child: const Icon(AppIcons.bulb,
                                    color: ZveltTokens.brand, size: 14),
                              ),
                              const SizedBox(width: ZveltTokens.s2),
                              Expanded(
                                child: Text(
                                  'Notes from your onboarding — elite competitors see sport-science-focused guidance.',
                                  style: ZType.bodyS.copyWith(
                                    color: ZveltTokens.text2,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: FadeTransition(
                  opacity: CurvedAnimation(
                    parent: openProgress,
                    curve: const Interval(0.12, 1.0, curve: Curves.easeOutCubic),
                  ),
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.04),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: openProgress,
                        curve: const Interval(0.12, 1.0, curve: Curves.easeOutCubic),
                      ),
                    ),
                    child: Material(
                      color: ZveltTokens.surface,
                      shape: _heroShape(),
                      clipBehavior: Clip.antiAlias,
                      child: body,
                    ),
                  ),
                ),
              ),
              SizedBox(height: bottomInset > 0 ? 4 : 10),
            ],
          ),
        ),
      ),
    );
  }
}
