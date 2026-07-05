/// Model pentru postările din feed / GET /v1/posts/:id
class SocialFeedSet {
  const SocialFeedSet({required this.weightKg, required this.reps, this.rpe, required this.tag});
  final double weightKg;
  final int reps;
  final double? rpe;
  final String tag;

  static double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
  static int _i(dynamic v) => v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0;

  static SocialFeedSet fromJson(Map<String, dynamic> j) => SocialFeedSet(
    weightKg: _d(j['weightKg']),
    reps: _i(j['reps']),
    rpe: j['rpe'] != null ? _d(j['rpe']) : null,
    tag: j['tag'] as String? ?? 'WORK',
  );
}

class SocialFeedExerciseLine {
  const SocialFeedExerciseLine({required this.name, required this.sets});
  final String name;
  final List<SocialFeedSet> sets;

  static SocialFeedExerciseLine fromJson(Map<String, dynamic> j) {
    final exercise = j['exercise'] as Map<String, dynamic>? ?? {};
    final sets = (j['sets'] as List<dynamic>? ?? [])
        .map((s) => SocialFeedSet.fromJson(s as Map<String, dynamic>))
        .where((s) => s.tag == 'WORK')
        .toList();
    return SocialFeedExerciseLine(
      name: exercise['name'] as String? ?? 'Exercise',
      sets: sets,
    );
  }
}

/// Per-post audience scope. Mirrors backend `visibility` enum
/// (public | friends | private). Defaults to FRIENDS per CLAUDE.md
/// privacy-by-default rule.
enum PostVisibility { public, friends, private }

PostVisibility _parseVisibility(dynamic raw) {
  if (raw is! String) return PostVisibility.friends;
  switch (raw.toLowerCase().trim()) {
    case 'public':
      return PostVisibility.public;
    case 'private':
    case 'only_me':
    case 'self':
      return PostVisibility.private;
    case 'friends':
    case 'friends_only':
    default:
      return PostVisibility.friends;
  }
}

class SocialFeedPost {
  const SocialFeedPost({
    required this.id,
    required this.userId,
    this.authorName,
    this.authorUsername,
    required this.caption,
    required this.imageUrl,
    required this.createdAt,
    required this.exercises,
    required this.likeCount,
    required this.commentCount,
    this.likedByMe = false,
    required this.hideWeights,
    required this.hideReps,
    this.visibility = PostVisibility.friends,
  });

  final String id;
  final String userId;
  final String? authorName;
  final String? authorUsername;
  final String? caption;
  /// Cale relativă `/uploads/...` sau URL absolut.
  final String? imageUrl;
  final DateTime createdAt;
  final List<SocialFeedExerciseLine> exercises;
  final int likeCount;
  final int commentCount;
  /// Whether the CURRENT viewer already liked this post. Backend emits
  /// `likedByMe` (camelCase) on /feed, /:id and the gallery list; older
  /// responses without the key default to false.
  final bool likedByMe;
  final bool hideWeights;
  final bool hideReps;
  final PostVisibility visibility;

  static SocialFeedPost fromJson(Map<String, dynamic> j) {
    final workout = j['workout'] as Map<String, dynamic>?;
    final privacy = j['privacySettings'] as Map<String, dynamic>?;
    final count = j['_count'] as Map<String, dynamic>?;
    final exercises = (workout?['exercises'] as List<dynamic>? ?? [])
        .map((e) => SocialFeedExerciseLine.fromJson(e as Map<String, dynamic>))
        .toList();
    
    // Parse author name + username from user relation
    String? authorName;
    String? authorUsername;
    final user = j['user'] as Map<String, dynamic>?;
    if (user != null) {
      final profile = user['profile'] as Map<String, dynamic>?;
      if (profile != null) {
        final displayName = profile['displayName'] as String?;
        final username = profile['username'] as String?;
        if (displayName != null && displayName.trim().isNotEmpty) {
          authorName = displayName.trim();
        }
        if (username != null && username.trim().isNotEmpty) {
          authorUsername = username.trim();
        }
      }
    }

    // Visibility may live on the post root (`visibility`) or inside
    // privacySettings (`visibility` / `audience`). We tolerate both.
    final visibilityRaw = j['visibility'] ?? privacy?['visibility'] ?? privacy?['audience'];

    return SocialFeedPost(
      id: j['id'] as String,
      userId: j['userId'] as String,
      authorName: authorName,
      authorUsername: authorUsername,
      caption: j['caption'] as String?,
      imageUrl: j['imageUrl'] as String?,
      createdAt: DateTime.parse(j['createdAt'] as String),
      exercises: exercises,
      likeCount: count?['likes'] as int? ?? 0,
      commentCount: count?['comments'] as int? ?? 0,
      likedByMe: j['likedByMe'] as bool? ?? false,
      hideWeights: privacy?['hideWeights'] as bool? ?? false,
      hideReps: privacy?['hideReps'] as bool? ?? false,
      visibility: _parseVisibility(visibilityRaw),
    );
  }

  SocialFeedPost copyWith({
    int? likeCount,
    int? commentCount,
    bool? likedByMe,
  }) {
    return SocialFeedPost(
      id: id,
      userId: userId,
      authorName: authorName,
      authorUsername: authorUsername,
      caption: caption,
      imageUrl: imageUrl,
      createdAt: createdAt,
      exercises: exercises,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      likedByMe: likedByMe ?? this.likedByMe,
      hideWeights: hideWeights,
      hideReps: hideReps,
      visibility: visibility,
    );
  }
}
