import 'package:flutter/foundation.dart' show kIsWeb;

import 'platform_info_io.dart'
    if (dart.library.html) 'platform_info_web.dart';

/// True when running on Android device/emulator.
bool get isAndroid => !kIsWeb && isAndroidIo;

/// True when running on iOS device/simulator.
bool get isIos => !kIsWeb && isIosIo;

