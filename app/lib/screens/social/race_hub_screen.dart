import 'dart:async';
import 'package:zvelt_app/theme/app_icons.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_strings.dart';
import '../../models/social_challenge.dart';
import '../../services/_crash_reporter.dart';
import '../../services/social_challenge_service.dart';
import '../../theme/zvelt_tokens.dart';
import '../../utils/relative_time.dart';
import '../../widgets/zvelt_empty_state.dart';
import '../../widgets/zvelt_error_state.dart';
import '../../widgets/zvelt_primary_button.dart';

class RaceHubScreen extends StatefulWidget {
  const RaceHubScreen({super.key, this.initialChallengeId});

  /// Optional: deep-link target. After [_loadChallenges] resolves the
  /// matching challenge, we auto-push [RaceChatScreen] so the "JOIN" CTA
  /// on the social hero card lands on the chat directly.
  final String? initialChallengeId;

  @override
  State<RaceHubScreen> createState() => _RaceHubScreenState();
}

class _RaceHubScreenState extends State<RaceHubScreen> {
  String _discipline = 'lift';
  String _preset = 'volume';

  /// Presets shown for each discipline — plain-language, strength-app-relevant
  /// (no cycling jargon like FTP/KOM on a Lift race).
  List<({String key, String label})> _presetsFor(String d) {
    switch (d) {
      case 'lift':
        return const [(key: 'volume', label: 'Volume'), (key: 'max', label: 'Max lift'), (key: 'reps', label: 'Reps')];
      case 'run':
        return const [(key: 'distance', label: 'Distance'), (key: 'time', label: 'Time'), (key: 'pace', label: 'Pace')];
      case 'bike':
        return const [(key: 'distance', label: 'Distance'), (key: 'time', label: 'Time'), (key: 'elevation', label: 'Climb')];
      case 'body':
        return const [(key: 'reps', label: 'Reps'), (key: 'streak', label: 'Streak'), (key: 'time', label: 'Time')];
      default:
        return const [(key: 'volume', label: 'Volume')];
    }
  }

  /// Select a discipline and reset the preset to a valid one for it (so e.g.
  /// "Distance" doesn't linger when you switch to Lift).
  void _selectDiscipline(String d) {
    setState(() {
      _discipline = d;
      final presets = _presetsFor(d);
      if (!presets.any((p) => p.key == _preset)) _preset = presets.first.key;
    });
  }

  String _presetLabel(String key) =>
      _presetsFor(_discipline).firstWhere((p) => p.key == key, orElse: () => (key: key, label: 'Custom')).label;
  int _duration = 7;
  String _privacy = 'private';
  bool _launching = false;

  final _challengeService = SocialChallengeService();
  List<SocialChallenge> _challenges = [];
  final Map<String, bool> _joinedChallenges = {};
  final Map<String, int> _participantCounts = {};
  // Join/leave taps in flight — guards _toggleJoin against rapid re-taps.
  final Set<String> _togglingJoinFor = {};
  // Trending list fetch state — so loading/error aren't shown as 'no races'.
  bool _challengesLoading = true;
  bool _challengesError = false;
  bool _deepLinkConsumed = false;

  // Gradient palettes for trending cards (cycled by index).
  // Single-orange signal: all cards ramp through the brand family —
  // depth comes from the brand3→brandDeep range, not off-palette hues.
  static const _gradients = [
    [ZveltTokens.brand, ZveltTokens.brandDeep],
    [ZveltTokens.brand2, ZveltTokens.brandDeep],
    [ZveltTokens.brand3, ZveltTokens.brand],
    [ZveltTokens.brand, ZveltTokens.brandDeep],
    [ZveltTokens.brand2, ZveltTokens.brandDeep],
  ];

  _TrendingRace _challengeToTrending(SocialChallenge c, int idx) {
    final colors = _gradients[idx % _gradients.length];
    final now = DateTime.now();
    final daysLeft = c.endsAt.difference(now).inDays.clamp(0, 999);
    return _TrendingRace(
      title: c.title,
      athletes: '$daysLeft days left',
      colors: colors,
    );
  }

  List<_TrendingRace> get _trending =>
      _challenges.asMap().entries.map((e) => _challengeToTrending(e.value, e.key)).toList();

  @override
  void initState() {
    super.initState();
    _loadChallenges();
  }

  Future<void> _loadChallenges() async {
    if (mounted && !_challengesLoading) {
      setState(() {
        _challengesLoading = true;
        _challengesError = false;
      });
    }
    try {
      final challenges = await _challengeService.loadActive();
      if (!mounted) return;
      setState(() {
        _challengesLoading = false;
        _challengesError = false;
        _challenges = challenges;
        // Hydrate joined state + counts from the server payload. Without
        // this, a race joined in a previous session (or via the feed hero)
        // showed 'JOIN THE RACE' forever, and re-tapping it bumped the
        // participant count past reality.
        for (final c in challenges) {
          _joinedChallenges[c.id] = c.joined;
          _participantCounts[c.id] = c.participantsCount;
        }
      });
      await _loadParticipantCounts();
      _maybeOpenDeepLink();
    } catch (e, st) {
      reportError(e, st, reason: 'race-hub:load-challenges');
      // Distinguish 'load failed' from 'no races exist' — the empty state
      // used to claim 'No active races' during the fetch and on errors.
      if (mounted) {
        setState(() {
          _challengesLoading = false;
          _challengesError = true;
        });
      }
    }
  }

  /// Called once after the challenge list loads if the screen was opened with
  /// [RaceHubScreen.initialChallengeId] (typically after the user just tapped
  /// "JOIN THE RACE" on the feed hero card).
  ///
  /// Previously this auto-pushed [RaceChatScreen] (the private Race Notes
  /// notepad), which surprised users — they expected to LAND in the race
  /// overview and see participants / progress, not in their own scratchpad.
  ///
  /// New behavior: stay on the hub (so the user sees their joined challenge
  /// in context with all other challenges) and surface a small confirmation
  /// snackbar with an explicit "Open notes" action — discoverable but
  /// opt-in, not forced.
  void _maybeOpenDeepLink() {
    if (_deepLinkConsumed) return;
    final target = widget.initialChallengeId;
    if (target == null || target.isEmpty) return;
    SocialChallenge? match;
    for (final c in _challenges) {
      if (c.id == target) {
        match = c;
        break;
      }
    }
    if (match == null) {
      // Deep link pointed at a race that's no longer active (ended /
      // deleted / never existed). Surface a clear note instead of
      // silently swallowing — the user tapped on something expecting
      // a destination.
      _deepLinkConsumed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('That race has ended or is no longer available.'),
          ),
        );
      });
      return;
    }
    _deepLinkConsumed = true;
    // No confirmation snackbar here: this path fires on every navigation
    // into the hub with a target race (hero card tap), not just on a fresh
    // join — users read the lingering "You're in: …" pill as an error
    // (Cip's feedback, 2026-06-12). Landing on the hub with the race
    // visible IS the confirmation; Notes stays reachable from the header.
  }

  void _openRaceChat(SocialChallenge challenge) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RaceChatScreen(challenge: challenge),
      ),
    );
  }

  /// Maps the configurator pickers (`_discipline`, `_preset`) onto the
  /// `SocialChallengeKind` enum the backend understands. The race hub UI
  /// exposes broader categories than the enum, so anything that doesn't
  /// have a 1:1 mapping falls back to `custom` with a human-friendly
  /// `customTitle` so the feed still renders a meaningful name.
  SocialChallenge _draftFromConfigurator() {
    final now = DateTime.now();
    // Every configurator preset maps to a `custom` challenge with a friendly
    // title built from the discipline + preset (e.g. "Volume Race").
    const kind = SocialChallengeKind.custom;
    final customTitle = '${_presetLabel(_preset)} Race';
    // Tag the discipline into the targetHint so the server (and feed
    // explainers) can render a sub-label.
    final targetHint = _discipline.isEmpty ? null : 'discipline:$_discipline';

    return SocialChallenge(
      id: now.millisecondsSinceEpoch.toString(),
      kind: kind,
      customTitle: customTitle,
      visibility: _privacy == 'private' ? 'friends' : 'public',
      targetHint: targetHint,
      durationDays: _duration,
      createdAt: now,
      endsAt: now.add(Duration(days: _duration)),
    );
  }

  Future<void> _launchRace() async {
    if (_launching) return;
    if (_discipline.isEmpty || _preset.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a discipline and a preset first.')),
      );
      return;
    }
    setState(() => _launching = true);
    final draft = _draftFromConfigurator();
    try {
      await _challengeService.publish(draft);
      if (!mounted) return;
      // Refresh the local list so the trending row updates; `publish()`
      // upserts the server-side row when the API is reachable, so we
      // re-load to pick up the server id (and `_loadChallenges` already
      // refreshes participant counts).
      await _loadChallenges();
      if (!mounted) return;
      // Find the just-published challenge (matching customTitle + duration
      // is "good enough" because publish either replaces the draft id with
      // a server uuid or keeps our local id verbatim).
      final fresh = _challenges.firstWhere(
        (c) =>
            c.customTitle == draft.customTitle &&
            c.durationDays == draft.durationDays,
        orElse: () => draft,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Race launched · 0 athletes joined'),
          duration: Duration(seconds: 2),
        ),
      );
      _openRaceChat(fresh);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  Future<void> _loadParticipantCounts() async {
    // Parallel — the old serial loop awaited each request (22s timeout
    // apiece), so with N races on a slow connection counts trickled in for
    // minutes and the deep-link snackbar waited behind all of them.
    await Future.wait(_challenges.map((c) async {
      try {
        final result = await _challengeService.getChallengeParticipants(c.id);
        if (mounted) {
          setState(() => _participantCounts[c.id] = result['total'] as int? ?? 0);
        }
      } catch (e, st) {
        reportError(e, st, reason: 'race-hub:participants-count');
      }
    }));
  }

  Future<void> _toggleJoin(String challengeId) async {
    // Guard against rapid re-taps — without it every tap queues another
    // join/leave API call while the first is still in flight.
    if (_togglingJoinFor.contains(challengeId)) return;
    _togglingJoinFor.add(challengeId);
    final alreadyJoined = _joinedChallenges[challengeId] ?? false;
    try {
      if (alreadyJoined) {
        await _challengeService.leaveChallenge(challengeId);
        if (mounted) {
          setState(() {
          _joinedChallenges[challengeId] = false;
          _participantCounts[challengeId] = (_participantCounts[challengeId] ?? 1) - 1;
        });
        }
      } else {
        await _challengeService.joinChallenge(challengeId);
        if (mounted) {
          setState(() {
          _joinedChallenges[challengeId] = true;
          _participantCounts[challengeId] = (_participantCounts[challengeId] ?? 0) + 1;
        });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      _togglingJoinFor.remove(challengeId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: Column(
        children: [
          // Header
          Padding(
            padding: EdgeInsets.fromLTRB(ZveltTokens.s4, top + ZveltTokens.s2, ZveltTokens.s4, ZveltTokens.s4),
            child: Row(
              children: [
                Semantics(
                  button: true,
                  label: 'Back',
                  child: _CircleBtn(
                    onTap: () => Navigator.pop(context),
                    child: Icon(AppIcons.angle_small_left,
                        size: 16, color: ZveltTokens.text2),
                  ),
                ),
                const SizedBox(width: ZveltTokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Race Hub',
                          style: ZType.h4.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Race notes',
                  child: _CircleBtn(
                  gradient: ZveltTokens.gradBtn,
                  // null when there's nothing to open — the button visibly
                  // dims so the user understands instead of getting a
                  // snackbar after tapping a button that looked active.
                  // Prefer the first JOINED race; opening notes for an
                  // arbitrary feed-order race confused users ('whose
                  // notepad is this?').
                  onTap: _challenges.isEmpty
                      ? null
                      : () => _openRaceChat(_challenges.firstWhere(
                            (c) => _joinedChallenges[c.id] ?? false,
                            orElse: () => _challenges.first,
                          )),
                  child: const Icon(AppIcons.comment_alt,
                      size: 16, color: Colors.white),
                  ),
                ),
                const SizedBox(width: ZveltTokens.s2),
                Semantics(
                  button: true,
                  label: 'Race settings',
                  child: _CircleBtn(
                    onTap: () => _showRaceSettings(context),
                    child: Icon(AppIcons.settings,
                        size: 16, color: ZveltTokens.text2),
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, 0, ZveltTokens.s4, ZveltTokens.s8),
              children: [
                // Build-a-race configurator (dark hero card)
                _RZCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('BUILD A RACE',
                          style: ZType.eyebrow.copyWith(color: ZveltTokens.brandDeep)),
                      const SizedBox(height: ZveltTokens.s2),
                      Text('Launch new race', style: ZType.h1),
                      const SizedBox(height: ZveltTokens.s6),

                      const _RZLabel('DISCIPLINE'),
                      const SizedBox(height: ZveltTokens.s3),
                      Row(children: [
                        Expanded(child: _DiscCard(icon: AppIcons.gym, label: 'Lift', selected: _discipline == 'lift', onTap: () => _selectDiscipline('lift'))),
                        const SizedBox(width: 10),
                        Expanded(child: _DiscCard(icon: AppIcons.running, label: 'Run', selected: _discipline == 'run', onTap: () => _selectDiscipline('run'))),
                        const SizedBox(width: 10),
                        Expanded(child: _DiscCard(icon: AppIcons.bike, label: 'Bike', selected: _discipline == 'bike', onTap: () => _selectDiscipline('bike'))),
                        const SizedBox(width: 10),
                        Expanded(child: _DiscCard(icon: AppIcons.bolt, label: 'Body', selected: _discipline == 'body', onTap: () => _selectDiscipline('body'))),
                      ]),
                      const SizedBox(height: ZveltTokens.s6),

                      const _RZLabel('PRESET'),
                      const SizedBox(height: ZveltTokens.s3),
                      Row(children: [
                        for (final (i, p) in _presetsFor(_discipline).indexed) ...[
                          if (i > 0) const SizedBox(width: ZveltTokens.s2),
                          _PresetPill(label: p.label, selected: _preset == p.key, onTap: () => setState(() => _preset = p.key)),
                        ],
                      ]),
                      const SizedBox(height: ZveltTokens.s6),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const _RZLabel('DURATION'),
                          Text('$_duration DAYS',
                              style: ZType.monoXS.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5,
                                  color: ZveltTokens.brandDeep)),
                        ],
                      ),
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 5,
                          activeTrackColor: ZveltTokens.brand,
                          inactiveTrackColor: ZveltTokens.surface3,
                          thumbColor: ZveltTokens.brand,
                          overlayColor: ZveltTokens.brand.withValues(alpha: 0.2),
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                        ),
                        child: Slider(
                          value: _duration.toDouble(),
                          min: 7,
                          max: 30,
                          onChanged: (v) => setState(() => _duration = v.round()),
                        ),
                      ),
                      const SizedBox(height: ZveltTokens.s3),

                      const _RZLabel('PRIVACY'),
                      const SizedBox(height: ZveltTokens.s3),
                      Row(children: [
                        Expanded(child: _PrivacyOption(icon: AppIcons.globe, label: 'Public', selected: _privacy == 'public', onTap: () => setState(() => _privacy = 'public'))),
                        const SizedBox(width: ZveltTokens.s3),
                        Expanded(child: _PrivacyOption(icon: AppIcons.user, label: 'Friends', selected: _privacy == 'private', onTap: () => setState(() => _privacy = 'private'))),
                      ]),
                      const SizedBox(height: ZveltTokens.s5),

                      ZveltPrimaryButton(
                        label: 'Launch new race',
                        busyLabel: 'Launching…',
                        busy: _launching,
                        variant: ZveltPrimaryVariant.lightInverse,
                        onTap: _launchRace,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: ZveltTokens.s6),

                // Global Trending. ('EXPLORE ALL' removed — it was a dead
                // brand-colored text styled exactly like a link, with no
                // handler and no destination.)
                Text('GLOBAL TRENDING',
                    style: ZType.eyebrow.copyWith(color: ZveltTokens.text2)),
                const SizedBox(height: ZveltTokens.s3),
                if (_challengesLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            color: ZveltTokens.brand, strokeWidth: 2.5),
                      ),
                    ),
                  )
                else if (_challengesError && _trending.isEmpty)
                  ZveltErrorState(
                    compact: true,
                    tier: ZveltErrorTier.network,
                    title: "Couldn't load races",
                    onRetry: _loadChallenges,
                  )
                else if (_trending.isEmpty)
                  const ZveltEmptyState(
                    compact: true,
                    icon: AppIcons.flag,
                    title: 'No active races',
                    subtitle: 'Be the first to launch one!',
                  )
                else SizedBox(
                  height: 148,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _challenges.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) {
                      final challenge = _challenges[i];
                      final r = _trending[i];
                      final joined = _joinedChallenges[challenge.id] ?? false;
                      final count = _participantCounts[challenge.id] ?? 0;
                      return Container(
                        key: ValueKey('chall-${challenge.id}'),
                        width: 168,
                        padding: const EdgeInsets.all(ZveltTokens.s4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(ZveltTokens.rLg),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: r.colors,
                          ),
                          boxShadow: [
                            BoxShadow(color: r.colors[0].withValues(alpha: 0.4), blurRadius: 22, offset: const Offset(0, 6)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                      color: Colors.white, shape: BoxShape.circle)),
                              const SizedBox(width: ZveltTokens.s1),
                              const Text('LIVE',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: 1.5)),
                            ]),
                            const SizedBox(height: ZveltTokens.s2),
                            Text(r.title,
                                style: const TextStyle(
                                    fontFamily: ZveltTokens.fontPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.white,
                                    height: 1)),
                            const SizedBox(height: ZveltTokens.s1),
                            Text('$count athletes',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white.withValues(alpha: 0.8))),
                            const Spacer(),
                            GestureDetector(
                              onTap: () => _toggleJoin(challenge.id),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                height: 28,
                                decoration: BoxDecoration(
                                  color: joined ? Colors.white.withValues(alpha: 0.15) : Colors.white,
                                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                                  border: joined ? Border.all(color: Colors.white.withValues(alpha: 0.6)) : null,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  joined ? 'LEAVE RACE' : 'JOIN THE RACE',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.2,
                                    color: joined ? Colors.white : r.colors[1],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showRaceSettings(BuildContext ctx) {
    // ── Was 3 no-op tiles (Race notifications / Leave this race / Share
    //    race link) that all just called Navigator.pop. Replaced with two
    //    actions that actually work in v1.0:
    //    • Refresh — re-fetch the active challenge list.
    //    • Share Zvelt — generic app-share so users can invite friends.
    //    Per-race notifications and "leave this race" need backend
    //    endpoints that aren't shipping in v1.0, so they're hidden until
    //    the routes exist instead of pretending to work.
    showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: ZveltTokens.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, ZveltTokens.s4, ZveltTokens.s5, ZveltTokens.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: ZveltTokens.border, borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
              ),
            ),
            const SizedBox(height: ZveltTokens.s4),
            Text('Race hub', style: ZType.h4),
            const SizedBox(height: ZveltTokens.s4),
            _SettingsTile(
              icon: AppIcons.refresh,
              label: 'Refresh active races',
              onTap: () {
                Navigator.pop(ctx);
                _loadChallenges();
              },
            ),
            _SettingsTile(
              icon: AppIcons.share,
              label: 'Share Zvelt with friends',
              onTap: () async {
                Navigator.pop(ctx);
                await SharePlus.instance.share(
                  ShareParams(
                    text:
                        'Join me on Zvelt — strength, races, and a feed that only counts real workouts. https://zvelt.app',
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Race Notes Screen ───────────────────────────────────────────────────────

// RACE NOTES: local-only private notepad per challenge.
// Future: when /v1/challenges/{id}/chat/messages ships server-side, this
// will sync and become a real multi-athlete chat — the local store
// acts as both cache and offline composer.
//
// Class name preserved (`RaceChatScreen`) to avoid breaking navigation
// call-sites; the UX is honest about being a single-user notepad in v1.0.
class RaceChatScreen extends StatefulWidget {
  const RaceChatScreen({super.key, required this.challenge});

  final SocialChallenge challenge;

  @override
  State<RaceChatScreen> createState() => _RaceChatScreenState();
}

class _RaceChatScreenState extends State<RaceChatScreen> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _challengeService = SocialChallengeService();

  /// Shared race chat rows from GET /challenges/:id/messages
  /// ({id, userId, displayName, body, createdAt, mine}).
  List<Map<String, dynamic>> _messages = [];
  bool _loadingMessages = true;
  bool _sending = false;

  // ── Design race experience (screens-race.jsx) — SERVER-BACKED ─────────────
  // 0 = Standings, 1 = Chat. Progress logs, per-athlete totals, rank and
  // the shared chat all live on /v1/challenges/:id/{progress,standings,messages}.
  int _tab = 0;

  double _myTotal = 0;
  int _myRank = 0; // 0 = not in standings yet
  List<Map<String, dynamic>> _standings = const [];
  bool _loadingStandings = true;

  /// Product target per race kind (mirrors the design's raceSpecFromConfig
  /// constants — these are goals/targets, not user data).
  ({String unit, double goal, String metric}) get _spec {
    switch (widget.challenge.kind) {
      case SocialChallengeKind.pullUps:
        return (unit: 'reps', goal: 400, metric: 'Pull-ups');
      case SocialChallengeKind.benchPress:
      case SocialChallengeKind.deadlift:
      case SocialChallengeKind.squat:
        return (unit: 'kg', goal: 24000, metric: 'Volume');
      case SocialChallengeKind.custom:
        return (unit: 'reps', goal: 300, metric: 'Reps');
    }
  }

  Future<void> _loadStandings() async {
    try {
      final res = await _challengeService.getStandings(widget.challenge.id);
      if (!mounted) return;
      setState(() {
        _standings = ((res['data'] as List<dynamic>?) ?? const [])
            .cast<Map<String, dynamic>>();
        final me = res['me'] as Map<String, dynamic>?;
        _myRank = (me?['rank'] as num?)?.toInt() ?? 0;
        _myTotal = (me?['total'] as num?)?.toDouble() ?? 0;
        _loadingStandings = false;
      });
    } catch (e, st) {
      reportError(e, st, reason: 'race:standings');
      if (mounted) setState(() => _loadingStandings = false);
    }
  }

  Future<void> _logProgress(double amount) async {
    if (amount <= 0) return;
    final spec = _spec;
    try {
      final r = await _challengeService.logProgress(widget.challenge.id, amount);
      if (!mounted) return;
      setState(() {
        _myTotal = r.total;
        _myRank = r.rank;
      });
      unawaited(_loadStandings());
      // Design's system message — posted to the SHARED chat so the pack
      // sees the move (server-backed, like everything else here now).
      final label =
          amount % 1 == 0 ? amount.toInt().toString() : amount.toStringAsFixed(1);
      unawaited(_send(
          prefilled: '⚡ Logged $label ${spec.unit} — now #${r.rank}'));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  void _openLogSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ZveltTokens.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _RaceLogSheet(spec: _spec, onLog: _logProgress),
    );
  }

  // Curated final list for v1.0 — competitive but not combative.
  // TODO(v1.1): move to GET /v1/i18n/race-replies for backend curation and A/B testing.
  static const List<String> _quickReplies = AppStrings.raceQuickReplies;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    // Server-backed race: standings (totals + rank) and shared chat load
    // in parallel; identity comes from the token server-side.
    unawaited(_loadStandings());
    try {
      final msgs = await _challengeService.getRaceMessages(widget.challenge.id);
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _loadingMessages = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    } catch (e, st) {
      reportError(e, st, reason: 'race-chat:bootstrap');
      if (!mounted) return;
      setState(() => _loadingMessages = false);
    }
  }

  void _scrollToEnd() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _showEmojiPicker(BuildContext ctx) {
    const emojis = ['🔥', '💪', '🏆', '👏', '😤', '🚀', '⚡', '🎯', '😂', '❤️'];
    showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: ZveltTokens.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(ZveltTokens.rLg))),
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s3, ZveltTokens.s4, ZveltTokens.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: ZveltTokens.border,
                    borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
              ),
            ),
            const SizedBox(height: ZveltTokens.s4),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 5,
              mainAxisSpacing: ZveltTokens.s2,
              crossAxisSpacing: ZveltTokens.s2,
              children: emojis
                  .map((e) => GestureDetector(
                        onTap: () {
                          Navigator.pop(sheetCtx);
                          _send(prefilled: e);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: ZveltTokens.bg2,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: ZveltTokens.border),
                          ),
                          alignment: Alignment.center,
                          child: Text(e, style: const TextStyle(fontSize: 24)),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send({String? prefilled}) async {
    if (_sending) return;
    final raw = prefilled ?? _ctrl.text;
    final text = raw.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final saved = await _challengeService.sendRaceMessage(
        widget.challenge.id,
        text,
      );
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, saved];
        if (prefilled == null) _ctrl.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    } catch (e, st) {
      reportError(e, st, reason: 'race-chat:send');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _formatTime(String? iso) {
    final dt = iso != null ? DateTime.tryParse(iso) : null;
    return dt != null ? relativeTime(dt.toLocal()) : '';
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;
    final challenge = widget.challenge;
    final spec = _spec;
    final daysLeft =
        challenge.endsAt.difference(DateTime.now()).inDays.clamp(0, 999);
    final pct = spec.goal > 0 ? (_myTotal / spec.goal).clamp(0.0, 1.0) : 0.0;

    // ── Design (screens-race.jsx): header → dark hero (your progress ring)
    // → Standings/Notes segmented → tab content → Log-progress CTA or the
    // notes composer. Honest data: YOUR total is local-first, participants
    // are real names; per-athlete totals + rank + shared chat need backend
    // support (on Razvan's list) and are not faked.
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(ZveltTokens.screenPaddingH, top + ZveltTokens.s2, ZveltTokens.screenPaddingH, ZveltTokens.s3),
            child: Row(
              children: [
                Semantics(
                  button: true,
                  label: 'Back',
                  child: _CircleBtn(
                    onTap: () => Navigator.pop(context),
                    child: Icon(AppIcons.arrow_small_left,
                        size: 18, color: ZveltTokens.text),
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        daysLeft == 0
                            ? 'ENDS TODAY'
                            : '$daysLeft DAY${daysLeft == 1 ? '' : 'S'} LEFT',
                        style: ZType.eyebrow,
                      ),
                      const SizedBox(height: ZveltTokens.s1),
                      Text(
                        challenge.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: ZType.bodyL.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 36),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              controller: _tab == 1 ? _scrollCtrl : null,
              padding: const EdgeInsets.fromLTRB(ZveltTokens.screenPaddingH, ZveltTokens.s1, ZveltTokens.screenPaddingH, ZveltTokens.s4),
              children: [
                // ── Your progress hero (light card + ring) ────────────────
                Container(
                  padding: const EdgeInsets.all(ZveltTokens.s5),
                  decoration: BoxDecoration(
                    color: ZveltTokens.surface,
                    borderRadius: BorderRadius.circular(ZveltTokens.rLg),
                    boxShadow: ZveltTokens.shadowHero,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      Positioned(
                        top: -30,
                        right: -30,
                        child: Container(
                          width: 160,
                          height: 160,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [ZveltTokens.brandGlow, Colors.transparent],
                              stops: [0.0, 0.7],
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          SizedBox(
                            width: 88,
                            height: 88,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CustomPaint(
                                  size: const Size(88, 88),
                                  painter: _RaceRingPainter(progress: pct),
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _myRank > 0 ? '#$_myRank' : '—',
                                      style: ZType.num_.copyWith(
                                          fontSize: 20, color: ZveltTokens.text),
                                    ),
                                    Text(
                                      'RANK',
                                      style: ZType.eyebrow.copyWith(
                                        fontSize: 11,
                                        letterSpacing: 0.6,
                                        color: ZveltTokens.text3,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: ZveltTokens.s5),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      _myTotal % 1 == 0
                                          ? '${_myTotal.toInt()}'
                                          : _myTotal.toStringAsFixed(1),
                                      style: ZType.num_.copyWith(
                                          fontSize: 28, color: ZveltTokens.text),
                                    ),
                                    const SizedBox(width: ZveltTokens.s1),
                                    Text(
                                      '/ ${spec.goal.toInt()} ${spec.unit}',
                                      style: ZType.bodyS.copyWith(
                                        color: ZveltTokens.text3,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: ZveltTokens.s2),
                                Text(
                                  _heroStatusLine(),
                                  style: ZType.bodyS.copyWith(
                                    height: 1.4,
                                    color: ZveltTokens.text2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: ZveltTokens.s4),

                // ── Segmented: Standings / Notes ──────────────────────────
                Container(
                  padding: const EdgeInsets.all(ZveltTokens.s1),
                  decoration: BoxDecoration(
                    color: ZveltTokens.surface2,
                    borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                  ),
                  child: Row(
                    children: [
                      for (final (i, label) in const [(0, 'Standings'), (1, 'Chat')])
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _tab = i),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s2),
                              decoration: BoxDecoration(
                                color: _tab == i
                                    ? ZveltTokens.surface
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                                boxShadow:
                                    _tab == i ? ZveltTokens.shadowCard : null,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                label,
                                style: ZType.bodyS.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: _tab == i
                                      ? ZveltTokens.text
                                      : ZveltTokens.text3,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: ZveltTokens.s4),

                if (_tab == 0)
                  _buildStandings()
                else
                  ..._buildChatItems(),
              ],
            ),
          ),

          // ── Bottom: Log CTA (standings) or composer (notes) ─────────────
          if (_tab == 0)
            Padding(
              padding: EdgeInsets.fromLTRB(ZveltTokens.screenPaddingH, ZveltTokens.s2, ZveltTokens.screenPaddingH, bottom + ZveltTokens.s4),
              child: GestureDetector(
                onTap: _openLogSheet,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                    gradient: ZveltTokens.gradBtn,
                    boxShadow: [
                      BoxShadow(
                        color: ZveltTokens.brand.withValues(alpha: 0.34),
                        blurRadius: 26,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(AppIcons.plus, size: 18, color: Colors.white),
                      SizedBox(width: ZveltTokens.s2),
                      Text(
                        'Log progress',
                        style: TextStyle(
                          fontFamily: ZveltTokens.fontPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            _buildComposer(bottom),
        ],
      ),
    );
  }

  /// Design hero status line: leading margin or gap to the athlete ahead.
  String _heroStatusLine() {
    final spec = _spec;
    if (_myRank <= 0 || _standings.isEmpty) {
      return 'Log your first ${spec.metric.toLowerCase()} to enter the standings.';
    }
    if (_myRank == 1) {
      final second =
          _standings.length > 1 ? (_standings[1]['total'] as num?)?.toDouble() ?? 0 : 0.0;
      final margin = (_myTotal - second);
      final m = margin % 1 == 0 ? margin.toInt().toString() : margin.toStringAsFixed(1);
      return 'Leading — $m ${spec.unit} ahead';
    }
    final ahead = _standings[_myRank - 2];
    final gap = ((ahead['total'] as num?)?.toDouble() ?? 0) - _myTotal;
    final g = gap % 1 == 0 ? gap.toInt().toString() : gap.toStringAsFixed(1);
    return '$g ${spec.unit} behind ${(ahead['displayName'] as String?) ?? 'the leader'}';
  }

  // ── Standings card — real totals from /standings (design layout) ──────────
  static const _medal = [Color(0xFFFFC24B), Color(0xFFC8CDD4), Color(0xFFE2A06A)];

  Widget _buildStandings() {
    if (_loadingStandings) {
      return const Padding(
        padding: EdgeInsets.all(30),
        child: Center(
          child: CircularProgressIndicator(
              color: ZveltTokens.brand, strokeWidth: 2),
        ),
      );
    }
    final spec = _spec;
    return Container(
      padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s1, ZveltTokens.s4, ZveltTokens.s1),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        children: [
          if (_standings.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s5),
              child: Text(
                'No one has joined yet — be the first.',
                style: ZType.bodyS.copyWith(color: ZveltTokens.text3),
              ),
            )
          else
            for (var i = 0; i < _standings.length; i++)
              _standingRow(i, _standings[i], spec),
        ],
      ),
    );
  }

  Widget _standingRow(
      int i, Map<String, dynamic> s, ({String unit, double goal, String metric}) spec) {
    final isMe = _myRank > 0 && i == _myRank - 1;
    final total = (s['total'] as num?)?.toDouble() ?? 0;
    final pct = spec.goal > 0 ? (total / spec.goal).clamp(0.0, 1.0) : 0.0;
    final name = (s['displayName'] as String?) ?? 'Athlete';
    final totalLabel =
        total % 1 == 0 ? total.toInt().toString() : total.toStringAsFixed(1);

    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMe ? 0 : 0),
      padding: EdgeInsets.symmetric(vertical: ZveltTokens.s3, horizontal: isMe ? ZveltTokens.s2 : 0),
      decoration: BoxDecoration(
        color: isMe
            ? ZveltTokens.brand.withValues(alpha: 0.06)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(isMe ? 12 : 0),
        border: i < _standings.length - 1 && !isMe
            ? Border(bottom: BorderSide(color: ZveltTokens.border))
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '${i + 1}',
              textAlign: TextAlign.center,
              style: ZType.num_.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: i < 3 ? _medal[i] : ZveltTokens.text3,
              ),
            ),
          ),
          const SizedBox(width: ZveltTokens.s2),
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: ZveltTokens.gradBrand,
            ),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'A',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: ZveltTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZType.bodyS.copyWith(
                    fontWeight: isMe ? FontWeight.w700 : FontWeight.w600,
                    color: ZveltTokens.text,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 4,
                    backgroundColor: ZveltTokens.surface3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isMe ? ZveltTokens.brand : ZveltTokens.border,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: ZveltTokens.s3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                totalLabel,
                style: ZType.num_.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isMe ? ZveltTokens.brand : ZveltTokens.text,
                ),
              ),
              Text(
                spec.unit,
                style:
                    TextStyle(fontSize: 11, color: ZveltTokens.text3),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Chat items (inside the shared ListView) ────────────────────────────────
  List<Widget> _buildChatItems() {
    if (_loadingMessages) {
      return const [
        Padding(
          padding: EdgeInsets.all(30),
          child: Center(
            child: CircularProgressIndicator(
                color: ZveltTokens.brand, strokeWidth: 2),
          ),
        ),
      ];
    }
    if (_messages.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _buildEmptyState(),
        ),
      ];
    }
    return [
      for (var i = 0; i < _messages.length; i++)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
          child: _chatBubble(_messages[i]),
        ),
    ];
  }

  /// Design bubbles: system '⚡' lines centered as brand pills, mine
  /// right-aligned on a brand gradient, others left with the sender name.
  Widget _chatBubble(Map<String, dynamic> m) {
    final body = (m['body'] as String?) ?? '';
    final mine = m['mine'] == true;
    final name = (m['displayName'] as String?) ?? 'Athlete';
    final time = _formatTime(m['createdAt'] as String?);

    if (body.startsWith('⚡')) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: 6),
          decoration: BoxDecoration(
            color: ZveltTokens.brandTint,
            borderRadius: BorderRadius.circular(ZveltTokens.rPill),
          ),
          child: Text(
            mine ? body : '$name $body',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: ZveltTokens.fontPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ZveltTokens.brandDeep,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment:
          mine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!mine) ...[
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: ZveltTokens.gradBrand,
            ),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'A',
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.74),
            padding: const EdgeInsets.fromLTRB(13, 9, 13, 6),
            decoration: BoxDecoration(
              gradient: mine ? ZveltTokens.gradBtn : null,
              color: mine ? null : ZveltTokens.surface,
              border: mine ? null : Border.all(color: ZveltTokens.border),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(mine ? 16 : 4),
                bottomRight: Radius.circular(mine ? 4 : 16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!mine)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: ZveltTokens.brandDeep,
                      ),
                    ),
                  ),
                Text(
                  body,
                  style: ZType.bodyS.copyWith(
                    height: 1.4,
                    color: mine ? Colors.white : ZveltTokens.text,
                  ),
                ),
                const SizedBox(height: ZveltTokens.s1),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 11,
                    color: mine
                        ? Colors.white.withValues(alpha: 0.75)
                        : ZveltTokens.text3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Notes composer (quick chips + input) ───────────────────────────────────
  Widget _buildComposer(double bottom) {
    return Container(
      padding: EdgeInsets.fromLTRB(ZveltTokens.s4, 10, ZveltTokens.s4, bottom + 10),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        border: Border(top: BorderSide(color: ZveltTokens.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _quickReplies.map((q) {
                return Padding(
                  padding: const EdgeInsets.only(right: ZveltTokens.s2),
                  child: GestureDetector(
                    onTap: () {
                      _ctrl.text =
                          '${_ctrl.text}${_ctrl.text.isEmpty ? '' : ' '}$q';
                      _ctrl.selection = TextSelection.fromPosition(
                          TextPosition(offset: _ctrl.text.length));
                    },
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3),
                      decoration: BoxDecoration(
                        color: ZveltTokens.surface2,
                        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                      ),
                      child: Center(
                        child: Text(
                          q,
                          style: TextStyle(
                            fontFamily: ZveltTokens.fontPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: ZveltTokens.text2,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: ZveltTokens.s2),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: ZveltTokens.bg,
                    border: Border.all(color: ZveltTokens.border),
                    borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                  ),
                  padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, 0, ZveltTokens.s2, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          enabled: !_sending,
                          textCapitalization: TextCapitalization.sentences,
                          style: ZType.bodyS.copyWith(color: ZveltTokens.text),
                          decoration: InputDecoration(
                            hintText: 'Message the pack…',
                            hintStyle: ZType.bodyS.copyWith(color: ZveltTokens.text3),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: 'Add emoji',
                        child: GestureDetector(
                          onTap: () => _showEmojiPicker(context),
                          child: Icon(AppIcons.grin,
                              size: 18, color: ZveltTokens.text2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: ZveltTokens.s2),
              Semantics(
                button: true,
                label: 'Send message',
                child: GestureDetector(
                  onTap: _sending ? null : () => _send(),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: ZveltTokens.brand,
                    ),
                    child: _sending
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(AppIcons.arrow_small_right,
                            size: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ZveltTokens.brand.withValues(alpha: 0.12),
                border: Border.all(
                    color: ZveltTokens.brand.withValues(alpha: 0.25)),
              ),
              child: const Icon(AppIcons.edit,
                  color: ZveltTokens.brand, size: 30),
            ),
            const SizedBox(height: ZveltTokens.s4),
            Text(
              'Start the trash-talk',
              textAlign: TextAlign.center,
              style: ZType.h4.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: ZveltTokens.s1),
            Text(
              'Everyone in this race sees the chat. Logged progress shows up here too.',
              textAlign: TextAlign.center,
              style: ZType.bodyS.copyWith(height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Hero progress ring (design: 88px, stroke 6, white12 track) ─────────────

class _RaceRingPainter extends CustomPainter {
  _RaceRingPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    final r = (size.width - stroke) / 2;
    final center = Offset(size.width / 2, size.height / 2);

    final track = Paint()
      ..color = ZveltTokens.surface3
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center, r, track);

    if (progress <= 0) return;
    final arc = Paint()
      ..color = ZveltTokens.brand
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RaceRingPainter old) => old.progress != progress;
}

// ─── Race log sheet (design RaceLogSheet: stepper + quick chips) ─────────────

class _RaceLogSheet extends StatefulWidget {
  const _RaceLogSheet({required this.spec, required this.onLog});

  final ({String unit, double goal, String metric}) spec;
  final ValueChanged<double> onLog;

  @override
  State<_RaceLogSheet> createState() => _RaceLogSheetState();
}

class _RaceLogSheetState extends State<_RaceLogSheet> {
  late double _amount;
  late final double _step;
  late final List<double> _chips;

  @override
  void initState() {
    super.initState();
    // Unit-aware presets — mirrors the design's RaceLogSheet table.
    switch (widget.spec.unit) {
      case 'kg':
        _amount = 5;
        _step = 2.5;
        _chips = const [2.5, 5, 10, 20];
        break;
      default: // reps
        _amount = 20;
        _step = 5;
        _chips = const [10, 20, 30, 50];
    }
  }

  String _fmt(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

  Widget _stepBtn(IconData icon, VoidCallback onTap, {required String label}) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ZveltTokens.surface,
            border: Border.all(color: ZveltTokens.border),
          ),
          child: Icon(icon, size: 20, color: ZveltTokens.text),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, ZveltTokens.s3, ZveltTokens.s5, ZveltTokens.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ZveltTokens.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: ZveltTokens.s4),
            Row(
              children: [
                const Icon(AppIcons.bolt, size: 12, color: ZveltTokens.brand),
                const SizedBox(width: 4),
                Text(
                  'LOG PROGRESS',
                  style: ZType.eyebrow.copyWith(
                      fontSize: 11, color: ZveltTokens.text3),
                ),
              ],
            ),
            const SizedBox(height: ZveltTokens.s1),
            Text(
              'How much ${spec.metric.toLowerCase()}?',
              style: ZType.display.copyWith(fontSize: 24, color: ZveltTokens.text),
            ),
            const SizedBox(height: ZveltTokens.s5),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _stepBtn(AppIcons.minus, () {
                  setState(() {
                    _amount = (_amount - _step).clamp(_step, 100000);
                  });
                }, label: 'Decrease amount'),
                SizedBox(
                  width: 120,
                  child: Column(
                    children: [
                      Text(
                        _fmt(_amount),
                        style: ZType.stat.copyWith(
                            fontSize: 42, color: ZveltTokens.text),
                      ),
                      Text(
                        spec.unit.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.7,
                          color: ZveltTokens.text3,
                        ),
                      ),
                    ],
                  ),
                ),
                _stepBtn(AppIcons.plus, () {
                  setState(() => _amount += _step);
                }, label: 'Increase amount'),
              ],
            ),
            const SizedBox(height: ZveltTokens.s5),
            Row(
              children: [
                for (final c in _chips) ...[
                  if (c != _chips.first) const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _amount = c),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _amount == c
                              ? ZveltTokens.brandTint
                              : ZveltTokens.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _amount == c
                                ? ZveltTokens.brand3
                                : ZveltTokens.border,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _fmt(c),
                          style: ZType.bodyS.copyWith(
                            fontWeight: FontWeight.w600,
                            color: _amount == c
                                ? ZveltTokens.brandDeep
                                : ZveltTokens.text2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: ZveltTokens.s5),
            GestureDetector(
              onTap: () {
                Navigator.of(context).pop();
                widget.onLog(_amount);
              },
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                  gradient: ZveltTokens.gradBtn,
                  boxShadow: [
                    BoxShadow(
                      color: ZveltTokens.brand.withValues(alpha: 0.34),
                      blurRadius: 26,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  'Add ${_fmt(_amount)} ${spec.unit}',
                  style: const TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: ZveltTokens.s3),
            Center(
              child: Text(
                'Stored on this device — server sync is on the roadmap.',
                style: TextStyle(fontSize: 11, color: ZveltTokens.text3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

class _CircleBtn extends StatelessWidget {
  const _CircleBtn({required this.child, required this.onTap, this.gradient});
  final Widget child;
  /// Nullable so callers can disable the button visually (e.g. chat with
  /// no active races) instead of catching the tap and showing a snackbar.
  final VoidCallback? onTap;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: disabled ? 0.4 : 1.0,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: gradient,
            color: gradient == null ? ZveltTokens.surface : null,
            border: gradient == null ? Border.all(color: ZveltTokens.border) : null,
            boxShadow: gradient != null
                ? [BoxShadow(color: ZveltTokens.brand.withValues(alpha: 0.4), blurRadius: 14)]
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _RZCard extends StatelessWidget {
  const _RZCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(ZveltTokens.s6),
        decoration: BoxDecoration(
          // Warm peach hero card — light accent surface.
          color: ZveltTokens.surfaceTinted,
          borderRadius: BorderRadius.circular(ZveltTokens.rLg),
          boxShadow: ZveltTokens.shadowHero,
        ),
        child: child,
      );
}

// Mono uppercase section label on the dark configurator card.
class _RZLabel extends StatelessWidget {
  const _RZLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: ZType.eyebrow.copyWith(color: ZveltTokens.text2),
      );
}

// One of the 4 discipline cards (Lift / Run / Bike / Body).
class _DiscCard extends StatelessWidget {
  const _DiscCard({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s4),
          decoration: BoxDecoration(
            gradient: selected ? ZveltTokens.gradBtn : null,
            color: selected ? null : ZveltTokens.surface,
            borderRadius: BorderRadius.circular(ZveltTokens.rMd),
            boxShadow: selected
                ? [BoxShadow(color: ZveltTokens.brand.withValues(alpha: 0.4), blurRadius: 14)]
                : null,
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: selected ? Colors.white : ZveltTokens.text2),
              const SizedBox(height: ZveltTokens.s2),
              Text(label,
                  style: ZType.bodyS.copyWith(
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : ZveltTokens.text2)),
            ],
          ),
        ),
      );
}

// A single preset pill (Volume / Distance / Reps / …, per discipline).
class _PresetPill extends StatelessWidget {
  const _PresetPill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s5, vertical: ZveltTokens.s3),
          decoration: BoxDecoration(
            color: selected ? ZveltTokens.brand : ZveltTokens.surface,
            borderRadius: BorderRadius.circular(ZveltTokens.rPill),
          ),
          child: Text(label,
              style: ZType.bodyM.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : ZveltTokens.text2)),
        ),
      );
}

// Public / Friends privacy option.
class _PrivacyOption extends StatelessWidget {
  const _PrivacyOption({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 52,
          decoration: BoxDecoration(
            color: selected ? ZveltTokens.brandTint : ZveltTokens.surface,
            borderRadius: BorderRadius.circular(ZveltTokens.rMd),
            border: Border.all(color: selected ? ZveltTokens.brand : Colors.transparent),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: selected ? ZveltTokens.brandDeep : ZveltTokens.text2),
              const SizedBox(width: ZveltTokens.s2),
              Text(label,
                  style: ZType.bodyM.copyWith(
                      fontWeight: FontWeight.w700,
                      color: selected ? ZveltTokens.brandDeep : ZveltTokens.text2)),
            ],
          ),
        ),
      );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger = false;

  @override
  Widget build(BuildContext context) {
    final color = danger ? ZveltTokens.error : ZveltTokens.text;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ZveltTokens.rSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s3, horizontal: ZveltTokens.s1),
        child: Row(
          children: [
            Icon(icon, size: 20, color: danger ? ZveltTokens.error : ZveltTokens.text2),
            const SizedBox(width: ZveltTokens.s4),
            Text(label, style: ZType.bodyM.copyWith(color: color, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _TrendingRace {
  const _TrendingRace({required this.title, required this.athletes, required this.colors});
  final String title;
  final String athletes;
  final List<Color> colors;
}
