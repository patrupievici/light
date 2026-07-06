import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../../services/_crash_reporter.dart';
import '../../services/moderation_service.dart';
import '../../services/report_outbox_service.dart';
import '../../theme/zvelt_tokens.dart';
import '../../utils/relative_time.dart';
import '../../widgets/zvelt_avatar.dart';
import '../../widgets/zvelt_empty_state.dart';
import '../../widgets/zvelt_error_state.dart';
import '../../widgets/zvelt_tertiary_button.dart';

/// Full-screen route — required by Apple §1.2 and Play UGC: users must be
/// able to inspect and unblock anyone they've previously blocked.
///
/// Handles three steady states:
///  - data: ListView with unblock action
///  - empty: "you haven't blocked anyone" copy
///  - not-deployed (404): shows the same friendly empty-state copy (no
///    dev-speak) — blocking still applies locally, so the surface keeps
///    working end-to-end.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key, ModerationService? service})
      : _service = service;

  final ModerationService? _service;

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  late final ModerationService _service =
      widget._service ?? ModerationService();

  List<BlockedUser> _items = const [];
  bool _loading = true;
  bool _backendMissing = false;
  String? _error;
  int _pendingReports = 0;

  @override
  void initState() {
    super.initState();
    _loadBlocked();
    // Wave 22 P0.2 — opportunistically drain the report outbox whenever
    // the user opens the moderation surface. If the backend just shipped,
    // queued reports flush; otherwise the count is shown in the footer.
    _drainAndRefreshOutbox();
  }

  Future<void> _drainAndRefreshOutbox() async {
    try {
      await ReportOutboxService.shared().drain();
      final count = await ReportOutboxService.shared().pendingCount();
      if (!mounted) return;
      setState(() => _pendingReports = count);
    } catch (e, st) {
      reportError(e, st, reason: 'moderation:outbox-drain');
    }
  }

  Future<void> _loadBlocked() async {
    setState(() {
      _loading = true;
      _error = null;
      _backendMissing = false;
    });
    try {
      final list = await _service.listBlocked();
      if (!mounted) return;
      // Keep local cache in sync with the canonical server list — defense in
      // depth so feed/comments filter behaves the same after a fresh launch.
      await _service.syncCacheFrom(list.map((b) => b.userId));
      setState(() {
        _items = list;
        _loading = false;
      });
    } on ModerationException catch (e, st) {
      if (!mounted) return;
      if (e.isNotDeployed) {
        setState(() {
          _loading = false;
          _backendMissing = true;
          _items = const [];
        });
        return;
      }
      reportError(e, st, reason: 'moderation:list-load');
      setState(() {
        _loading = false;
        _error = e.isNetworkError
            ? "We can't reach the server. Check your connection."
            : "Couldn't load blocked users.";
      });
    } catch (e, st) {
      reportError(e, st, reason: 'moderation:list-load');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load blocked users.";
      });
    }
  }

  Future<void> _confirmAndUnblock(BlockedUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: ZveltTokens.surface,
        title: Text('Unblock user?', style: ZType.h3.copyWith(color: ZveltTokens.text)),
        content: Text(
          'You will see ${user.displayName}\'s posts and comments again. They can also message and friend-request you.',
          style: ZType.bodyM.copyWith(color: ZveltTokens.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text('Cancel', style: ZType.bodyM.copyWith(color: ZveltTokens.text2)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _unblock(user);
  }

  Future<void> _unblock(BlockedUser user) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final before = _items;
    setState(() {
      _items = _items.where((b) => b.userId != user.userId).toList();
    });
    try {
      await _service.unblockUser(user.userId);
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(content: Text('${user.displayName} unblocked')),
      );
    } on ModerationException catch (e, st) {
      // 404 means the backend doesn't enforce yet — we already pruned the
      // local cache inside the service, so the optimistic remove is fine.
      if (e.isNotDeployed) {
        if (!mounted) return;
        messenger?.showSnackBar(
          const SnackBar(content: Text('Unblocked locally — will sync once available.')),
        );
        return;
      }
      reportError(e, st, reason: 'moderation:unblock');
      if (!mounted) return;
      setState(() => _items = before);
      messenger?.showSnackBar(
        SnackBar(content: Text(e.isNetworkError
            ? "Network error — couldn't unblock"
            : "Couldn't unblock — try again")),
      );
    } catch (e, st) {
      reportError(e, st, reason: 'moderation:unblock');
      if (!mounted) return;
      setState(() => _items = before);
      messenger?.showSnackBar(
        const SnackBar(content: Text("Couldn't unblock — try again")),
      );
    }
  }

  String _relativeDate(DateTime dt) => relativeTime(dt);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(title: const Text('Blocked users')),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          if (_pendingReports > 0) _PendingReportsBanner(count: _pendingReports),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: ZveltTokens.brand),
      );
    }
    if (_error != null) {
      final tier = _error!.toLowerCase().contains("can't reach") ||
              _error!.toLowerCase().contains('connection')
          ? ZveltErrorTier.network
          : ZveltErrorTier.generic;
      return ZveltErrorState(
        tier: tier,
        title: "Couldn't load blocked users",
        message: _error,
        onRetry: _loadBlocked,
      );
    }
    if (_backendMissing) {
      return const ZveltEmptyState(
        icon: AppIcons.ban,
        title: 'Blocked users will appear here',
        subtitle:
            'When you block someone, they no longer show up in your feed or comments. You can unblock them anytime.',
      );
    }
    if (_items.isEmpty) {
      return const ZveltEmptyState(
        icon: AppIcons.shield_check,
        title: "You haven't blocked anyone",
        subtitle:
            'When you block someone, they show up here and you can unblock them anytime.',
      );
    }
    return RefreshIndicator(
      color: ZveltTokens.brand,
      onRefresh: _loadBlocked,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s4, ZveltTokens.s4, ZveltTokens.s8),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: ZveltTokens.s3),
        itemBuilder: (_, i) {
          final u = _items[i];
          return _BlockedRow(
            key: ValueKey('blocked-${u.userId}'),
            user: u,
            blockedAgo: _relativeDate(u.blockedAt),
            onUnblock: () => _confirmAndUnblock(u),
          );
        },
      ),
    );
  }
}

class _BlockedRow extends StatelessWidget {
  const _BlockedRow({
    super.key,
    required this.user,
    required this.blockedAgo,
    required this.onUnblock,
  });

  final BlockedUser user;
  final String blockedAgo;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
      child: Row(
        children: [
          // Wave 22 P1.4 — unified avatar token (36dp = sm). Previously a
          // hand-rolled 40px Container that hard-coded surface colors and
          // computed initials manually, drifting from every other avatar in
          // the app.
          ZveltAvatar(
            size: AvatarSize.sm,
            displayName: user.displayName,
            username: user.username,
            userId: user.userId,
          ),
          const SizedBox(width: ZveltTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  style: ZType.h4.copyWith(
                    color: ZveltTokens.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (user.username != null && user.username!.isNotEmpty)
                  Text(
                    '@${user.username}',
                    style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
                  ),
                Text(
                  'Blocked $blockedAgo',
                  style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
                ),
              ],
            ),
          ),
          // Tertiary CTA — low-emphasis row action.
          ZveltTertiaryButton(
            label: 'UNBLOCK',
            dense: true,
            onTap: onUnblock,
          ),
        ],
      ),
    );
  }
}

/// Wave 22 P0.2 — surfaces the queued-but-not-yet-submitted report count
/// so the user knows their report wasn't lost (vs the prior fake-success
/// snackbar that violated Apple §1.2).
class _PendingReportsBanner extends StatelessWidget {
  const _PendingReportsBanner({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final s = count == 1 ? 'report' : 'reports';
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s2, ZveltTokens.s4, ZveltTokens.s4),
        padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
        decoration: BoxDecoration(
          color: ZveltTokens.surface,
          borderRadius: BorderRadius.circular(ZveltTokens.rLg),
          boxShadow: ZveltTokens.shadowCard,
        ),
        child: Row(
          children: [
            const Icon(AppIcons.clock, size: 18, color: ZveltTokens.brand),
            const SizedBox(width: ZveltTokens.s3),
            Expanded(
              child: Text(
                '$count pending $s — will sync when our moderation service is online.',
                style: ZType.bodyS.copyWith(
                  color: ZveltTokens.text2,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
