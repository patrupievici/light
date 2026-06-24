import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/services/settings_store.dart';

// Guards the kg<->lb conversion + display that UnitsNotifier exposes app-wide.
// The conversion helpers read system.value, which we set directly (no
// SharedPreferences needed) to test both unit systems deterministically.
void main() {
  test('metric: weight displays kg, conversions are identity', () {
    UnitsNotifier.system.value = 'metric';
    expect(UnitsNotifier.isImperial, isFalse);
    expect(UnitsNotifier.weight(80), '80 kg');
    expect(UnitsNotifier.kgToDisplay(80), 80);
    expect(UnitsNotifier.displayToKg(80), 80);
  });

  test('imperial: weight displays lb, kg<->lb roundtrips losslessly', () {
    UnitsNotifier.system.value = 'imperial';
    expect(UnitsNotifier.isImperial, isTrue);
    expect(UnitsNotifier.weight(100), '${(100 * 2.20462).round()} lb');

    final displayed = UnitsNotifier.kgToDisplay(100);
    expect(displayed, closeTo(220.462, 0.01));
    // Canonical storage is always kg — converting back must recover the input.
    expect(UnitsNotifier.displayToKg(displayed), closeTo(100, 0.0001));

    // reset so other suites see the default
    UnitsNotifier.system.value = 'metric';
  });
}
