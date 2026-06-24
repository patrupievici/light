import 'package:cached_network_image/cached_network_image.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/map_style.dart';
import '../models/workout_result.dart';
import '../theme/zvelt_tokens.dart';

/// A fixed-size widget designed to be captured via [screenshot] package.
/// Caller wraps with RepaintBoundary + ScreenshotController.
class ActivityShareCard extends StatelessWidget {
  final WorkoutResult result;

  /// 'story' → 1080×1920 (9:16), 'post' → 1080×1080 (1:1)
  final String format;

  const ActivityShareCard({
    super.key,
    required this.result,
    this.format = 'story',
  });

  bool get _isStory => format == 'story';

  double get _aspectRatio => _isStory ? 9 / 16 : 1;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Map background
          if (result.activityType.isGps && result.routePoints.isNotEmpty)
            _MapBackground(routePoints: result.routePoints)
          else
            _WorkoutBackground(),

          // Dark gradient overlay
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x33000000),
                  Color(0xCC000000),
                ],
                stops: [0.4, 1.0],
              ),
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(ZveltTokens.s6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TopBar(result: result),
                if (result.activityType.isGps && result.routePoints.isNotEmpty) ...[
                  // GPS: metric cards overlaid on the map (like the run detail).
                  const SizedBox(height: 14),
                  _ShareMetricsOverlay(result: result),
                  const Spacer(),
                ] else ...[
                  // Non-GPS workout: keep the bottom stats block.
                  const Spacer(),
                  _StatsBlock(result: result, isStory: _isStory),
                  if (_isStory) const SizedBox(height: 20),
                ],
                _BottomBranding(result: result),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MapBackground extends StatelessWidget {
  final List<LatLng> routePoints;

  const _MapBackground({required this.routePoints});

  @override
  Widget build(BuildContext context) {
    final bounds = LatLngBounds.fromPoints(routePoints);
    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(32),
        ),
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
      ),
      children: [
        TileLayer(
          urlTemplate: kMapTileUrl,
          userAgentPackageName: 'com.zvelt.app',
          retinaMode: true,
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: routePoints,
              strokeWidth: 3.5,
              gradientColors: kRouteGradient,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: routePoints.first,
              width: 14,
              height: 14,
              child: Container(
                decoration: BoxDecoration(
                  color: ZveltTokens.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
            Marker(
              point: routePoints.last,
              width: 14,
              height: 14,
              child: Container(
                decoration: BoxDecoration(
                  color: ZveltTokens.brand,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Metric cards (Distance / Pace / Elev. Gain / Duration) overlaid top-left on
/// the share map — matches the run-detail look.
class _ShareMetricsOverlay extends StatelessWidget {
  final WorkoutResult result;
  const _ShareMetricsOverlay({required this.result});

  @override
  Widget build(BuildContext context) {
    final r = result;
    String distVal = '';
    String distUnit = '';
    final s = r.distanceLabel.trim();
    final i = s.lastIndexOf(' ');
    if (i > 0) {
      distVal = s.substring(0, i);
      distUnit = s.substring(i + 1);
    } else {
      distVal = s;
    }

    final cards = <Widget>[];
    if (distVal.isNotEmpty) {
      cards.add(_ShareMetricCard(label: 'Distance', value: distVal, unit: distUnit.isEmpty ? null : distUnit));
    }
    if (r.activityType.hasPace) {
      cards.add(_ShareMetricCard(label: 'Pace', value: r.paceLabel, unit: distUnit.isEmpty ? null : '/$distUnit'));
    }
    if (r.activityType.hasElevation && r.elevGainM > 0) {
      cards.add(_ShareMetricCard(label: 'Elev. Gain', value: r.elevGainM.toStringAsFixed(0), unit: 'm'));
    }
    cards.add(_ShareMetricCard(label: 'Duration', value: r.durationLabel));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var k = 0; k < cards.length; k++) ...[
          if (k > 0) const SizedBox(height: 8),
          cards[k],
        ],
      ],
    );
  }
}

class _ShareMetricCard extends StatelessWidget {
  const _ShareMetricCard({required this.label, required this.value, this.unit});
  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 86,
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: ZveltTokens.s2),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
        border: Border.all(color: ZveltTokens.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: ZveltTokens.fontMono,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: ZveltTokens.text3,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: ZveltTokens.text,
                    height: 1,
                  ),
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 3),
                Text(
                  unit!,
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: ZveltTokens.text2,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkoutBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ZveltTokens.bg,
            ZveltTokens.brandTint,
            ZveltTokens.surface,
          ],
        ),
      ),
      child: const Opacity(
        opacity: 0.05,
        child: Center(
          child: Icon(
            AppIcons.gym,
            size: 200,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final WorkoutResult result;

  const _TopBar({required this.result});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (result.avatarUrl != null)
          CircleAvatar(
            radius: 18,
            backgroundImage: CachedNetworkImageProvider(
              result.avatarUrl!,
              maxWidth: 144, // 48dp @ 3x
            ),
            backgroundColor: ZveltTokens.surface2,
          )
        else
          CircleAvatar(
            radius: 18,
            backgroundColor: ZveltTokens.brand.withValues(alpha: 0.2),
            child: Text(
              (result.displayName ?? 'A')[0].toUpperCase(),
              style: const TextStyle(
                color: ZveltTokens.brand,
                fontWeight: FontWeight.w700,
                fontFamily: ZveltTokens.fontPrimary,
              ),
            ),
          ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.displayName ?? 'Athlete',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontFamily: ZveltTokens.fontPrimary,
                fontSize: 13,
              ),
            ),
            Text(
              _formatDate(result.startedAt),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
                fontFamily: ZveltTokens.fontPrimary,
              ),
            ),
          ],
        ),
        const Spacer(),
        _XpBadge(xp: result.xpEarned),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

class _XpBadge extends StatelessWidget {
  final int xp;

  const _XpBadge({required this.xp});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: ZveltTokens.brand.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        border: Border.all(color: ZveltTokens.brand.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(AppIcons.bolt, color: ZveltTokens.brand, size: 14),
          const SizedBox(width: 3),
          Text(
            '+$xp XP',
            style: const TextStyle(
              color: ZveltTokens.brand,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFamily: ZveltTokens.fontPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsBlock extends StatelessWidget {
  final WorkoutResult result;
  final bool isStory;

  const _StatsBlock({required this.result, required this.isStory});

  @override
  Widget build(BuildContext context) {
    final primary = _primaryStats();
    final secondary = _secondaryStats();

    return ClipRRect(
      borderRadius: BorderRadius.circular(ZveltTokens.rMd),
      child: Container(
        color: Colors.black.withValues(alpha: 0.45),
        padding: const EdgeInsets.all(ZveltTokens.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.activityType.label.toUpperCase(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
                letterSpacing: 1.2,
                fontFamily: ZveltTokens.fontPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: primary
                  .map((s) => Expanded(child: _StatCell(label: s.label, value: s.value)))
                  .toList(),
            ),
            if (secondary.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
              const SizedBox(height: 10),
              Row(
                children: secondary
                    .map((s) => Expanded(child: _StatCell(label: s.label, value: s.value, small: true)))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<_Stat> _primaryStats() {
    if (result.activityType.isGps) {
      return [
        _Stat(label: 'DISTANCE', value: result.distanceLabel),
        _Stat(label: 'TIME', value: result.durationLabel),
        if (result.activityType.hasPace)
          _Stat(label: 'PACE', value: result.paceLabel)
        else if (result.activityType.hasSpeed)
          _Stat(label: 'AVG SPEED', value: result.speedLabel),
      ];
    }
    return [
      _Stat(label: 'DURATION', value: result.durationLabel),
      _Stat(label: 'CALORIES', value: '${result.calories} kcal'),
    ];
  }

  List<_Stat> _secondaryStats() {
    final list = <_Stat>[];
    if (result.elevGainM > 0) list.add(_Stat(label: 'ELEV', value: '+${result.elevGainM.toStringAsFixed(0)}m'));
    if (result.avgHeartRate != null) list.add(_Stat(label: 'HR', value: '${result.avgHeartRate} bpm'));
    if (list.length < 2 && result.calories > 0 && result.activityType.isGps) {
      list.add(_Stat(label: 'CALORIES', value: '${result.calories} kcal'));
    }
    return list.take(3).toList();
  }
}

class _Stat {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final bool small;

  const _StatCell({required this.label, required this.value, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: small ? 9 : 10,
            letterSpacing: 0.8,
            fontFamily: ZveltTokens.fontPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: small ? 14 : 20,
            fontWeight: FontWeight.w700,
            fontFamily: ZveltTokens.fontPrimary,
          ),
        ),
      ],
    );
  }
}

class _BottomBranding extends StatelessWidget {
  final WorkoutResult result;

  const _BottomBranding({required this.result});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset(
          'assets/images/zvelt_logo.png',
          height: 22,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 8),
        Text(
          '· zvelt.app',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 12,
            fontFamily: ZveltTokens.fontPrimary,
          ),
        ),
        if (result.rankTierUnlocked != null) ...[
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: ZveltTokens.warn.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(ZveltTokens.rPill),
              border: Border.all(color: ZveltTokens.warn.withValues(alpha: 0.4)),
            ),
            child: Text(
              result.rankTierUnlocked!,
              style: const TextStyle(
                color: ZveltTokens.warn,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFamily: ZveltTokens.fontPrimary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
