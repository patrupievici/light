import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Global test harness setup (auto-loaded by `flutter test`).
///
/// The app's typography now comes from Manrope via `google_fonts`, which
/// fetches the font over the network at runtime. The test sandbox has no
/// network, so leaving fetching on makes every widget test throw
/// "Failed to load font with url ...". Disabling runtime fetching makes
/// google_fonts fall back silently to the default font — deterministic and
/// offline-safe for widget/golden tests.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  await testMain();
}
