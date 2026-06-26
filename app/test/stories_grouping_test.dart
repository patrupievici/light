// Pins the pure grouping logic that turns a newest-first stories feed into the
// per-author playback groups the tray + viewer consume. The ordering rules that
// MUST hold:
//   * Stories within an author play oldest → newest (IG order), even though the
//     feed delivers them newest-first.
//   * Authors keep newest-author-first order from the feed...
//   * ...except the current user's own group, which is pulled to the very front.
import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/services/stories_service.dart';

Story _story(String id, String userId, {String? name, DateTime? createdAt}) => Story(
      id: id,
      userId: userId,
      authorName: name ?? userId,
      caption: null,
      imageUrl: null,
      location: null,
      expiresAt: DateTime.parse('2999-01-01T00:00:00.000Z'),
      createdAt: createdAt ?? DateTime.parse('2026-06-20T10:00:00.000Z'),
      likeCount: 0,
      likedByMe: false,
    );

void main() {
  group('groupStoriesByAuthor', () {
    test('empty feed → no groups', () {
      expect(groupStoriesByAuthor(const [], meId: 'me'), isEmpty);
    });

    test('one author: stories are re-ordered oldest → newest for playback', () {
      // Feed is newest-first: s3, s2, s1.
      final feed = [
        _story('s3', 'u1', createdAt: DateTime.parse('2026-06-20T12:00:00.000Z')),
        _story('s2', 'u1', createdAt: DateTime.parse('2026-06-20T11:00:00.000Z')),
        _story('s1', 'u1', createdAt: DateTime.parse('2026-06-20T10:00:00.000Z')),
      ];
      final groups = groupStoriesByAuthor(feed, meId: 'meX');
      expect(groups, hasLength(1));
      expect(groups.single.stories.map((s) => s.id).toList(), ['s1', 's2', 's3']);
      expect(groups.single.newest.id, 's3');
      expect(groups.single.isMe, isFalse);
    });

    test('multiple authors keep newest-author-first encounter order', () {
      final feed = [
        _story('a1', 'alice'), // alice encountered first (newest)
        _story('b1', 'bob'),
        _story('a2', 'alice'),
      ];
      final groups = groupStoriesByAuthor(feed, meId: 'meX');
      expect(groups.map((g) => g.userId).toList(), ['alice', 'bob']);
      // alice's two stories grouped + ordered oldest→newest (a2 older in feed
      // position so newest is a1).
      final alice = groups.first;
      expect(alice.stories.map((s) => s.id).toList(), ['a2', 'a1']);
    });

    test("the current user's own group is pulled to the front", () {
      final feed = [
        _story('a1', 'alice'),
        _story('m1', 'me'),
        _story('b1', 'bob'),
      ];
      final groups = groupStoriesByAuthor(feed, meId: 'me');
      expect(groups.first.userId, 'me');
      expect(groups.first.isMe, isTrue);
      // The others keep their relative order behind "me".
      expect(groups.map((g) => g.userId).toList(), ['me', 'alice', 'bob']);
    });

    test('thumbUrl picks the newest story that has a photo', () {
      final feed = [
        Story(
          id: 'p2', userId: 'u1', authorName: 'u1', caption: null,
          imageUrl: '/uploads/stories/p2.jpg', location: null,
          expiresAt: DateTime.parse('2999-01-01T00:00:00.000Z'),
          createdAt: DateTime.parse('2026-06-20T12:00:00.000Z'),
          likeCount: 0, likedByMe: false,
        ),
        _story('p1', 'u1', createdAt: DateTime.parse('2026-06-20T11:00:00.000Z')),
      ];
      final g = groupStoriesByAuthor(feed, meId: 'meX').single;
      expect(g.thumbUrl, '/uploads/stories/p2.jpg');
    });
  });
}
