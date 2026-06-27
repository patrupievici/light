// Pins the SocialChallenge JSON contract — especially the `isOfficial` flag the
// Discover ("Camere publice") screen relies on to split official rooms from
// community challenges.
import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/models/social_challenge.dart';

Map<String, dynamic> _base({bool? isOfficial}) => {
      'id': 'c1',
      'kind': 'pullUps',
      'visibility': 'public',
      'durationDays': 30,
      'createdAt': '2026-06-20T10:00:00.000Z',
      'endsAt': '2099-12-31T00:00:00.000Z',
      'participantsCount': 42,
      'joined': false,
      if (isOfficial != null) 'isOfficial': isOfficial,
    };

void main() {
  group('SocialChallenge.isOfficial', () {
    test('parses an official public room', () {
      final c = SocialChallenge.fromJson(_base(isOfficial: true))!;
      expect(c.isOfficial, isTrue);
      expect(c.visibility, 'public');
      expect(c.participantsCount, 42);
    });

    test('defaults to false when the server omits isOfficial', () {
      final c = SocialChallenge.fromJson(_base())!;
      expect(c.isOfficial, isFalse);
    });

    test('survives a toJson → fromJson round trip', () {
      final original = SocialChallenge.fromJson(_base(isOfficial: true))!;
      final restored = SocialChallenge.fromJson(original.toJson())!;
      expect(restored.isOfficial, isTrue);
      expect(restored.participantsCount, 42);
    });

    test('copyWith preserves isOfficial', () {
      final c = SocialChallenge.fromJson(_base(isOfficial: true))!;
      expect(c.copyWith(joined: true).isOfficial, isTrue);
    });
  });
}
