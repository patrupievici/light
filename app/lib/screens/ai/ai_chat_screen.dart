import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../../theme/zvelt_tokens.dart';
import '../../services/ai_chat_service.dart';
import '../../services/workout_service.dart';
import '../workouts/workout_tracker_screen.dart';

/// Chat AI prin backend DeepSeek (todo #31 / #26).
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

  /// Design's COACH_PROMPTS — shown as chips until the first user message.
  static const _suggestedPrompts = [
    'Am I recovered enough to train?',
    'What should I eat today?',
    'Plan my training week',
    'Review my bench form',
  ];

  @override
  void initState() {
    super.initState();
    // Local seed greeting (design's coachSeed). Honest copy: it promises
    // personalization (true — the backend reads profile + training data),
    // it does NOT claim to have already analyzed anything.
    _msgs.add(_Msg(
      role: 'assistant',
      text: "Hey 👋 I'm your Zvelt coach. I can read your profile, training "
          'settings and recovery data. What do you want to tackle today?',
    ));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send({String? retryPrompt}) async {
    final text = retryPrompt ?? _ctrl.text.trim();
    if (text.isEmpty || text.length > 300) return;
    if (retryPrompt == null) _ctrl.clear();
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _msgs.add(_Msg(role: 'error', text: "Couldn't reach the coach right now.")));
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollBottom();
    }
  }

  /// Design: suggested prompts visible only while the thread is fresh
  /// (just the seed greeting, no user message yet).
  bool get _showPrompts =>
      !_busy && !_msgs.any((m) => m.role == 'user');

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      // Design header: "Coach Zvelt" + green "AI · always on" status row.
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Coach Zvelt',
              style: TextStyle(
                fontFamily: ZveltTokens.fontPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: ZveltTokens.text,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: ZveltTokens.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                const Text(
                  'AI · always on',
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: ZveltTokens.success,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'AI trainer responses are personalized from your profile, training settings, and current workout suggestion. Max 300 chars/message.',
              style: TextStyle(color: ZveltTokens.text2, fontSize: 11, height: 1.45),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              // +1 slot for the suggested-prompt chips while the thread is
              // fresh (design: show only at the start, hide after the first
              // user message).
              itemCount: _msgs.length + (_busy ? 1 : 0) + (_showPrompts ? 1 : 0),
              itemBuilder: (_, i) {
                if (_showPrompts && i == _msgs.length + (_busy ? 1 : 0)) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in _suggestedPrompts)
                          GestureDetector(
                            onTap: _busy
                                ? null
                                : () {
                                    _ctrl.text = p;
                                    _send();
                                  },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: ZveltTokens.s4, vertical: ZveltTokens.s2),
                              decoration: BoxDecoration(
                                color: ZveltTokens.brandTint,
                                borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                              ),
                              child: Text(
                                p,
                                style: const TextStyle(
                                  fontFamily: ZveltTokens.fontPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: ZveltTokens.brandDeep,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }
                if (_busy && i == _msgs.length) {
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: _TypingDots(),
                    ),
                  );
                }
                final m = _msgs[i];
                if (m.role == 'error') {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ErrorCard(
                      message: m.text,
                      isTimeout: m.isTimeout,
                      onRetry: _busy || _lastPrompt == null
                          ? null
                          : () => _send(retryPrompt: _lastPrompt),
                    ),
                  );
                }
                final user = m.role == 'user';
                return Align(
                  alignment: user ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
                    decoration: BoxDecoration(
                      color: user ? ZveltTokens.brand : ZveltTokens.surface,
                      borderRadius: BorderRadius.circular(ZveltTokens.rLg),
                      border: Border.all(color: ZveltTokens.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          m.text,
                          style: TextStyle(
                            color: user ? ZveltTokens.onBrand : ZveltTokens.text,
                            fontSize: 15,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Design: time under the bubble text (real client-side
                        // send/receive moment).
                        Text(
                          m.timeLabel,
                          style: TextStyle(
                            color: (user ? ZveltTokens.onBrand : ZveltTokens.text3)
                                .withValues(alpha: user ? 0.7 : 1.0),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.paddingOf(context).bottom + 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    maxLength: 300,
                    maxLines: 3,
                    minLines: 1,
                    style: TextStyle(color: ZveltTokens.text),
                    decoration: InputDecoration(
                      hintText: 'Ask about training, nutrition…',
                      counterStyle: TextStyle(color: ZveltTokens.text2, fontSize: 11),
                    ),
                    onSubmitted: (_) => _busy ? null : _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _busy ? null : _send,
                  icon: const Icon(AppIcons.paper_plane),
                  style: IconButton.styleFrom(
                    backgroundColor: ZveltTokens.brand,
                    foregroundColor: ZveltTokens.onBrand,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ZveltTokens.rLg),
                    ),
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

class _Msg {
  _Msg({required this.role, required this.text, this.isTimeout = false})
      : at = DateTime.now();
  final String role; // 'user' | 'assistant' | 'error'
  final String text;
  final bool isTimeout;

  /// Client-side timestamp (design shows times under bubbles) — stamped at
  /// creation, so it's the real send/receive moment, nothing invented.
  final DateTime at;

  String get timeLabel =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
}

/// Three animated dots shown while awaiting AI reply. Appears within one frame
/// (<100ms) thanks to the synchronous setState() in [_send].
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
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
              style: TextStyle(color: ZveltTokens.text, fontSize: 13, height: 1.4),
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
