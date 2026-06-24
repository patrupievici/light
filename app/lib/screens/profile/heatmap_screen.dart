import 'dart:async';
import 'package:zvelt_app/theme/app_icons.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../config/api_config.dart' show v1Base;
import '../../services/auth_service.dart';
import '../../services/http_client.dart';
import '../../theme/zvelt_tokens.dart';

// ─── Constants ───────────────────────────────────────────────────────────────

const _kVoltGreen = ZveltTokens.brand;
final _kBgDark = ZveltTokens.bg;
final _kCard = ZveltTokens.surface;
final _kBorder = ZveltTokens.border;
const _kTileUrl =
    'https://cartodb-basemaps-a.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png';

const _kRouteColors = [
  ZveltTokens.brand,
  ZveltTokens.info,
  ZveltTokens.strength,
  ZveltTokens.cardio,
  ZveltTokens.sleep,
  ZveltTokens.warn,
  ZveltTokens.recovery,
  ZveltTokens.brandDeep,
];

// ─── Private data class ───────────────────────────────────────────────────────

class _ActivityData {
  final List<LatLng> route;
  final double distanceM;
  _ActivityData({required this.route, required this.distanceM});
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class HeatmapScreen extends StatefulWidget {
  const HeatmapScreen({super.key});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen>
    with SingleTickerProviderStateMixin {
  final _auth = AuthService();
  final _mapCtrl = MapController();

  List<_ActivityData> _activities = [];
  bool _loading = true;
  String? _error;
  bool _showHeatmap = true; // false → routes polylines

  late final AnimationController _shimmerCtrl;

  // ── Computed ────────────────────────────────────────────────────────────────

  List<LatLng> get _heatmapPoints {
    final all = _activities.expand((a) => a.route).toList();
    if (all.length > 1000) {
      return [for (var i = 0; i < all.length; i += 3) all[i]];
    }
    return all;
  }

  double get _totalKm =>
      _activities.fold(0.0, (s, a) => s + a.distanceM) / 1000;

  String get _hotZone => _findHotZone(_heatmapPoints);

  LatLng? get _centroid {
    final pts = _heatmapPoints;
    if (pts.isEmpty) return null;
    final lat = pts.fold(0.0, (s, p) => s + p.latitude) / pts.length;
    final lng = pts.fold(0.0, (s, p) => s + p.longitude) / pts.length;
    return LatLng(lat, lng);
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _load();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    _mapCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ─────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await _auth.getAccessToken();
      if (token == null) throw Exception('Not authenticated');

      final res = await http
          .get(
            Uri.parse('$v1Base/activities'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .withTimeout();

      if (res.statusCode != 200) {
        throw Exception('Server error ${res.statusCode}');
      }

      final decoded = jsonDecode(res.body);
      final rawList = decoded is List
          ? decoded
          : (decoded is Map ? (decoded['activities'] ?? decoded['data'] ?? []) : []);

      final activities = <_ActivityData>[];
      for (final item in rawList as List) {
        if (item is! Map) continue;
        final rawPoints = item['route_points'];
        if (rawPoints == null) continue;

        final points = <LatLng>[];
        for (final rp in rawPoints as List) {
          LatLng? pt;
          if (rp is Map) {
            final lat = (rp['lat'] ?? rp['latitude'])?.toDouble();
            final lng = (rp['lng'] ?? rp['longitude'] ?? rp['lon'])?.toDouble();
            if (lat != null && lng != null) pt = LatLng(lat, lng);
          } else if (rp is List && rp.length >= 2) {
            pt = LatLng((rp[0] as num).toDouble(), (rp[1] as num).toDouble());
          }
          if (pt != null) points.add(pt);
        }

        if (points.isEmpty) continue;
        final distM = (item['distance_m'] as num?)?.toDouble() ?? 0.0;
        activities.add(_ActivityData(route: points, distanceM: distM));
      }

      if (!mounted) return;
      setState(() {
        _activities = activities;
        _loading = false;
      });

      _fitMap();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _fitMap() {
    final pts = _heatmapPoints;
    if (pts.isEmpty) return;

    final bounds = LatLngBounds.fromPoints(pts);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapCtrl.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(ZveltTokens.s12),
        ),
      );
    });
  }

  // ── Stats helper ─────────────────────────────────────────────────────────────

  static String _findHotZone(List<LatLng> points) {
    if (points.isEmpty) return '—';
    const cell = 0.005; // ~500 m grid
    final grid = <String, int>{};
    for (final p in points) {
      final key =
          '${(p.latitude / cell).floor()}_${(p.longitude / cell).floor()}';
      grid[key] = (grid[key] ?? 0) + 1;
    }
    final top = grid.entries.reduce((a, b) => a.value > b.value ? a : b);
    final parts = top.key.split('_');
    final lat = int.parse(parts[0]) * cell + cell / 2;
    final lng = int.parse(parts[1]) * cell + cell / 2;
    final ns = lat >= 0 ? 'N' : 'S';
    final ew = lng >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(2)}°$ns  ${lng.abs().toStringAsFixed(2)}°$ew';
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBgDark,
      appBar: AppBar(
        backgroundColor: _kBgDark,
        foregroundColor: ZveltTokens.text,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'MY ROUTES',
          style: TextStyle(
            fontFamily: ZveltTokens.fontPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
            color: ZveltTokens.text,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(AppIcons.refresh, size: 20),
            onPressed: _loading ? null : _load,
            color: ZveltTokens.text2,
            tooltip: 'Refresh routes',
          ),
        ],
      ),
      body: Column(
        children: [
          _StatsHeader(
            count: _activities.length,
            totalKm: _totalKm,
            hotZone: _hotZone,
            loading: _loading,
          ),
          Expanded(
            child: Stack(
              children: [
                _buildMap(),
                if (_loading) _ShimmerOverlay(animation: _shimmerCtrl),
                if (_error != null && !_loading) _ErrorCard(message: _error!),
                if (!_loading && _activities.isEmpty && _error == null)
                  const _EmptyCard(),
                Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _TogglePill(
                      showHeatmap: _showHeatmap,
                      onToggle: (v) => setState(() => _showHeatmap = v),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final initialCenter = _centroid ?? const LatLng(44.4268, 26.1025);

    final polylines = _activities.asMap().entries.map((e) {
      final color = _kRouteColors[e.key % _kRouteColors.length]
          .withValues(alpha: 0.6);
      return Polyline(
        points: e.value.route,
        color: color,
        strokeWidth: 2.5,
      );
    }).toList();

    return FlutterMap(
      mapController: _mapCtrl,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: 13,
        backgroundColor: _kBgDark,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: _kTileUrl,
          userAgentPackageName: 'com.zvelt.app',
        ),
        if (!_loading && _activities.isNotEmpty)
          _showHeatmap
              ? _HeatmapLayer(points: _heatmapPoints)
              : PolylineLayer(polylines: polylines),
      ],
    );
  }
}

// ─── Heatmap layer ────────────────────────────────────────────────────────────

class _HeatmapLayer extends StatelessWidget {
  final List<LatLng> points;
  const _HeatmapLayer({required this.points});

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return Semantics(
      label: 'Activity heatmap showing where your routes concentrate',
      child: MobileLayerTransformer(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _HeatmapPainter(points: points, camera: camera),
            size: camera.size,
            isComplex: true,
          ),
        ),
      ),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final List<LatLng> points;
  final MapCamera camera;

  const _HeatmapPainter({required this.points, required this.camera});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    // saveLayer so the blend accumulates density correctly.
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..blendMode = BlendMode.multiply,
    );

    const radius = 28.0;
    // Margin so we still draw circles whose center is just off-screen.
    const margin = radius + 4;

    for (final pt in points) {
      final off = camera.latLngToScreenOffset(pt);

      if (off.dx < -margin ||
          off.dx > size.width + margin ||
          off.dy < -margin ||
          off.dy > size.height + margin) {
        continue;
      }

      final shader = const RadialGradient(
        colors: [
          ZveltTokens.brand,  // solid brand orange at centre
          Color(0x66FF7A2F),  // 40 % opacity mid-ring
          Color(0x00FF7A2F),  // transparent at edge
        ],
        stops: [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: off, radius: radius));

      canvas.drawCircle(
        off,
        radius,
        Paint()
          ..shader = shader
          ..blendMode = BlendMode.multiply,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      !identical(old.camera, camera) || !identical(old.points, points);
}

// ─── Stats header ─────────────────────────────────────────────────────────────

class _StatsHeader extends StatelessWidget {
  final int count;
  final double totalKm;
  final String hotZone;
  final bool loading;

  const _StatsHeader({
    required this.count,
    required this.totalKm,
    required this.hotZone,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kCard,
      padding: const EdgeInsets.symmetric(
          horizontal: ZveltTokens.s4, vertical: ZveltTokens.s4),
      child: Row(
        children: [
          _StatCell(
            label: 'ACTIVITIES',
            value: loading ? '—' : '$count',
          ),
          _kDivider,
          _StatCell(
            label: 'TOTAL KM',
            value: loading ? '—' : totalKm.toStringAsFixed(1),
          ),
          _kDivider,
          Expanded(
            child: _StatCell(
              label: 'HOT ZONE',
              value: loading ? '—' : hotZone,
              small: true,
            ),
          ),
        ],
      ),
    );
  }

  static final _kDivider = SizedBox(
    height: 32,
    child: VerticalDivider(
      color: _kBorder,
      thickness: 1,
      width: 24,
    ),
  );
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final bool small;

  const _StatCell({
    required this.label,
    required this.value,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: ZType.eyebrow.copyWith(color: ZveltTokens.text2),
          ),
          const SizedBox(height: ZveltTokens.s1),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: ZType.num_.copyWith(
              fontSize: small ? 12 : 18,
              fontWeight: FontWeight.w700,
              color: _kVoltGreen,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Toggle pill ──────────────────────────────────────────────────────────────

class _TogglePill extends StatelessWidget {
  final bool showHeatmap;
  final ValueChanged<bool> onToggle;

  const _TogglePill({required this.showHeatmap, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: _kCard.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        border: Border.all(color: _kBorder, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(
            label: 'HEATMAP',
            active: showHeatmap,
            isLeft: true,
            onTap: () => onToggle(true),
          ),
          _Segment(
            label: 'RUTE',
            active: !showHeatmap,
            isLeft: false,
            onTap: () => onToggle(false),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool active;
  final bool isLeft;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.active,
    required this.isLeft,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = isLeft
        ? const BorderRadius.horizontal(left: Radius.circular(ZveltTokens.rPill))
        : const BorderRadius.horizontal(right: Radius.circular(ZveltTokens.rPill));

    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(
            horizontal: ZveltTokens.s5, vertical: ZveltTokens.s2),
        decoration: BoxDecoration(
          color: active ? _kVoltGreen : Colors.transparent,
          borderRadius: radius,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: ZveltTokens.fontMono,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: active ? _kBgDark : ZveltTokens.text2,
          ),
        ),
      ),
      ),
    );
  }
}

// ─── Shimmer overlay ──────────────────────────────────────────────────────────

class _ShimmerOverlay extends StatelessWidget {
  final Animation<double> animation;
  const _ShimmerOverlay({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        final v = animation.value; // 0→1 repeating
        // Sweep from left (−1) to right (+1), wrapping
        final begin = Alignment(v * 2 - 1.5, -0.3);
        final end = Alignment(v * 2 - 0.5, 0.3);
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: begin,
              end: end,
              colors: [
                ZveltTokens.bg.withValues(alpha: 0.55),
                ZveltTokens.surface.withValues(alpha: 0.06),
                ZveltTokens.bg.withValues(alpha: 0.55),
              ],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: _kVoltGreen,
                    strokeWidth: 2.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Se încarcă rutele…',
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontMono,
                    fontSize: 12,
                    letterSpacing: 1,
                    color: ZveltTokens.text2,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Error / empty cards ──────────────────────────────────────────────────────

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: ZveltTokens.s8),
        padding: const EdgeInsets.all(ZveltTokens.s5),
        decoration: BoxDecoration(
          color: _kCard.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(ZveltTokens.rMd),
          border: Border.all(color: ZveltTokens.error.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.cloud_disabled,
                color: ZveltTokens.error, size: 32),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: ZveltTokens.fontPrimary,
                fontSize: 13,
                color: ZveltTokens.text2,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: ZveltTokens.s10),
        padding: const EdgeInsets.all(ZveltTokens.s6),
        decoration: BoxDecoration(
          color: _kCard.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(ZveltTokens.rMd),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.map, color: _kVoltGreen, size: 36),
            const SizedBox(height: 12),
            Text(
              'No activity recorded',
              style: TextStyle(
                fontFamily: ZveltTokens.fontPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: ZveltTokens.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Start a GPS workout\nto see your route on the map.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: ZveltTokens.fontPrimary,
                fontSize: 13,
                color: ZveltTokens.text2,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

