import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../../models/social_feed_post.dart';
import '../../services/_crash_reporter.dart';
import '../../services/social_feed_service.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/social_feed_post_card.dart';
import '../../widgets/zvelt_empty_state.dart';
import '../../widgets/zvelt_error_state.dart';

/// "My Bookmarks" — paginated list of posts the current user saved.
///
/// Mirrors the feed card UI / pull-to-refresh / cursor-pagination patterns used
/// by [SocialPlusScreen] so the experience feels consistent. The list reacts to
/// per-card bookmark toggles (via `onBookmarkChanged`) and slides the row out
/// when the user un-bookmarks from inside this screen.
class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  final _service = SocialFeedService();
  final ScrollController _scrollController = ScrollController();

  List<SocialFeedPost> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 1;
  bool _hasMore = true;
  SocialFeedException? _error;

  /// Posts currently mid-removal animation. Tracked so the AnimatedList-style
  /// fade-out plays once before we drop the entry, without double-firing on
  /// rebuilds.
  final Set<String> _removing = <String>{};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    final ratio = _scrollController.position.pixels / max;
    if (ratio >= 0.8) _loadMore();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
      _hasMore = true;
      _posts = [];
      _removing.clear();
    });
    try {
      final page = await _service.getBookmarks(page: 1);
      if (!mounted) return;
      setState(() {
        _posts = page.posts;
        _page = 2;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } on SocialFeedException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    } catch (e, st) {
      reportError(e, st, reason: 'bookmarks:load');
      if (!mounted) return;
      setState(() {
        _error = SocialFeedException(e.toString());
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.getBookmarks(page: _page);
      if (!mounted) return;
      // Filter out any post that was already optimistically removed from this
      // screen (so a mid-pagination un-bookmark can't re-introduce a ghost row)
      // AND any id already present, so an offset shift can't duplicate a row.
      final existing = _posts.map((p) => p.id).toSet();
      final fresh = page.posts
          .where((p) => !_removing.contains(p.id) && !existing.contains(p.id))
          .toList();
      setState(() {
        _posts = [..._posts, ...fresh];
        if (page.hasMore) _page += 1;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e, st) {
      reportError(e, st, reason: 'bookmarks:load-more');
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _onBookmarkChanged(String postId, bool stillBookmarked) {
    if (stillBookmarked) return;
    if (_removing.contains(postId)) return;
    setState(() => _removing.add(postId));
    // Let the fade-out animation play, then drop the entry so the next page
    // cursor stays sound (no shifted indices, no key collisions).
    Future<void>.delayed(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      setState(() {
        _posts.removeWhere((p) => p.id == postId);
        _removing.remove(postId);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        backgroundColor: ZveltTokens.bg,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(AppIcons.angle_small_left, size: 18),
          color: ZveltTokens.text2,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'My Bookmarks',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: ZveltTokens.text,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: ZveltTokens.brand))
            : _error != null
                ? ZveltErrorState(
                    tier: _error!.isNetworkError
                        ? ZveltErrorTier.network
                        : (_error!.isAuthError
                            ? ZveltErrorTier.auth
                            : (_error!.isServerError
                                ? ZveltErrorTier.server
                                : ZveltErrorTier.generic)),
                    title: "Couldn't load bookmarks",
                    onRetry: _load,
                  )
                : _posts.isEmpty
                    ? RefreshIndicator(
                        color: ZveltTokens.brand,
                        onRefresh: _load,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 40),
                            ZveltEmptyState(
                              icon: AppIcons.bookmark,
                              title: 'No saved posts yet',
                              subtitle:
                                  'Tap the bookmark icon on any post to save it for later.',
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        color: ZveltTokens.brand,
                        onRefresh: _load,
                        child: CustomScrollView(
                          controller: _scrollController,
                          slivers: [
                            SliverPadding(
                              padding: EdgeInsets.only(top: 8, bottom: mq.padding.bottom + 24),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    if (index < _posts.length) {
                                      final post = _posts[index];
                                      final fading = _removing.contains(post.id);
                                      return AnimatedOpacity(
                                        duration: const Duration(milliseconds: 250),
                                        opacity: fading ? 0.0 : 1.0,
                                        child: AnimatedSize(
                                          duration: const Duration(milliseconds: 250),
                                          alignment: Alignment.topCenter,
                                          child: fading
                                              ? const SizedBox(width: double.infinity)
                                              : SocialFeedPostCard(
                                                  key: ValueKey('bookmark-${post.id}'),
                                                  post: post,
                                                  service: _service,
                                                  onLike: () {},
                                                  initiallyBookmarked: true,
                                                  onBookmarkChanged: (stillBookmarked) =>
                                                      _onBookmarkChanged(post.id, stillBookmarked),
                                                ),
                                        ),
                                      );
                                    }
                                    // Footer slot.
                                    if (_loadingMore) {
                                      return const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 16),
                                        child: Center(
                                          child: CircularProgressIndicator(color: ZveltTokens.brand),
                                        ),
                                      );
                                    }
                                    if (!_hasMore) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 20),
                                        child: Center(
                                          child: Text(
                                            "You've reached the end",
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: ZveltTokens.text2,
                                              letterSpacing: 0.4,
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  },
                                  childCount: _posts.length + 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
      ),
    );
  }
}

