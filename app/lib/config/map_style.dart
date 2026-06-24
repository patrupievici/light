import 'package:flutter/material.dart';
import '../theme/zvelt_tokens.dart';

/// Centralised map look so all route maps stay consistent and a Tier-2 custom
/// vector style is a one-line swap later.

/// Tier-1 light minimal basemap (Carto Positron). Same provider the app already
/// used for the dark style — just the light variant.
const String kMapTileUrl =
    'https://cartodb-basemaps-a.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png';

/// Route polyline gradient, start → finish: green → brand orange.
const List<Color> kRouteGradient = [Color(0xFF2EC27E), ZveltTokens.brand];
