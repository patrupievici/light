import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../config/map_style.dart';
import '../../models/workout_result.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/beast_intelligence_card.dart';
import '../../widgets/charts/elevation_chart.dart';
import '../../widgets/charts/pace_chart.dart';
import '../../widgets/splits_table.dart';
import '../../widgets/share_bottom_sheet.dart';
import '../workouts/post_workout_screen.dart';

class ActivitySummaryScreen extends StatefulWidget {
  final WorkoutResult result;

  const ActivitySummaryScreen({super.key, required this.result});

  @override
  State<ActivitySummaryScreen> createState() => _ActivitySummaryScreenState();
}

class _ActivitySummaryScreenState extends State<ActivitySummaryScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _staggerCtrl;
  late final MapController _mapCtrl;

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _mapCtrl = MapController();
  }

  @override
  void dispose() {
    _staggerCtrl.dispose();
    super.dispose();
  }

  Animation<double> _fadeAt(double from, double to) => CurvedAnimation(
        parent: _staggerCtrl,
        curve: Interval(from, to, curve: Curves.easeOut),
      );

  @override
  Widget build(BuildContext context) {
    final r = widget.result;

    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: CustomScrollView(
        slivers: [
          _AppBar(result: r, onShare: _openShare),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Map (GPS activities only)
                if (r.activityType.isGps && r.routePoints.isNotEmpty)
                  FadeTransition(
                    opacity: _fadeAt(0.0, 0.4),
                    child: _RouteMapCard(result: r, mapController: _mapCtrl),
                  ),

                // Primary stats
                FadeTransition(
                  opacity: _fadeAt(0.1, 0.5),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s4, ZveltTokens.s4, 0),
                    child: _StatsGrid(result: r),
                  ),
                ),

                // Secondary stat chips
                FadeTransition(
                  opacity: _fadeAt(0.2, 0.6),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s3, ZveltTokens.s4, 0),
                    child: _SecondaryChips(result: r),
                  ),
                ),

                // AI Insight
                if (r.aiInsight != null)
                  FadeTransition(
                    opacity: _fadeAt(0.3, 0.7),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s4, ZveltTokens.s4, 0),
                      child: BeastIntelligenceCard(
                        insight: r.aiInsight!,
                        tags: r.aiTags,
                      ),
                    ),
                  ),

                // Pace / Speed chart
                if (r.activityType.hasPace || r.activityType.hasSpeed)
                  if (r.splits.isNotEmpty)
                    FadeTransition(
                      opacity: _fadeAt(0.35, 0.75),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s4, ZveltTokens.s4, 0),
                        child: _ChartCard(
                          title: r.activityType.hasPace ? 'Pace per km' : 'Speed per km',
                          child: Semantics(
                            label: r.activityType.hasPace
                                ? 'Pace per kilometer chart across ${r.splits.length} splits'
                                : 'Speed per kilometer chart across ${r.splits.length} splits',
                            child: PaceChart(
                              splits: r.splits,
                              activityType: r.activityType,
                            ),
                          ),
                        ),
                      ),
                    ),

                // Elevation chart — only when the route actually carries a
                // per-point altitude series. The gain/loss numbers live in the
                // stats grid / map overlay and are shown regardless; we hide
                // just the chart when there's no real profile to draw, so a
                // flat line never contradicts a non-zero gain/loss figure.
                if (r.activityType.hasElevation && r.routePoints.length >= 2)
                  Builder(builder: (context) {
                    final elevations = _extractElevations(r.routePoints);
                    if (!_hasElevationProfile(elevations)) {
                      return const SizedBox.shrink();
                    }
                    return FadeTransition(
                      opacity: _fadeAt(0.4, 0.8),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s4, ZveltTokens.s4, 0),
                        child: _ChartCard(
                          title: 'Elevation',
                          subtitle: '+${r.elevGainM.toStringAsFixed(0)} m gain · -${r.elevLossM.toStringAsFixed(0)} m loss',
                          child: Semantics(
                            label:
                                'Elevation profile: ${r.elevGainM.toStringAsFixed(0)} metres gain, ${r.elevLossM.toStringAsFixed(0)} metres loss',
                            child: ElevationChart(
                              elevationM: elevations,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),

                // Splits table
                if (r.activityType.hasSplits && r.splits.isNotEmpty)
                  FadeTransition(
                    opacity: _fadeAt(0.45, 0.85),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s4, ZveltTokens.s4, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SectionTitle('Splits'),
                          const SizedBox(height: 8),
                          SplitsTable(splits: r.splits),
                        ],
                      ),
                    ),
                  ),

                // Weather row
                if (r.weather != null)
                  FadeTransition(
                    opacity: _fadeAt(0.5, 0.9),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s4, ZveltTokens.s4, 0),
                      child: _WeatherRow(weather: r.weather!),
                    ),
                  ),

                // Social actions
                FadeTransition(
                  opacity: _fadeAt(0.55, 1.0),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s6, ZveltTokens.s4, 0),
                    child: _SocialActions(result: r, onShare: _openShare),
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openShare() {
    ShareBottomSheet.show(
      context,
      result: widget.result,
      onPostToFeed: _postToFeed,
    );
  }

  void _postToFeed() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostWorkoutScreen(workoutId: widget.result.id),
      ),
    );
  }

  /// Real per-point altitude series in metres, or an empty list when the route
  /// carries no altitude data.
  ///
  /// `latlong2`'s [LatLng] holds only lat/lng — no altitude — so points alone
  /// can't yield a profile. When the backend wires a real altitude series here
  /// (e.g. parsed from the route_points JSON), return it; until then we return
  /// an empty list rather than fabricated zeros, which would render a flat
  /// chart that contradicts the gain/loss figures. The cap of 200 samples
  /// matches the chart's downsampling budget.
  List<double> _extractElevations(List<LatLng> points) {
    // No altitude source is available on LatLng, so there is nothing real to
    // plot. Do not invent data (e.g. a row of zeros).
    return const <double>[];
  }

  /// True when [elevations] describe an actual profile — i.e. there are enough
  /// samples and they aren't all identical (a flat line). Used to suppress the
  /// elevation chart when only placeholder/empty data is available.
  bool _hasElevationProfile(List<double> elevations) {
    if (elevations.length < 2) return false;
    final first = elevations.first;
    return elevations.any((e) => e != first);
  }
}

// ─── App Bar ─────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  final WorkoutResult result;
  final VoidCallback onShare;

  const _AppBar({required this.result, required this.onShare});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      backgroundColor: ZveltTokens.bg,
      surfaceTintColor: Colors.transparent,
      pinned: true,
      expandedHeight: 0,
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: Icon(AppIcons.angle_small_left, color: ZveltTokens.text),
        tooltip: 'Back',
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.activityType.label,
            style: TextStyle(
              color: ZveltTokens.text,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              fontFamily: ZveltTokens.fontPrimary,
            ),
          ),
          Text(
            _formatDate(result.startedAt),
            style: TextStyle(
              color: ZveltTokens.text2,
              fontSize: 12,
              fontFamily: ZveltTokens.fontPrimary,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: onShare,
          icon: const Icon(AppIcons.share, color: ZveltTokens.brand),
          tooltip: 'Share',
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final wd = days[dt.weekday - 1];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$wd, ${months[dt.month - 1]} ${dt.day} · $h:$m';
  }
}

// ─── Route Map ───────────────────────────────────────────────────────────────

class _RouteMapCard extends StatelessWidget {
  final WorkoutResult result;
  final MapController mapController;

  const _RouteMapCard({required this.result, required this.mapController});

  @override
  Widget build(BuildContext context) {
    final points = result.routePoints;
    final bounds = LatLngBounds.fromPoints(points);

    return SizedBox(
      height: 240,
      child: ClipRRect(
        child: Stack(children: [
          FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.all(ZveltTokens.s10),
            ),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
            ),
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
                  points: points,
                  strokeWidth: 3.5,
                  gradientColors: kRouteGradient,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: points.first,
                  width: 16,
                  height: 16,
                  child: Container(
                    decoration: BoxDecoration(
                      color: ZveltTokens.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
                Marker(
                  point: points.last,
                  width: 16,
                  height: 16,
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
        ),
        // Metric cards overlaid on the left, like the design mockup.
        Positioned(
          left: 12,
          top: 12,
          child: _MapMetricsOverlay(result: result),
        ),
        ]),
      ),
    );
  }
}

class _MapMetricsOverlay extends StatelessWidget {
  final WorkoutResult result;
  const _MapMetricsOverlay({required this.result});

  @override
  Widget build(BuildContext context) {
    final r = result;
    String distVal = '';
    String distUnit = '';
    if (r.activityType.isGps) {
      final s = r.distanceLabel.trim();
      final i = s.lastIndexOf(' ');
      if (i > 0) {
        distVal = s.substring(0, i);
        distUnit = s.substring(i + 1);
      } else {
        distVal = s;
      }
    }

    final cards = <Widget>[];
    if (distVal.isNotEmpty) {
      cards.add(_MapMetricCard(label: 'Distance', value: distVal, unit: distUnit.isEmpty ? null : distUnit));
    }
    if (r.activityType.hasPace) {
      cards.add(_MapMetricCard(label: 'Pace', value: r.paceLabel, unit: distUnit.isEmpty ? null : '/$distUnit'));
    }
    if (r.activityType.hasElevation && r.elevGainM > 0) {
      cards.add(_MapMetricCard(label: 'Elev. Gain', value: r.elevGainM.toStringAsFixed(0), unit: 'm'));
    }
    cards.add(_MapMetricCard(label: 'Duration', value: r.durationLabel));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          cards[i],
        ],
      ],
    );
  }
}

class _MapMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  const _MapMetricCard({required this.label, required this.value, this.unit});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 86,
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: ZveltTokens.s2),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
        // Stronger shadow than the V2 card default so white cards pop on the
        // light basemap instead of blending in.
        boxShadow: ZveltTokens.shadowFloat,
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
                  style: ZType.num_.copyWith(
                    fontSize: 15,
                    color: ZveltTokens.text,
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

// ─── Stats Grid ──────────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  final WorkoutResult result;

  const _StatsGrid({required this.result});

  @override
  Widget build(BuildContext context) {
    final cells = _buildCells();
    final crossCount = cells.length >= 4 ? 2 : cells.length;

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: crossCount,
      childAspectRatio: 1.6,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: cells,
    );
  }

  List<Widget> _buildCells() {
    final r = result;
    final cells = <Widget>[];

    if (r.activityType.isGps) {
      cells.add(_StatCell(label: 'Distance', value: r.distanceLabel, icon: AppIcons.ruler_horizontal));
    }

    cells.add(_StatCell(label: 'Duration', value: r.durationLabel, icon: AppIcons.stopwatch));

    if (r.activityType.hasPace) {
      cells.add(_StatCell(label: 'Avg Pace', value: r.paceLabel, icon: AppIcons.tachometer_fast));
    } else if (r.activityType.hasSpeed) {
      cells.add(_StatCell(label: 'Avg Speed', value: r.speedLabel, icon: AppIcons.tachometer_fast));
    }

    cells.add(_StatCell(
      label: 'Calories',
      value: '${r.calories} kcal',
      icon: AppIcons.flame,
    ));

    if (r.activityType.hasElevation && r.elevGainM > 0) {
      cells.add(_StatCell(
        label: 'Elevation',
        value: '+${r.elevGainM.toStringAsFixed(0)} m',
        icon: AppIcons.mountains,
      ));
    }

    if (r.avgHeartRate != null) {
      cells.add(_StatCell(
        label: 'Avg HR',
        value: '${r.avgHeartRate} bpm',
        icon: AppIcons.heart,
      ));
    }

    // Ensure even count for 2-column grid
    if (cells.length.isOdd) cells.add(const SizedBox.shrink());

    return cells;
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCell({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: ZveltTokens.text2, size: 14),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: ZveltTokens.text2,
                  fontSize: 12,
                  fontFamily: ZveltTokens.fontPrimary,
                ),
              ),
            ],
          ),
          Text(
            value,
            style: ZType.num_.copyWith(
              color: ZveltTokens.text,
              fontSize: 20,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Secondary Chips ─────────────────────────────────────────────────────────

class _SecondaryChips extends StatelessWidget {
  final WorkoutResult result;

  const _SecondaryChips({required this.result});

  @override
  Widget build(BuildContext context) {
    final chips = _buildChips();
    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips,
    );
  }

  List<Widget> _buildChips() {
    final r = result;
    final chips = <Widget>[];

    if (r.movingTime != r.elapsed) {
      final diff = r.elapsed - r.movingTime;
      final m = diff.inMinutes;
      if (m > 0) {
        chips.add(_Chip(label: 'Rest: ${m}m ${diff.inSeconds % 60}s', icon: AppIcons.pause));
      }
    }
    if (r.maxSpeedKmh > 0) {
      chips.add(_Chip(label: 'Max ${r.maxSpeedKmh.toStringAsFixed(1)} km/h', icon: AppIcons.bolt));
    }
    if (r.maxHeartRate != null) {
      chips.add(_Chip(label: 'Max HR: ${r.maxHeartRate} bpm', icon: AppIcons.heart));
    }
    if (r.steps != null) {
      chips.add(_Chip(label: '${r.steps} steps', icon: AppIcons.running));
    }
    if (r.cadenceRpm != null) {
      chips.add(_Chip(label: '${r.cadenceRpm!.toStringAsFixed(0)} rpm', icon: AppIcons.arrows_repeat));
    }
    if (r.xpEarned > 0) {
      chips.add(_Chip(
        label: '+${r.xpEarned} XP',
        icon: AppIcons.bolt,
        accent: ZveltTokens.brand,
      ));
    }

    return chips;
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? accent;

  const _Chip({required this.label, required this.icon, this.accent});

  @override
  Widget build(BuildContext context) {
    final c = accent ?? ZveltTokens.text2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: ZveltTokens.s2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        border: Border.all(color: c.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: c,
              fontSize: 12,
              fontFamily: ZveltTokens.fontPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Chart Card ──────────────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _ChartCard({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  color: ZveltTokens.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFamily: ZveltTokens.fontPrimary,
                ),
              ),
              if (subtitle != null) ...[
                const Spacer(),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: ZveltTokens.text2,
                    fontSize: 11,
                    fontFamily: ZveltTokens.fontPrimary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ─── Section title ────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: ZveltTokens.text,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        fontFamily: ZveltTokens.fontPrimary,
      ),
    );
  }
}

// ─── Weather Row ─────────────────────────────────────────────────────────────

class _WeatherRow extends StatelessWidget {
  final WeatherData weather;

  const _WeatherRow({required this.weather});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Row(
        children: [
          Text(
            _weatherEmoji(weather.iconCode),
            style: const TextStyle(fontSize: 28),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${weather.tempC.toStringAsFixed(0)}°C · ${weather.condition}',
                style: TextStyle(
                  color: ZveltTokens.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  fontFamily: ZveltTokens.fontPrimary,
                ),
              ),
              Text(
                'Humidity ${weather.humidity}% · Wind ${weather.windKmh.toStringAsFixed(0)} km/h',
                style: TextStyle(
                  color: ZveltTokens.text2,
                  fontSize: 12,
                  fontFamily: ZveltTokens.fontPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _weatherEmoji(String code) {
    if (code.contains('01')) return '☀️';
    if (code.contains('02') || code.contains('03')) return '⛅';
    if (code.contains('04')) return '☁️';
    if (code.contains('09') || code.contains('10')) return '🌧️';
    if (code.contains('11')) return '⛈️';
    if (code.contains('13')) return '❄️';
    if (code.contains('50')) return '🌫️';
    return '🌡️';
  }
}

// ─── Social Actions ──────────────────────────────────────────────────────────

class _SocialActions extends StatelessWidget {
  final WorkoutResult result;
  final VoidCallback onShare;

  const _SocialActions({required this.result, required this.onShare});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: onShare,
            icon: const Icon(AppIcons.share, size: 18),
            label: const Text('Share'),
            style: FilledButton.styleFrom(
              backgroundColor: ZveltTokens.brand,
              foregroundColor: ZveltTokens.onBrand,
              padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ZveltTokens.rLg),
              ),
              textStyle: const TextStyle(
                fontFamily: ZveltTokens.fontPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: () {
            // Pops back to the main shell; tab switching to Feed is not wired.
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          icon: const Icon(AppIcons.home, size: 18),
          label: const Text('Home'),
          style: OutlinedButton.styleFrom(
            foregroundColor: ZveltTokens.text,
            side: BorderSide(color: ZveltTokens.border),
            padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s4, horizontal: ZveltTokens.s5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ZveltTokens.rLg),
            ),
            textStyle: const TextStyle(
              fontFamily: ZveltTokens.fontPrimary,
              fontWeight: FontWeight.w500,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }
}
