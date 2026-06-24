// Widget contract test for SyncStatusChip — the small offline-sync indicator
// surfaced in the workout tracker AppBar.
//
// The risky bits this pins down:
//  * synced (count 0) vs pending (count > 0) label + which cloud glyph shows;
//  * the optional onRetry handler: only then is the chip a tappable button with
//    a trailing retry glyph, and tapping it must invoke the callback;
//  * without onRetry the chip stays a plain, non-interactive pill (no extra
//    tap target / retry glyph) — preserving its original behaviour.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:zvelt_app/widgets/sync_status_chip.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('SyncStatusChip', () {
    testWidgets('count 0 → "Synced" with cloud_check glyph', (tester) async {
      await tester.pumpWidget(_host(const SyncStatusChip()));
      expect(find.text('Synced'), findsOneWidget);
      expect(find.byIcon(AppIcons.cloud_check), findsOneWidget);
      expect(find.byIcon(AppIcons.cloud_upload), findsNothing);
    });

    testWidgets('count > 0 → "Pending N" with cloud_upload glyph', (tester) async {
      await tester.pumpWidget(_host(const SyncStatusChip(pendingCount: 3)));
      expect(find.text('Pending 3'), findsOneWidget);
      expect(find.byIcon(AppIcons.cloud_upload), findsOneWidget);
      expect(find.byIcon(AppIcons.cloud_check), findsNothing);
    });

    testWidgets('no onRetry → no retry glyph and not a button', (tester) async {
      await tester.pumpWidget(_host(const SyncStatusChip(pendingCount: 2)));
      expect(find.byIcon(AppIcons.arrows_repeat), findsNothing);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('onRetry → shows retry glyph and tapping invokes the callback',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(SyncStatusChip(pendingCount: 2, onRetry: () => taps++)),
      );
      expect(find.byIcon(AppIcons.arrows_repeat), findsOneWidget);

      await tester.tap(find.byType(SyncStatusChip));
      await tester.pump();
      expect(taps, 1);
    });
  });
}
