import 'dart:convert';
import 'package:zvelt_app/theme/app_icons.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/api_config.dart' show v1Base;
import '../../config/map_style.dart';
import '../../theme/zvelt_tokens.dart';
import '../../services/_crash_reporter.dart';
import '../../services/auth_service.dart';
import '../../services/http_client.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

class _SegmentDetail {
  const _SegmentDetail({
    required this.id,
    required this.name,
    required this.distanceM,
    required this.elevationGainM,
    required this.polyline,
    this.myBestSec,
  });

  final String id;
  final String name;
  final double distanceM;
  final double elevationGainM;
  final List<LatLng> polyline;
  final int? myBestSec;

  LatLng get start => polyline.first;
  LatLng get end => polyline.last;
  LatLng get midpoint => polyline[polyline.length ~/ 2];
}

class _LeaderboardEntry {
  const _LeaderboardEntry({
    required this.rank,
    required this.name,
    required this.elapsedSec,
    required this.date,
    this.isMe = false,
  });

  final int rank;
  final String name;
  final int elapsedSec;
  final DateTime date;
  final bool isMe;

  String get formattedTime {
    final m = elapsedSec ~/ 60;
    final s = elapsedSec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get formattedDate => '${date.day}/${date.month}/${date.year}';
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class SegmentLeaderboardScreen extends StatefulWidget {
  const SegmentLeaderboardScreen({super.key, required this.segmentId});

  final String segmentId;

  @override
  State<SegmentLeaderboardScreen> createState() =>
      _SegmentLeaderboardScreenState();
}

class _SegmentLeaderboardScreenState extends State<SegmentLeaderboardScreen> {
  final _auth = AuthService();
  final _map = MapController();

  _SegmentDetail? _segment;
  List<_LeaderboardEntry> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final token = await _auth.getAccessToken();
      final headers = token != null
          ? {'Authorization': 'Bearer $token'}
          : <String, String>{};

      final results = await Future.wait([
        http
            .get(
              Uri.parse('$v1Base/segments/${widget.segmentId}'),
              headers: headers,
            )
            .withTimeout(),
        http
            .get(
              Uri.parse('$v1Base/segments/${widget.segmentId}/leaderboard')
                  .replace(queryParameters: {'limit': '10'}),
              headers: headers,
            )
            .withTimeout(),
      ]);

      final segRes = results[0];
      final lbRes = results[1];

      if (segRes.statusCode != 200) {
        throw Exception('Segmentul nu a putut fi încărcat (${segRes.statusCode})');
      }

      final segBody = jsonDecode(segRes.body) as Map<String, dynamic>;
      _segment = _parseSegment(segBody['data'] ?? segBody);

      if (lbRes.statusCode == 200) {
        final lbBody = jsonDecode(lbRes.body) as Map<String, dynamic>;
        final list = lbBody['data'] as List<dynamic>? ?? [];
        _entries = list
            .asMap()
            .entries
            .map((e) => _parseEntry(e.key + 1, e.value))
            .toList();
      }

      if (mounted) setState(() => _loading = false);

      WidgetsBinding.instance.addPostFrameCallback((_) => _fitMap());
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  _SegmentDetail _parseSegment(dynamic raw) {
    final j = raw as Map<String, dynamic>;

    LatLng parsePoint(dynamic p) {
      if (p is Map) {
        return LatLng(
          (p['lat'] as num).toDouble(),
          (p['lng'] as num).toDouble(),
        );
      }
      if (p is List && p.length >= 2) {
        return LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble());
      }
      throw const FormatException('bad point');
    }

    final rawPoly = j['polyline'] as List<dynamic>? ?? [];
    var poly = rawPoly.map(parsePoint).toList();
    if (poly.isEmpty) {
      poly = [parsePoint(j['start']), parsePoint(j['end'])];
    }

    return _SegmentDetail(
      id: j['id'] as String,
      name: j['name'] as String,
      distanceM: (j['distanceM'] as num?)?.toDouble() ?? 0,
      elevationGainM: (j['elevationGainM'] as num?)?.toDouble() ?? 0,
      polyline: poly,
      myBestSec: (j['myBestSec'] as num?)?.toInt(),
    );
  }

  _LeaderboardEntry _parseEntry(int rank, dynamic raw) {
    final j = raw as Map<String, dynamic>;
    final name =
        (j['displayName'] ?? j['username'] ?? 'Athlete').toString().trim();
    final elapsed = (j['elapsedSec'] as num?)?.toInt() ?? 0;
    final rawDate = j['date'] as String? ?? j['achievedAt'] as String?;
    final date = rawDate != null
        ? DateTime.tryParse(rawDate) ?? DateTime.now()
        : DateTime.now();
    final isMe = j['isMe'] as bool? ?? false;
    return _LeaderboardEntry(
      rank: rank,
      name: name,
      elapsedSec: elapsed,
      date: date,
      isMe: isMe,
    );
  }

  void _fitMap() {
    final seg = _segment;
    if (seg == null || seg.polyline.isEmpty || !mounted) return;
    try {
      final bounds = LatLngBounds.fromPoints(seg.polyline);
      _map.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(48),
        ),
      );
    } catch (e, st) {
      reportError(e, st, reason: 'segment-leaderboard:fit-map');
    }
  }

  Future<void> _navigateToStart() async {
    final start = _segment?.start;
    if (start == null) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${start.latitude},${start.longitude}'
      '&travelmode=walking',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: ZveltTokens.bg,
        body: const Center(
          child: CircularProgressIndicator(
            color: ZveltTokens.brand,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: ZveltTokens.bg,
        appBar: AppBar(backgroundColor: ZveltTokens.bg),
        body: _ErrorView(error: _error!, onRetry: _load),
      );
    }

    final seg = _segment!;
    final myEntry = _entries.where((e) => e.isMe).firstOrNull;

    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: CustomScrollView(
        slivers: [
          _MapAppBar(
            segment: seg,
            mapController: _map,
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(ZveltTokens.screenPaddingH, ZveltTokens.s5, ZveltTokens.screenPaddingH, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _SegmentHeader(segment: seg),
                const SizedBox(height: 16),
                _StatsRow(segment: seg, myEntry: myEntry),
                const SizedBox(height: 24),
                _LeaderboardSection(entries: _entries),
                const SizedBox(height: 20),
                _NavigateButton(onTap: _navigateToStart),
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Map app bar ──────────────────────────────────────────────────────────────

class _MapAppBar extends StatelessWidget {
  const _MapAppBar({required this.segment, required this.mapController});

  final _SegmentDetail segment;
  final MapController mapController;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 260,
      pinned: true,
      backgroundColor: ZveltTokens.bg,
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            decoration: BoxDecoration(
              color: ZveltTokens.bg2,
              shape: BoxShape.circle,
            ),
            child: Icon(
              AppIcons.arrow_small_left,
              color: ZveltTokens.text,
              size: 20,
            ),
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          children: [
            FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: segment.midpoint,
                initialZoom: 14,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: kMapTileUrl,
                  userAgentPackageName: 'com.lunaoscar.zvelt',
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: segment.polyline,
                      gradientColors: kRouteGradient,
                      strokeWidth: 4.5,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: segment.start,
                      width: 28,
                      height: 28,
                      child: const _MapPin(color: ZveltTokens.success, label: 'S'),
                    ),
                    Marker(
                      point: segment.end,
                      width: 28,
                      height: 28,
                      child: const _MapPin(color: ZveltTokens.error, label: 'F'),
                    ),
                  ],
                ),
              ],
            ),
            // Bottom fade to background
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, ZveltTokens.bg],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ─── Segment header ───────────────────────────────────────────────────────────

class _SegmentHeader extends StatelessWidget {
  const _SegmentHeader({required this.segment});

  final _SegmentDetail segment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: ZveltTokens.brand.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(ZveltTokens.rPill),
            border:
                Border.all(color: ZveltTokens.brand.withValues(alpha: 0.35)),
          ),
          child: const Text(
            'SEGMENT',
            style: TextStyle(
              color: ZveltTokens.brand,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          segment.name,
          style: ZType.h1.copyWith(
            color: ZveltTokens.text,
          ),
        ),
      ],
    );
  }
}

// ─── Stats row ────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.segment, this.myEntry});

  final _SegmentDetail segment;
  final _LeaderboardEntry? myEntry;

  String get _distanceLabel {
    final m = segment.distanceM;
    return m < 1000
        ? '${m.toStringAsFixed(0)} m'
        : '${(m / 1000).toStringAsFixed(2)} km';
  }

  String get _elevationLabel =>
      '+${segment.elevationGainM.toStringAsFixed(0)} m';

  String get _prLabel {
    final sec = myEntry?.elapsedSec ?? segment.myBestSec;
    if (sec == null) return '–';
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  bool get _hasPr => myEntry != null || segment.myBestSec != null;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: AppIcons.ruler_horizontal,
            label: 'Distanță',
            value: _distanceLabel,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: AppIcons.arrow_trend_up,
            label: 'Denivelare',
            value: _elevationLabel,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: AppIcons.trophy,
            label: 'Recordul tău',
            value: _prLabel,
            highlight: _hasPr,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final accent = highlight ? ZveltTokens.success : ZveltTokens.brand;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s4, horizontal: ZveltTokens.s3),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        border: highlight
            ? Border.all(color: ZveltTokens.success.withValues(alpha: 0.35))
            : null,
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 16),
          const SizedBox(height: ZveltTokens.s2),
          Text(
            value,
            style: ZType.num_.copyWith(
              color: highlight ? ZveltTokens.success : ZveltTokens.text,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: ZveltTokens.s1),
          Text(
            label,
            style: TextStyle(
              fontFamily: ZveltTokens.fontPrimary,
              color: ZveltTokens.text2,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Leaderboard ──────────────────────────────────────────────────────────────

class _LeaderboardSection extends StatelessWidget {
  const _LeaderboardSection({required this.entries});

  final List<_LeaderboardEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TOP 10',
          style: TextStyle(
            color: ZveltTokens.text2,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        if (entries.isEmpty)
          _EmptyLeaderboard()
        else
          ...entries.map((e) => _LeaderboardRow(entry: e)),
      ],
    );
  }
}

class _EmptyLeaderboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s6),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Center(
        child: Column(
          children: [
            Icon(
              AppIcons.trophy,
              color: ZveltTokens.text2,
              size: 36,
            ),
            const SizedBox(height: ZveltTokens.s2),
            Text(
              'Fii primul pe leaderboard!',
              style: ZType.bodyM.copyWith(
                color: ZveltTokens.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.entry});

  final _LeaderboardEntry entry;

  static const _medals = ['🥇', '🥈', '🥉'];

  @override
  Widget build(BuildContext context) {
    final isTop3 = entry.rank <= 3;
    final Color rankColor;
    if (entry.isMe) {
      rankColor = ZveltTokens.success;
    } else if (isTop3) {
      rankColor = ZveltTokens.warn;
    } else {
      rankColor = ZveltTokens.text2;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: ZveltTokens.s2),
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
      decoration: BoxDecoration(
        color: entry.isMe
            ? ZveltTokens.success.withValues(alpha: 0.08)
            : ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        border: entry.isMe
            ? Border.all(color: ZveltTokens.success.withValues(alpha: 0.35))
            : null,
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Row(
        children: [
          // Rank / medal
          SizedBox(
            width: 36,
            child: Text(
              isTop3 ? _medals[entry.rank - 1] : '#${entry.rank}',
              style: TextStyle(
                color: rankColor,
                fontSize: isTop3 ? 22 : 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Avatar circle
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: entry.isMe
                  ? ZveltTokens.success.withValues(alpha: 0.18)
                  : ZveltTokens.bg2,
              shape: BoxShape.circle,
              border: Border.all(
                color: entry.isMe
                    ? ZveltTokens.success.withValues(alpha: 0.4)
                    : ZveltTokens.border,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              entry.name.isNotEmpty ? entry.name[0].toUpperCase() : '?',
              style: TextStyle(
                color: entry.isMe ? ZveltTokens.success : ZveltTokens.text2,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name + date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.isMe ? '${entry.name} (tu)' : entry.name,
                  style: TextStyle(
                    color:
                        entry.isMe ? ZveltTokens.success : ZveltTokens.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  entry.formattedDate,
                  style: TextStyle(
                    color: ZveltTokens.text2,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Time (monospaced for alignment)
          Text(
            entry.formattedTime,
            style: ZType.num_.copyWith(
              color: entry.isMe ? ZveltTokens.success : ZveltTokens.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Navigate CTA ─────────────────────────────────────────────────────────────

class _NavigateButton extends StatelessWidget {
  const _NavigateButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: ZveltTokens.brand,
          foregroundColor: ZveltTokens.onBrand,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ZveltTokens.rLg),
          ),
        ),
        icon: const Icon(AppIcons.navigation, size: 20),
        label: const Text(
          'Încearcă segmentul',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

// ─── Error view ───────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.exclamation, color: ZveltTokens.error, size: 48),
            const SizedBox(height: 16),
            Text(
              error,
              textAlign: TextAlign.center,
              style: ZType.bodyM.copyWith(
                color: ZveltTokens.text2,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(AppIcons.refresh),
              label: const Text('Încearcă din nou'),
              style:
                  FilledButton.styleFrom(backgroundColor: ZveltTokens.brand),
            ),
          ],
        ),
      ),
    );
  }
}
