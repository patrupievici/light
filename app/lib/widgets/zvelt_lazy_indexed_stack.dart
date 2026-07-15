import 'package:flutter/material.dart';

/// Lazily builds tab pages while keeping visited pages mounted at stable
/// positions. Fresh widget configurations let inherited theme changes reach
/// every mounted tab without discarding its State.
class ZveltLazyIndexedStack extends StatelessWidget {
  const ZveltLazyIndexedStack({
    super.key,
    required this.index,
    required this.built,
    required this.itemBuilder,
  });

  final int index;
  final List<bool> built;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    assert(index >= 0 && index < built.length);

    return IndexedStack(
      index: index,
      children: [
        for (var i = 0; i < built.length; i++)
          if (built[i]) itemBuilder(context, i) else const SizedBox.shrink(),
      ],
    );
  }
}
