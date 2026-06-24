import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/widgets/map_metrics_overlay.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Mirrors real usage: positioned inside a Stack over the map.
          body: Stack(children: [Positioned(top: 12, left: 12, child: child)]),
        ),
      ),
    );
  }

  testWidgets('renders all four cards with formatted values', (tester) async {
    await pump(
      tester,
      const MapMetricsOverlay(
        distanceM: 8420,
        elapsed: Duration(minutes: 46, seconds: 21),
        elevGainM: 132,
      ),
    );

    expect(find.text('DISTANCE'), findsOneWidget);
    expect(find.text('8.42'), findsOneWidget);
    expect(find.text('km'), findsOneWidget);
    expect(find.text('PACE'), findsOneWidget);
    expect(find.text('5:30'), findsOneWidget); // 46:21 over 8.42 km
    expect(find.text('ELEV. GAIN'), findsOneWidget);
    expect(find.text('132'), findsOneWidget);
    expect(find.text('DURATION'), findsOneWidget);
    expect(find.text('46:21'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fresh session: meters, no pace, elevation hidden when null',
      (tester) async {
    await pump(
      tester,
      const MapMetricsOverlay(distanceM: 0, elapsed: Duration.zero),
    );

    expect(find.text('0'), findsOneWidget); // distance in meters
    expect(find.text('m'), findsOneWidget);
    expect(find.text('--'), findsOneWidget); // pace placeholder
    expect(find.text('ELEV. GAIN'), findsNothing);
    expect(find.text('0:00'), findsOneWidget); // duration
    expect(tester.takeException(), isNull);
  });
}
