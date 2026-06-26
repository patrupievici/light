import 'package:flutter/material.dart';

import '../../models/social_challenge.dart';
import '../../services/_crash_reporter.dart';
import '../../services/social_challenge_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/zvelt_empty_state.dart';
import '../../widgets/zvelt_error_state.dart';
import 'race_hub_screen.dart';

/// "Camere publice" — browse public rooms: seeded official rooms first, then
/// community public challenges. Reuses the challenge engine; tapping a room
/// opens its hub (standings + chat + log progress, which auto-joins).
class DiscoverRoomsScreen extends StatefulWidget {
  const DiscoverRoomsScreen({super.key});

  @override
  State<DiscoverRoomsScreen> createState() => _DiscoverRoomsScreenState();
}

class _DiscoverRoomsScreenState extends State<DiscoverRoomsScreen> {
  final _service = SocialChallengeService();

  List<SocialChallenge> _rooms = const [];
  bool _loading = true;
  bool _failed = false;
  final Set<String> _joining = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _rooms.isEmpty;
      _failed = false;
    });
    try {
      final rooms = await _service.discover(limit: 40);
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _loading = false;
      });
    } catch (e, st) {
      reportError(e, st, reason: 'rooms:discover');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = _rooms.isEmpty;
      });
    }
  }

  Future<void> _join(SocialChallenge room) async {
    if (_joining.contains(room.id)) return;
    setState(() => _joining.add(room.id));
    try {
      await _service.joinChallenge(room.id);
      if (!mounted) return;
      setState(() {
        final i = _rooms.indexWhere((r) => r.id == room.id);
        if (i >= 0) {
          _rooms[i] = _rooms[i].copyWith(
            joined: true,
            participantsCount: _rooms[i].participantsCount + 1,
          );
        }
      });
    } catch (e, st) {
      reportError(e, st, reason: 'rooms:join');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nu am putut intra în cameră.')),
      );
    } finally {
      if (mounted) setState(() => _joining.remove(room.id));
    }
  }

  Future<void> _open(SocialChallenge room) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => RaceHubScreen(initialChallengeId: room.id)),
    );
    if (mounted) _load(); // refresh counts/joined after the hub visit
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        backgroundColor: ZveltTokens.surface,
        surfaceTintColor: Colors.transparent,
        title: Text('Camere publice', style: ZType.h4.copyWith(color: ZveltTokens.text)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: ZveltTokens.brand))
          : _failed
              ? ZveltErrorState(title: 'Nu am putut încărca camerele', onRetry: _load)
              : RefreshIndicator(
                  color: ZveltTokens.brand,
                  onRefresh: _load,
                  child: _rooms.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 80),
                            ZveltEmptyState(
                              icon: AppIcons.globe,
                              title: 'Nicio cameră publică',
                              subtitle: 'Creează o provocare publică din feed ca să apară aici.',
                            ),
                          ],
                        )
                      : _buildList(),
                ),
    );
  }

  Widget _buildList() {
    final official = _rooms.where((r) => r.isOfficial).toList();
    final community = _rooms.where((r) => !r.isOfficial).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: ZveltTokens.s8),
      children: [
        if (official.isNotEmpty) ...[
          _sectionHeader('Camere oficiale', AppIcons.badge_check),
          for (final r in official) _RoomCard(
            room: r,
            joining: _joining.contains(r.id),
            onJoin: () => _join(r),
            onOpen: () => _open(r),
          ),
        ],
        if (community.isNotEmpty) ...[
          _sectionHeader('De la comunitate', AppIcons.users),
          for (final r in community) _RoomCard(
            room: r,
            joining: _joining.contains(r.id),
            onJoin: () => _join(r),
            onOpen: () => _open(r),
          ),
        ],
      ],
    );
  }

  Widget _sectionHeader(String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          ZveltTokens.s4, ZveltTokens.s4, ZveltTokens.s4, ZveltTokens.s2),
      child: Row(
        children: [
          Icon(icon, color: ZveltTokens.brand, size: 18),
          const SizedBox(width: ZveltTokens.s2),
          Text(label,
              style: ZType.eyebrow.copyWith(color: ZveltTokens.text3, letterSpacing: 0.6)),
        ],
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.joining,
    required this.onJoin,
    required this.onOpen,
  });

  final SocialChallenge room;
  final bool joining;
  final VoidCallback onJoin;
  final VoidCallback onOpen;

  IconData get _kindIcon => switch (room.kind) {
        SocialChallengeKind.pullUps => AppIcons.gym,
        SocialChallengeKind.deadlift => AppIcons.gym,
        SocialChallengeKind.squat => AppIcons.gym,
        SocialChallengeKind.benchPress => AppIcons.gym,
        SocialChallengeKind.custom => AppIcons.flame,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(ZveltTokens.s4, 0, ZveltTokens.s4, ZveltTokens.s2),
      child: InkWell(
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(ZveltTokens.s3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(ZveltTokens.s3),
                decoration: BoxDecoration(
                  color: ZveltTokens.brandTint.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                ),
                child: Icon(_kindIcon, color: ZveltTokens.brand, size: 22),
              ),
              const SizedBox(width: ZveltTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(room.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ZType.h4.copyWith(fontSize: 15, color: ZveltTokens.text)),
                        ),
                        if (room.isOfficial) ...[
                          const SizedBox(width: ZveltTokens.s2),
                          const Icon(AppIcons.badge_check, color: ZveltTokens.brand, size: 16),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(AppIcons.users, color: ZveltTokens.text3, size: 13),
                        const SizedBox(width: 4),
                        Text('${room.participantsCount} membri',
                            style: ZType.bodyS.copyWith(color: ZveltTokens.text3, fontSize: 12)),
                        if (room.creatorDisplayName != null && !room.isOfficial) ...[
                          Text('  ·  ', style: ZType.bodyS.copyWith(color: ZveltTokens.text4)),
                          Flexible(
                            child: Text(room.creatorDisplayName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ZType.bodyS.copyWith(color: ZveltTokens.text3, fontSize: 12)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: ZveltTokens.s2),
              _trailing(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trailing() {
    if (room.joined) {
      return TextButton(
        onPressed: onOpen,
        child: Text('Deschide', style: ZType.bodyM.copyWith(color: ZveltTokens.brand, fontWeight: FontWeight.w600)),
      );
    }
    return FilledButton(
      onPressed: joining ? null : onJoin,
      style: FilledButton.styleFrom(
        backgroundColor: ZveltTokens.brand,
        foregroundColor: ZveltTokens.onBrand,
        padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
      ),
      child: joining
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Text('Intră'),
    );
  }
}
