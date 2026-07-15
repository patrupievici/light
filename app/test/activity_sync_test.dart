import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zvelt_app/models/activity_kind.dart';
import 'package:zvelt_app/services/activity_calendar_store.dart';
import 'package:zvelt_app/services/activity_service.dart';
import 'package:zvelt_app/services/auth_service.dart';

class _FakeAuth extends AuthService {
  @override
  Future<String?> getCurrentUserId() async => 'sync-user';
}

String _ymd(DateTime date) {
  final local = date.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('server and client cycling aliases map to the same kind', () {
    expect(ActivityKind.tryParse('ride'), ActivityKind.cycle);
    expect(ActivityKind.tryParse('bike'), ActivityKind.cycle);
    expect(ActivityService.canonicalActivityType('bike'), 'ride');
    expect(ActivityService.canonicalActivityType('cycle'), 'ride');
  });

  test('server history replaces one matching local upload without duplicates',
      () async {
    final store = ActivityCalendarStore(auth: _FakeAuth());
    final startedAt = DateTime(2026, 7, 1, 8);
    final day = _ymd(startedAt);
    await store.addManualSession(
      day,
      ManualCardioSession(
        id: startedAt.millisecondsSinceEpoch.toString(),
        kind: ActivityKind.cycle,
        distanceKm: 10,
        durationMin: 60,
      ),
    );

    final item = ActivityFeedItem(
      id: '123e4567-e89b-42d3-a456-426614174000',
      type: 'ride',
      source: 'gps',
      startedAt: startedAt,
      // Server recomputation can differ from the phone estimate; start time
      // still identifies this as the same physical session.
      distanceM: 10400,
      durationS: 3600,
    );
    expect(await store.mergeServerCardioActivities([item]), 1);
    expect(await store.mergeServerCardioActivities([item]), 0);

    final sessions = (await store.loadManualSessions())[day]!;
    expect(sessions, hasLength(1));
    expect(sessions.single.id, item.id);
    expect(sessions.single.kind, ActivityKind.cycle);
  });

  test('one server row only replaces one of two identical local sessions',
      () async {
    final store = ActivityCalendarStore(auth: _FakeAuth());
    final startedAt = DateTime(2026, 7, 2, 8);
    final day = _ymd(startedAt);
    for (final id in ['local-1', 'local-2']) {
      await store.addManualSession(
        day,
        ManualCardioSession(
          id: id,
          kind: ActivityKind.run,
          distanceKm: 5,
          durationMin: 30,
        ),
      );
    }

    await store.mergeServerCardioActivities([
      ActivityFeedItem(
        id: '123e4567-e89b-42d3-a456-426614174001',
        type: 'run',
        source: 'gps',
        startedAt: startedAt,
        distanceM: 5000,
        durationS: 1800,
      ),
    ]);

    final sessions = (await store.loadManualSessions())[day]!;
    expect(sessions, hasLength(2));
    expect(
      sessions.where((session) => session.id!.startsWith('123e')),
      hasLength(1),
    );
  });
}
