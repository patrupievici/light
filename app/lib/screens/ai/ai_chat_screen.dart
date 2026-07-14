import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../../theme/zvelt_tokens.dart';
import '../../services/_crash_reporter.dart';
import '../../services/ai_chat_service.dart';
import '../../services/profile_service.dart';
import '../../services/workout_service.dart';
import '../workouts/workout_tracker_screen.dart';

/// AI Coach screen — prototype "AI Coach" (HTML 417–434, composer 648–654).
/// Pushed as a full route (allowed deviation); visuals match the prototype:
/// gradient sparkles header tile, Suggested chips, floating glass composer.
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _svc = AiChatService();
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  bool _busy = false;
  String? _lastPrompt;

  /// Suggested chips (HTML 430) — label shown on the chip → preset actually
  /// sent on tap (JS 2215: askFast sends "How's my fast going?").
  static const List<(String, String)> _suggested = [
    ("What's my workout today?", "What's my workout today?"),
    ("How's my fast?", "How's my fast going?"),
    ('Suggest a lunch', 'Suggest a lunch'),
  ];

  static const String _greetingTail =
      "I'm your ZVELT coach. Ask me about workouts, meals or your fasting window.";

  @override
  void initState() {
    super.initState();
    // Seed greeting (JS 1431). Name-less fallback first; upgraded with the
    // real first name from ProfileService as soon as /me resolves.
    _msgs.add(_Msg(role: 'assistant', text: 'Hey! $_greetingTail'));
    _loadGreetingName();
  }

  Future<void> _loadGreetingName() async {
    Map<String, dynamic>? me;
    try {
      me = await ProfileService().getMe();
    } catch (_) {
      me = null;
    }
    if (!mounted || me == null) return;
    final profile = me['profile'] as Map<String, dynamic>?;
    final display = (profile?['displayName'] as String?)?.trim();
    if (display == null || display.isEmpty) return;
    final first = display.split(RegExp(r'\s+')).first;
    if (first.isEmpty) return;
    // Index 0 is always the seed (only errors are ever removed).
    setState(() {
      _msgs[0] = _Msg(role: 'assistant', text: 'Hey $first! $_greetingTail');
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send({String? retryPrompt, String? preset}) async {
    final text = retryPrompt ?? preset ?? _ctrl.text.trim();
    if (text.isEmpty || text.length > 300) return;
    if (retryPrompt == null && preset == null) _ctrl.clear();
    _lastPrompt = text;
    setState(() {
      // Drop any prior error card so the retry replaces it.
      _msgs.removeWhere((m) => m.role == 'error');
      if (retryPrompt == null) _msgs.add(_Msg(role: 'user', text: text));
      _busy = true;
    });
    _scrollBottom();

    try {
      final data = await _svc.askTrainer(text, createWorkout: true);
      final trainer = data['trainer'];
      final createdWorkout = data['workout'];
      String reply;
      if (trainer is Map) {
        final answer = (trainer['answer'] as String? ?? '').trim();
        final nextSessionFocus = ((trainer['nextSessionFocus'] as List?) ?? const [])
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList();
        final risksToWatch = ((trainer['risksToWatch'] as List?) ?? const [])
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList();
        final microPlan7Days = ((trainer['microPlan7Days'] as List?) ?? const [])
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList();

        final buffer = StringBuffer();
        buffer.writeln(answer.isEmpty ? '(no reply)' : answer);
        if (nextSessionFocus.isNotEmpty) {
          buffer.writeln('\nNext session focus:');
          for (final item in nextSessionFocus) {
            buffer.writeln('- $item');
          }
        }
        if (risksToWatch.isNotEmpty) {
          buffer.writeln('\nRisks to watch:');
          for (final item in risksToWatch) {
            buffer.writeln('- $item');
          }
        }
        if (microPlan7Days.isNotEmpty) {
          buffer.writeln('\n7-day micro plan:');
          for (final item in microPlan7Days) {
            buffer.writeln('- $item');
          }
        }
        reply = buffer.toString().trim();
      } else {
        reply = '(no reply)';
      }
      if (!mounted) return;
      setState(() => _msgs.add(_Msg(role: 'assistant', text: reply)));
      if (createdWorkout is Map && createdWorkout['id'] is String) {
        final workoutId = createdWorkout['id'] as String;
        final rawStartedAt = createdWorkout['startedAt'];
        await WorkoutService.saveActiveWorkoutPointerById(
          workoutId: workoutId,
          startedAt:
              rawStartedAt is String ? DateTime.tryParse(rawStartedAt) : null,
          label: 'AI workout',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('New workout created from AI plan. Opening tracker...'),
          ),
        );
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => WorkoutTrackerScreen(
              workoutId: workoutId,
              onComplete: () {},
            ),
          ),
        );
      }
    } on AiChatException catch (e) {
      if (!mounted) return;
      final msg = e.isTimeout
          ? 'Zvelt is taking a moment to think. Try again.'
          : "Couldn't reach the coach right now.";
      setState(() => _msgs.add(_Msg(role: 'error', text: msg, isTimeout: e.isTimeout)));
    } catch (e, st) {
      reportError(e, st, reason: 'ai_chat:send');
      if (!mounted) return;
      setState(() => _msgs.add(_Msg(role: 'error', text: "Couldn't reach the coach right now.")));
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollBottom();
    }
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _header(),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    // Bubble column: prototype padding 20/20/0 (HTML 425);
                    // bottom inset clears the floating composer.
                    padding: EdgeInsets.fromLTRB(
                        20, 20, 20, 90 + (keyboardOpen ? 0 : safeBottom)),
                    // messages + typing indicator + trailing Suggested block
                    // (always visible per prototype, HTML 430).
                    itemCount: _msgs.length + (_busy ? 1 : 0) + 1,
                    itemBuilder: (_, i) {
                      final tail = _msgs.length + (_busy ? 1 : 0);
                      if (i == tail) return _suggestedBlock();
                      if (_busy && i == _msgs.length) {
                        return const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: _TypingDots(),
                          ),
                        );
                      }
                      final m = _msgs[i];
                      if (m.role == 'error') {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ErrorCard(
                            message: m.text,
                            isTimeout: m.isTimeout,
                            onRetry: _busy || _lastPrompt == null
                                ? null
                                : () => _send(retryPrompt: _lastPrompt),
                          ),
                        );
                      }
                      return _bubble(m);
                    },
                  ),
                ),
              ],
            ),
          ),
          // Floating liquid-glass composer (HTML 649–653) anchored above the
          // bottom safe area (pushed screen — no nav bar underneath).
          Positioned(
            left: 16,
            right: 16,
            bottom: keyboardOpen ? 10 : safeBottom + 12,
            child: _composer(),
          ),
        ],
      ),
    );
  }

  /// Header row (HTML 419–421): circle back (app idiom) + 42×42 gradient
  /// sparkles tile + "ZVELT Coach" / "● Online · AI-assisted".
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 22, 0),
      child: Row(
        children: [
          _CircleBack(onTap: () => Navigator.of(context).maybePop()),
          const SizedBox(width: 11),
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ZveltTokens.rChip),
              gradient: ZveltTokens.gradAccentDeep,
              boxShadow: ZveltTokens.glowMd,
            ),
            child: const Icon(AppIcons.sparkles,
                color: ZveltTokens.onBrand, size: 22),
          ),
          const SizedBox(width: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ZVELT Coach', style: ZType.h4),
              const SizedBox(height: 1),
              Text(
                '● Online · AI-assisted',
                style: ZType.monoS
                    .copyWith(color: ZveltTokens.brand, height: 1.2),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Chat bubble (JS 2042–2051): user = accent bg, radius 20/20/6/20, no
  /// border, max-w 78%, brand glow; AI = surface2 + border, radius 20/20/20/6,
  /// max-w 82%. Text 13.5 w500 lh1.45. No timestamps (prototype has none).
  Widget _bubble(_Msg m) {
    final user = m.role == 'user';
    final w = MediaQuery.sizeOf(context).width;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        constraints: BoxConstraints(maxWidth: w * (user ? 0.78 : 0.82)),
        decoration: user
            ? BoxDecoration(
                color: ZveltTokens.brand,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomRight: Radius.circular(6),
                  bottomLeft: Radius.circular(20),
                ),
                // Prototype: 0 6px 16px rgba(240,120,12,.3) — brandGlow base
                // color at the prototype's softer .3 alpha (JS 2049).
                boxShadow: [
                  BoxShadow(
                      color: ZveltTokens.brandGlow.withValues(alpha: 0.3),
                      offset: const Offset(0, 6),
                      blurRadius: 16),
                ],
              )
            : BoxDecoration(
                color: ZveltTokens.surface2,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                  bottomLeft: Radius.circular(6),
                ),
                border: Border.all(color: ZveltTokens.border),
              ),
        child: Text(
          m.text,
          style: ZType.bodyM.copyWith(
            fontSize: 13.5,
            height: 1.45,
            color: user ? ZveltTokens.onBrand : ZveltTokens.text,
          ),
        ),
      ),
    );
  }

  /// "Suggested" label + 3 glass chips (HTML 430) — always visible; a tap
  /// sends the preset as a real message (JS 2215).
  Widget _suggestedBlock() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text('Suggested',
                style: ZType.monoS.copyWith(color: ZveltTokens.text3)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, preset) in _suggested)
                GestureDetector(
                  onTap: _busy ? null : () => _send(preset: preset),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: ZveltTokens.chip,
                      borderRadius:
                          BorderRadius.circular(ZveltTokens.rControl),
                      border: Border.all(color: ZveltTokens.border),
                    ),
                    child: Text(
                      label,
                      style: ZType.monoS.copyWith(
                          fontSize: 12.5,
                          color: ZveltTokens.text,
                          height: 1.2),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Floating glass pill composer (HTML 649–653): blur 24 + navBg fill,
  /// radius 26, border, "Ask your coach…", 40×40 circular gradient send.
  Widget _composer() {
    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(ZveltTokens.rCardLg)),
        boxShadow: ZveltTokens.shadowFloat,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ZveltTokens.rCardLg),
        child: BackdropFilter(
          filter: ImageFilter.blur(
              sigmaX: ZveltTokens.glassBlur, sigmaY: ZveltTokens.glassBlur),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 7, 7, 7),
            decoration: BoxDecoration(
              color: ZveltTokens.navBg,
              borderRadius: BorderRadius.circular(ZveltTokens.rCardLg),
              border: Border.all(color: ZveltTokens.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    maxLength: 300, // cap enforced silently (no counter)
                    maxLines: 1,
                    textInputAction: TextInputAction.send,
                    cursorColor: ZveltTokens.brand,
                    style: ZType.bodyM
                        .copyWith(color: ZveltTokens.text, height: 1.3),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      counterText: '',
                      hintText: 'Ask your coach…',
                      hintStyle: ZType.bodyM
                          .copyWith(color: ZveltTokens.text3, height: 1.3),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (_) => _busy ? null : _send(),
                  ),
                ),
                const SizedBox(width: 9),
                GestureDetector(
                  onTap: _busy ? null : _send,
                  child: Opacity(
                    opacity: _busy ? 0.6 : 1,
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: ZveltTokens.gradAccentDeep,
                        boxShadow: ZveltTokens.glowMd,
                      ),
                      child: const Icon(AppIcons.paper_plane,
                          color: ZveltTokens.onBrand, size: 18),
                    ),
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

class _Msg {
  _Msg({required this.role, required this.text, this.isTimeout = false});
  final String role; // 'user' | 'assistant' | 'error'
  final String text;
  final bool isTimeout;
}

/// 40×40 circular back button — app idiom for pushed screens.
class _CircleBack extends StatelessWidget {
  const _CircleBack({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ZveltTokens.surface,
      shape: const CircleBorder(),
      shadowColor: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: ZveltTokens.surface,
          shape: BoxShape.circle,
          boxShadow: ZveltTokens.shadowCard,
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              AppIcons.angle_small_left,
              color: ZveltTokens.text2,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

/// Three animated dots shown while awaiting AI reply, styled as an AI bubble.
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: ZveltTokens.surface2,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
          bottomLeft: Radius.circular(6),
        ),
        border: Border.all(color: ZveltTokens.border),
      ),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final t = ((_c.value + i * 0.2) % 1.0);
              final opacity = 0.3 + 0.7 * (1 - (2 * t - 1).abs()).clamp(0.0, 1.0);
              return Padding(
                padding: EdgeInsets.only(right: i < 2 ? 6 : 0),
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: ZveltTokens.brand3,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

/// Slim inline card with a Retry button shown when an AI call fails.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.isTimeout, this.onRetry});
  final String message;
  final bool isTimeout;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final accent = isTimeout ? ZveltTokens.warn : ZveltTokens.error;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        border: Border.all(color: accent.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(isTimeout ? AppIcons.clock : AppIcons.cloud_disabled, color: accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: ZType.bodyS
                  .copyWith(color: ZveltTokens.text, height: 1.4),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: accent),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
