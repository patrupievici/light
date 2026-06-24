import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';
import '../../services/messages_service.dart';
import '../../services/social_notification_hub.dart';
import '../../utils/relative_time.dart';
import '../../widgets/zvelt_avatar.dart';
import '../../widgets/zvelt_empty_state.dart';
import '../../widgets/zvelt_error_state.dart';
import 'direct_chat_screen.dart';

/// Listă conversații DM (mesagerie 1:1) — UI inspirat de pattern-uri open-source (ex. chat_bubbles demos).
class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  final _svc = MessagesService();
  List<DmConversationRow> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _svc.listConversations();
      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _openChat(DmConversationRow row) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DirectChatScreen(
          conversationId: row.conversationId,
          peer: row.peer,
        ),
      ),
    );
    await _load();
    SocialNotificationHub.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(AppIcons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: ZveltTokens.brand))
          : _error != null
              ? ZveltErrorState(
                  tier: ZveltErrorTier.generic,
                  title: "Couldn't load your messages",
                  onRetry: _load,
                )
              : _rows.isEmpty
                  ? const ZveltEmptyState(
                      icon: AppIcons.comments,
                      title: 'No conversations yet',
                      subtitle:
                          'Open a chat from Friends using the message icon.',
                    )
                  : RefreshIndicator(
                      color: ZveltTokens.brand,
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s3, ZveltTokens.s4, ZveltTokens.s8),
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: ZveltTokens.s2),
                        itemBuilder: (_, i) {
                          final r = _rows[i];
                          final preview = r.lastBody ?? 'Tap to chat';
                          return Material(
                            key: ValueKey('conv-${r.conversationId}'),
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _openChat(r),
                              borderRadius: BorderRadius.circular(ZveltTokens.rLg),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s4),
                                decoration: BoxDecoration(
                                  color: ZveltTokens.surface,
                                  borderRadius: BorderRadius.circular(ZveltTokens.rLg),
                                  boxShadow: ZveltTokens.shadowCard,
                                ),
                                child: Row(
                                  children: [
                                    ZveltAvatar(
                                      size: AvatarSize.xs,
                                      displayName: r.peer.displayName,
                                      username: r.peer.username,
                                      userId: r.peer.userId,
                                    ),
                                    const SizedBox(width: ZveltTokens.s4),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  r.peer.label,
                                                  style: ZType.bodyM.copyWith(
                                                    color: ZveltTokens.text,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (r.lastCreatedAt != null)
                                                Text(
                                                  safeRelativeTime(r.lastCreatedAt),
                                                  style: TextStyle(color: ZveltTokens.text2, fontSize: 11),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: ZveltTokens.s1),
                                          Text(
                                            preview,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(AppIcons.angle_small_right, color: ZveltTokens.text2),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
