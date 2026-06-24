import 'dart:convert';
import 'package:zvelt_app/theme/app_icons.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config/api_config.dart' show v1Base, mediaAbsoluteUrl;
import '../../services/_crash_reporter.dart';
import '../../services/auth_service.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/zvelt_empty_state.dart';
import '../../widgets/zvelt_error_state.dart';
import '../../widgets/zvelt_network_image.dart';
import 'post_detail_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  String _filter = 'recent';

  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  bool _hasMore = true;
  bool _error = false;
  int _page = 1;
  bool _fetchingMore = false;

  final _scrollCtrl = ScrollController();

  // Decorative gallery palettes — intentional exception to the single-orange-
  // signal rule. These hues back post thumbnails only (never UI signals such as
  // active states / KPIs / CTAs), so the multi-color ramp is allowed here purely
  // for visual variety. Do not reuse these colors for real UI signals.
  static const _palettes = [
    [ZveltTokens.brand, ZveltTokens.brandDeep],
    [Color(0xFF4DA3FF), Color(0xFF2563EB)],
    [Color(0xFF22C55E), Color(0xFF15803D)],
    [Color(0xFFA855F7), Color(0xFF6D28D9)],
    [Color(0xFFF59E0B), Color(0xFFD97706)],
    [Color(0xFFEC4899), Color(0xFFBE185D)],
    [Color(0xFF06B6D4), Color(0xFF0E7490)],
  ];

  static const _timeout = Duration(seconds: 22);

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 200 &&
        !_fetchingMore &&
        _hasMore) {
      _loadPosts();
    }
  }

  Future<void> _loadPosts({bool reset = false}) async {
    if (_fetchingMore) return;
    if (reset) {
      _posts = [];
      _page = 1;
      _hasMore = true;
      _loading = true;
      _error = false;
    }
    setState(() => _fetchingMore = true);
    final currentPage = _page;
    final currentFilter = _filter;
    try {
      final token = await AuthService().getAccessToken();
      final sort = currentFilter == 'popular' ? 'popular' : 'recent';
      final mine = currentFilter == 'mine' ? 'true' : 'false';
      final uri = Uri.parse(
          '$v1Base/posts?sort=$sort&mine=$mine&page=$currentPage&limit=20');

      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final res =
          await http.get(uri, headers: headers).timeout(_timeout);

      if (!mounted) return;

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final rawList = (body['data'] as List<dynamic>? ?? []);
        final newPosts = rawList
            .map((e) => _normalisePost(e as Map<String, dynamic>))
            .toList();

        setState(() {
          if (reset || currentPage == 1) {
            _posts = newPosts;
          } else {
            _posts = [..._posts, ...newPosts];
          }
          _hasMore = newPosts.length >= 20;
          if (_hasMore) _page = currentPage + 1;
          _loading = false;
        });
      } else {
        // Non-200: an error is NOT an empty gallery — without _error the
        // user was told 'No posts yet · Be the first to share!' on a 500.
        setState(() {
          _loading = false;
          _hasMore = false;
          if (_posts.isEmpty) _error = true;
        });
      }
    } catch (e, st) {
      reportError(e, st, reason: 'gallery:load-posts');
      if (mounted) {
        setState(() {
          _loading = false;
          _hasMore = false;
          if (_posts.isEmpty) _error = true;
        });
      }
    } finally {
      if (mounted) setState(() => _fetchingMore = false);
    }
  }

  /// Normalise varying API shapes into a flat map the grid can use.
  Map<String, dynamic> _normalisePost(Map<String, dynamic> p) {
    final user = p['user'] as Map<String, dynamic>? ?? {};
    final profile = user['profile'] as Map<String, dynamic>? ?? {};
    final count = p['_count'] as Map<String, dynamic>? ?? {};

    final displayName = (profile['displayName'] as String?)?.trim() ??
        (user['username'] as String?)?.trim() ??
        'User';

    return {
      'id': p['id'] as String? ?? '',
      'imageUrl': p['imageUrl'] as String?,
      'caption': p['caption'] as String?,
      'userId': p['userId'] as String? ?? '',
      'authorName': displayName,
      'likes': (count['likes'] as int?) ?? 0,
      'comments': (count['comments'] as int?) ?? 0,
      'createdAt': p['createdAt'] as String? ?? '',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            _buildFilterPills(),
            Expanded(
              child: Stack(
                children: [
                  _buildGrid(),
                  // Dead "POST YOUR PROGRESS" CTA removed — the only way to
                  // post on v1.0 is via post_workout_screen after completing
                  // a workout. The button used to pop the gallery and show a
                  // "Go to Feed to post" snackbar which led nowhere.
                  // _buildPostCTA(mq),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          ZveltTokens.s2, ZveltTokens.s1, ZveltTokens.s4, 0),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Back',
            child: IconButton(
              icon: const Icon(AppIcons.angle_small_left, size: 18),
              color: ZveltTokens.text2,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              'EXPLORE MOMENTUM',
              style: TextStyle(
                fontFamily: ZveltTokens.fontPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                color: ZveltTokens.text,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ZveltTokens.brand.withValues(alpha: 0.12),
              border: Border.all(color: ZveltTokens.brand.withValues(alpha: 0.25)),
            ),
            child: const Icon(AppIcons.flame,
                color: ZveltTokens.brand3, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPills() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          ZveltTokens.s4, ZveltTokens.s3, ZveltTokens.s4, ZveltTokens.s3),
      child: Row(
        children: ['recent', 'popular', 'mine'].map((f) {
          final sel = _filter == f;
          return Padding(
            padding: const EdgeInsets.only(right: ZveltTokens.s2),
            child: GestureDetector(
              onTap: () {
                if (_filter == f) return;
                setState(() => _filter = f);
                _loadPosts(reset: true);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4),
                decoration: BoxDecoration(
                  color: sel ? ZveltTokens.text : ZveltTokens.surface,
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                  border: sel ? null : Border.all(color: ZveltTokens.border),
                ),
                alignment: Alignment.center,
                child: Text(
                  f.toUpperCase(),
                  style: TextStyle(
                    color: sel ? ZveltTokens.bg : ZveltTokens.text2,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                    fontFamily: ZveltTokens.fontPrimary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGrid() {
    // Loading state (first load, no posts yet).
    if (_loading && _posts.isEmpty) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(ZveltTokens.s3, 0, ZveltTokens.s3, 120),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 1,
        ),
        itemCount: 12,
        itemBuilder: (_, i) => ClipRRect(
          borderRadius: BorderRadius.circular(ZveltTokens.rSm),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: ZveltTokens.surface,
              borderRadius: BorderRadius.circular(ZveltTokens.rSm),
            ),
            child: const _ShimmerBox(),
          ),
        ),
      );
    }

    // Honest error state — only a successful 200 with zero posts gets the
    // 'No posts yet' copy.
    if (!_loading && _error && _posts.isEmpty) {
      return ZveltErrorState(
        tier: ZveltErrorTier.network,
        title: 'Could not load the gallery',
        message: 'Check your connection and try again.',
        onRetry: () {
          setState(() => _error = false);
          _loadPosts(reset: true);
        },
      );
    }

    // Empty state after load.
    if (!_loading && _posts.isEmpty) {
      return const ZveltEmptyState(
        icon: AppIcons.picture,
        title: 'No posts yet',
        subtitle: 'Be the first to share your progress!',
      );
    }

    return GridView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(ZveltTokens.s3, 0, ZveltTokens.s3, 120),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 1,
      ),
      itemCount: _posts.length + (_hasMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= _posts.length) {
          // Pagination loader at the bottom.
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(ZveltTokens.s3),
              child: CircularProgressIndicator(
                  color: ZveltTokens.brand, strokeWidth: 2),
            ),
          );
        }
        final post = _posts[i];
        final postId = post['id'] as String?;
        final imageUrl = post['imageUrl'] as String?;
        final authorName = post['authorName'] as String? ?? '';
        final likes = post['likes'] as int? ?? 0;
        final palette = _palettes[i % _palettes.length];
        final initials = authorName.isNotEmpty
            ? authorName.trim().split(RegExp(r'\s+')).map((w) => w[0]).take(2).join().toUpperCase()
            : '?';

        // Tiles open the post — the explore grid used to be look-but-don't-
        // touch: you could see thumbnails and like counts but not open,
        // like, or comment on anything.
        return GestureDetector(
          onTap: (postId == null || postId.isEmpty)
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PostDetailScreen(postId: postId),
                    ),
                  ),
          child: _buildTile(imageUrl, palette, initials, likes),
        );
      },
    );
  }

  Widget _buildTile(
      String? imageUrl, List<Color> palette, String initials, int likes) {
    return ClipRRect(
          borderRadius: BorderRadius.circular(ZveltTokens.rSm),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Image or gradient placeholder.
              if (imageUrl != null && imageUrl.isNotEmpty)
                Semantics(
                  image: true,
                  label: 'Progress photo by $initials',
                  child: ZveltNetworkImage(
                    url: mediaAbsoluteUrl(imageUrl),
                    fit: BoxFit.cover,
                    cacheWidth: ZveltImageCacheWidth.galleryGrid,
                    errorWidget: (_) =>
                        _gradientPlaceholder(palette, initials),
                  ),
                )
              else
                _gradientPlaceholder(palette, initials),

              // Like badge.
              if (likes > 0)
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(AppIcons.heart,
                            color: Colors.redAccent, size: 9),
                        const SizedBox(width: 3),
                        Text(
                          '$likes',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
  }

  Widget _gradientPlaceholder(List<Color> palette, String initials) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: const Alignment(-0.5, -1),
              end: const Alignment(0.5, 1),
              colors: palette,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, 0.4),
              radius: 0.8,
              colors: [Colors.black.withValues(alpha: 0.35), Colors.transparent],
            ),
          ),
        ),
        Center(
          child: Opacity(
            opacity: 0.18,
            child: CustomPaint(
                size: const Size(36, 52), painter: _SilhouettePainter()),
          ),
        ),
        Positioned(
          top: 6,
          left: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(ZveltTokens.rPill),
            ),
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.8,
              ),
            ),
          ),
        ),
      ],
    );
  }

}

// ── shimmer placeholder ───────────────────────────────────────────────────────

class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox();

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        decoration: BoxDecoration(
          color: Color.lerp(
            ZveltTokens.surface,
            ZveltTokens.surface2,
            _anim.value,
          ),
        ),
      ),
    );
  }
}

// ── silhouette painter (unchanged) ────────────────────────────────────────────

class _SilhouettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white;
    canvas.drawCircle(
        Offset(size.width / 2, size.height * 0.15), size.width * 0.22, p);
    final body = Path()
      ..moveTo(size.width * 0.12, size.height * 0.32)
      ..lineTo(size.width * 0.88, size.height * 0.32)
      ..lineTo(size.width * 0.82, size.height * 0.68)
      ..quadraticBezierTo(
          size.width / 2, size.height * 0.78, size.width * 0.18, size.height * 0.68)
      ..close();
    canvas.drawPath(body, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
