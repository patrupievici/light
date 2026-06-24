/// Etichete de porție și unități pentru UI (ouă, felii, „servings”) — independent de sursa datelor.
class NutritionFoodLabels {
  NutritionFoodLabels._();

  /// Porție implicită pentru alimente generice (ex. USDA): ouă ~50 g.
  static ({String portionUnitKey, double? servingGrams, String? servingLabel}) genericPortionHints(
    String productName, [
    String? servingSizeHint,
  ]) {
    final unitKey = portionUnitKeyFromProduct(productName, servingSizeHint);
    if (unitKey == 'egg') {
      return (portionUnitKey: 'egg', servingGrams: 50, servingLabel: '1 medium egg (~50 g)');
    }
    return (portionUnitKey: unitKey, servingGrams: null, servingLabel: null);
  }

  /// Cheie unitate pentru slider-uri (1 egg / 2 slices).
  static String portionUnitKeyFromProduct(String productName, String? servingSizeRaw) {
    final n = productName.toLowerCase();
    final s = (servingSizeRaw ?? '').toLowerCase();
    if ((n.contains('egg') && !n.contains('eggplant')) || s.contains('egg')) return 'egg';
    if (n.contains('slice') || s.contains('slice')) return 'slice';
    if (n.contains('waffle') || s.contains('waffle')) return 'waffle';
    if (s.contains('biscuit') || s.contains('cookie') || n.contains('cookie')) return 'cookie';
    return 'serving';
  }

  static String formatUnitCount(double count, String unitKey) {
    String fmtCount(double c) {
      if ((c - c.round()).abs() < 0.001) return c.round().toString();
      var s = c.toStringAsFixed(2);
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
      return s;
    }

    final c = count;
    final r = c.round();
    final whole = (c - r).abs() < 0.001;
    final disp = fmtCount(c);

    switch (unitKey) {
      case 'egg':
        return whole && r == 1 ? '1 egg' : '$disp eggs';
      case 'slice':
        return whole && r == 1 ? '1 slice' : '$disp slices';
      case 'waffle':
        return whole && r == 1 ? '1 waffle' : '$disp waffles';
      case 'cookie':
        return whole && r == 1 ? '1 cookie' : '$disp cookies';
      default:
        return whole && r == 1 ? '1 serving' : '$disp servings';
    }
  }
}
