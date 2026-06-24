import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('ZveltApp builds with MaterialApp root', (tester) async {
    await tester.pumpWidget(const ZveltApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
