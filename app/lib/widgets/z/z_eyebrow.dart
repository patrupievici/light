import 'package:flutter/material.dart';

import '../../theme/zvelt_tokens.dart';

/// Short uppercase label rendered in IBM Plex Mono — the "eyebrow" text
/// that sits above section titles. Mirrors the `.z-eyebrow` CSS utility.
///
/// Example use:
///   ```dart
///   const ZEyebrow('TODAY · 6 LIFTS · 48 MIN'),
///   ZSizedBox.s1,
///   const Text('Push · Day 12', style: ZType.h3),
///   ```
class ZEyebrow extends StatelessWidget {
  const ZEyebrow(this.text, {super.key, this.color});

  final String text;
  /// Defaults to [ZveltTokens.text3]. Override for branded eyebrows.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: ZType.eyebrow.copyWith(color: color),
    );
  }
}
