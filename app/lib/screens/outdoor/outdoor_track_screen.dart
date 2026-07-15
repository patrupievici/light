// GPS track + OpenStreetMap — same free stack as:
//   https://github.com/mo7amedaliEbaid/run-tracker (Apache-2.0, flutter_map + geolocator)
// Zvelt: single-screen integration (no Riverpod / upstream file copies).
//
// Layout = Razvan's run-detail mockup: full-bleed map with the metric cards
// (Distance / Pace / Elev. Gain / Duration) overlaid on the left edge.

import 'dart:async';
import 'package:zvelt_app/theme/app_icons.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../config/map_style.dart';
import '../../widgets/map_metrics_overlay.dart';
import '../../widgets/start_countdown.dart';
import '../../theme/zvelt_tokens.dart';
import '../../models/activity_kind.dart';
import '../../services/_crash_reporter.dart';
import '../../services/activity_calendar_store.dart';
import '../../services/activity_service.dart';
import '../../services/auth_service.dart';
import '../../services/offline_sync_coordinator.dart';
import '../../services/pending_activity_queue.dart';
import '../../services/route_tracker.dart';
import '../../services/weather_service.dart';

/// Run or ride: live route on OSM + distance (foreground GPS only).
class OutdoorTrackScreen extends StatefulWidget {
  const OutdoorTrackScreen({super.key, this.initialMode = 'run'});

  /// 'run' | 'bike' — which activity the screen opens on (Home Run/Ride tiles).
  final String initialMode;

  @override
  State<OutdoorTrackScreen> createState() => _OutdoorTrackScreenState();
}

class _OutdoorTrackScreenState extends State<OutdoorTrackScreen> {
  final MapController _map = MapController();
  StreamSubscription<Position>? _sub;
  bool _tracking = false;
  bool _locBusy = true;
  String? _error;

  RouteTracker _tracker = RouteTracker();
  LatLng _center = const LatLng(44.4268, 26.1025); // București fallback

  late String _mode = widget.initialMode == 'bike' ? 'bike' : 'run';

  DateTime? _trackStart;
  DateTime? _trackEnd;
  Timer? _tick;
  int _elapsedSec = 0;
  String? _weatherLine;
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    setState(() {
      _locBusy = true;
      _error = null;
    });
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() {
          _error = 'Location permission is required to show your route.';
          _locBusy = false;
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final ll = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _center = ll;
        _locBusy = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _map.move(ll, 16);
      });
      _fetchWeather(pos.latitude, pos.longitude);
    } catch (e, st) {
      reportError(e, st, reason: 'outdoor:initial-location');
      setState(() {
        _error = 'Could not get location. Check GPS.';
        _locBusy = false;
      });
    }
  }

  Future<void> _fetchWeather(double lat, double lon) async {
    final w = await WeatherService().current(lat: lat, lon: lon);
    if (!mounted) return;
    if (w.tempC != null) {
      setState(() {
        _weatherLine =
            '${w.tempC!.toStringAsFixed(0)}°C · ${w.description ?? ''}'.trim();
      });
    }
  }

  Future<void> _toggleTracking() async {
    if (_tracking) {
      await _sub?.cancel();
      _sub = null;
      _tick?.cancel();
      _tick = null;
      await WakelockPlus.disable();
      setState(() {
        _tracking = false;
        _trackEnd = DateTime.now();
      });
      return;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      setState(() => _error = 'Enable location to record a route.');
      return;
    }

    // 3 · 2 · 1 start countdown (same as the workout start), then begin.
    // ignore: use_build_context_synchronously
    final go = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (ctx, _, __) => StartCountdown(
          title: 'OUTDOOR · GPS',
          accent: ZveltTokens.brand,
          onComplete: () => Navigator.of(ctx).pop(true),
          onCancel: () => Navigator.of(ctx).pop(false),
        ),
      ),
    );
    if (!mounted || go != true) return;
    await _beginTracking();
  }

  Future<void> _beginTracking() async {
    setState(() {
      _error = null;
      _tracking = true;
      _tracker = RouteTracker(isBike: _mode == 'bike');
      _trackStart = DateTime.now();
      _trackEnd = null;
      _elapsedSec = 0;
      _saved = false;
    });
    await WakelockPlus.enable();
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_tracking || _trackStart == null || !mounted) return;
      setState(() =>
          _elapsedSec = DateTime.now().difference(_trackStart!).inSeconds);
    });

    const settings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 5,
    );

    _sub =
        Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
      if (!mounted) return;
      // RouteTracker filters jitter/teleports; rejected fixes shouldn't move
      // the marker or camera either, so the route stays honest.
      if (!_tracker.add(pos)) return;
      final ll = _tracker.lastPoint!;
      setState(() => _center = ll);
      _map.move(ll, _map.camera.zoom);
    });
  }

  void _recenter() {
    _map.move(_tracker.lastPoint ?? _center, 16);
  }

  /// Persist the completed outdoor session: best-effort POST to the backend
  /// (stub endpoint — see WorkoutService.saveOutdoorSession) and always
  /// mirror locally into the Activity calendar so it shows up immediately.
  Future<void> _saveSession() async {
    if (_saving || _saved) return;
    if (_tracker.points.isEmpty || _trackStart == null) return;
    final start = _trackStart!;
    final end = _trackEnd ?? DateTime.now();

    // Auth guard — should be impossible here, but surface a clear error
    // rather than failing silently if the token has vanished.
    final token = await AuthService().getAccessToken();
    if (!mounted) return;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to save this session.')),
      );
      Navigator.of(context).pop();
      return;
    }

    // Short-session confirm (<60s).
    if (_elapsedSec < 60) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ZveltTokens.surface,
          title: const Text('Very short session'),
          content: Text('Only ${_elapsedSec}s recorded. Save anyway?',
              style: TextStyle(color: ZveltTokens.text2)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save')),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }

    setState(() => _saving = true);

    // Canonical wire shape: {lat, lng, t: epoch ms}. The server recomputes
    // distance/duration/elevation from these points (anti-cheat) — an ISO
    // timestamp here would be silently dropped by the backend normalizer.
    final route =
        ActivityService.routePointsFrom(_tracker.points, _tracker.pointTs);

    var storedOffline = false;
    var xpGain = 0;
    Object? err; // 4xx only — a payload the server will never accept
    try {
      final saved = await ActivityService().saveActivity(
        mode: _mode,
        routePoints: route,
        distanceM: _tracker.meters,
        durationS: _elapsedSec,
        calories: _kcalEstimate > 0 ? _kcalEstimate : null,
        startedAt: start,
        endedAt: end,
      );
      // Award XP on the server-trusted metrics (best-effort — the activity is
      // already persisted; a failed XP call must not fail the save).
      try {
        final xp = await ActivityService().completeCardio(
          mode: _mode == 'bike' ? 'bike' : 'run',
          distanceM: (saved.distanceM ?? _tracker.meters),
          durationSec: (saved.durationS ?? _elapsedSec).clamp(1, 86400),
          source: 'outdoor_track',
        );
        xpGain = xp.xpGain;
      } catch (e, st) {
        reportError(e, st, reason: 'outdoor:xp-award');
      }
    } on ActivitySaveException catch (e) {
      err = e;
    } catch (e, st) {
      // Offline / 5xx — durable-store the full session; the sync coordinator
      // replays it (and awards the XP) when connectivity returns.
      reportError(e, st, reason: 'outdoor:save-enqueue');
      await OfflineSyncCoordinator.instance.enqueueActivity(
        PendingActivityEntry(
          clientActivityId: 'act_${DateTime.now().microsecondsSinceEpoch}',
          mode: _mode,
          routePoints: route,
          distanceM: _tracker.meters,
          durationS: _elapsedSec,
          calories: _kcalEstimate > 0 ? _kcalEstimate : null,
          startedAtIso: start.toUtc().toIso8601String(),
          endedAtIso: end.toUtc().toIso8601String(),
        ),
      );
      storedOffline = true;
    }

    // Always mirror locally so the Activity calendar shows the session
    // immediately, regardless of how the backend save went.
    final dayYmd =
        '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    await ActivityCalendarStore().addManualSession(
      dayYmd,
      ManualCardioSession(
        // Stable id (session start epoch): the Retry path re-runs this whole
        // method, so the mirror must replace, not duplicate, on each attempt.
        id: start.millisecondsSinceEpoch.toString(),
        kind: _mode == 'bike' ? ActivityKind.cycle : ActivityKind.run,
        distanceKm: _tracker.meters / 1000.0,
        durationMin: (_elapsedSec / 60).round(),
      ),
    );

    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = err == null;
    });

    if (err != null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ZveltTokens.surface,
          title: const Text('Could not save'),
          content:
              Text(err.toString(), style: TextStyle(color: ZveltTokens.text2)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close')),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _saveSession();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(storedOffline
              ? 'Offline — run stored on device, will sync automatically'
              : xpGain > 0
                  ? 'Run saved · +$xpGain XP · view it in Activity'
                  : 'Run saved · view it in Activity')),
    );
    _returnToAppRoot();
  }

  void _returnToAppRoot() {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true)
        .popUntil((route) => route.isFirst);
  }

  /// Back pressed while GPS is actively recording — confirm before the
  /// recording is silently discarded.
  Future<void> _confirmDiscardRecording() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZveltTokens.surface,
        title: const Text('Discard recording?'),
        content: Text(
          'GPS is still recording. Leaving now discards this session.',
          style: TextStyle(color: ZveltTokens.text2),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep recording')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ZveltTokens.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    WakelockPlus.disable();
    _map.dispose();
    super.dispose();
  }

  double get _avgKmh {
    if (_elapsedSec < 5 || _tracker.meters < 5) return 0;
    return (_tracker.meters / _elapsedSec) * 3.6;
  }

  /// MET aproximativ: alergare ~9, bike ~6; greutate implicită 70 kg dacă nu e în profil.
  /// Gated on real distance too — a time-only estimate ticked up while the
  /// user stood still, contradicting the frozen 0 m distance (no fake metrics).
  int get _kcalEstimate {
    if (_elapsedSec < 10 || _tracker.meters < 20) return 0;
    final met = _mode == 'bike' ? 6.0 : 9.0;
    final hours = _elapsedSec / 3600;
    return (met * 70 * hours).round();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;

    return PopScope(
      canPop: !_tracking,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmDiscardRecording();
      },
      child: Scaffold(
        backgroundColor: ZveltTokens.bg,
        body: _locBusy
            ? const Center(
                child: CircularProgressIndicator(color: ZveltTokens.brand))
            : Stack(
                fit: StackFit.expand,
                children: [
                  // ── Full-bleed map ────────────────────────────────────────
                  FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: _center,
                      initialZoom: 16,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: kMapTileUrl,
                        userAgentPackageName: 'com.lunaoscar.zvelt',
                      ),
                      if (_tracker.points.isNotEmpty)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _tracker.points,
                              strokeWidth: 5,
                              gradientColors: kRouteGradient,
                            ),
                          ],
                        ),
                      if (_tracker.points.isNotEmpty)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _tracker.points.last,
                              width: 36,
                              height: 36,
                              child: Icon(
                                _mode == 'bike'
                                    ? AppIcons.bike
                                    : AppIcons.running,
                                color: ZveltTokens.brand,
                                size: 32,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),

                  // ── Floating top bar: back · mode · recenter ──────────────
                  Positioned(
                    top: topPad + 8,
                    left: 12,
                    right: 12,
                    child: Row(
                      children: [
                        _RoundMapButton(
                          icon: AppIcons.arrow_small_left,
                          tooltip: 'Back',
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                        const SizedBox(width: 10),
                        _ModeToggle(
                          mode: _mode,
                          enabled: !_tracking,
                          onChanged: (m) => setState(() => _mode = m),
                        ),
                        const Spacer(),
                        _RoundMapButton(
                          icon: AppIcons.location_alt,
                          tooltip: 'Recenter',
                          onTap: _recenter,
                        ),
                      ],
                    ),
                  ),

                  // ── Metric cards overlaid on the map (Razvan's design) ────
                  Positioned(
                    top: topPad + 64,
                    left: 12,
                    child: MapMetricsOverlay(
                      distanceM: _tracker.meters,
                      elapsed: Duration(seconds: _elapsedSec),
                      elevGainM: _tracker.elevGainM,
                    ),
                  ),

                  // ── Bottom control panel ──────────────────────────────────
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildBottomPanel(),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rLg)),
        boxShadow: ZveltTokens.shadowFloat,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_weatherLine != null || _tracking || _elapsedSec > 0) ...[
                Text(
                  [
                    if (_weatherLine != null) _weatherLine!,
                    if (_tracking || _elapsedSec > 0)
                      'Avg ${_avgKmh.toStringAsFixed(1)} km/h · ~$_kcalEstimate kcal (est.)',
                  ].join(' · '),
                  style: TextStyle(color: ZveltTokens.text2, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _toggleTracking,
                  icon: Icon(_tracking ? AppIcons.stop : AppIcons.play),
                  label: Text(_tracking ? 'Stop' : 'Start'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (!_tracking && _trackEnd != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: (_saving || _saved || _tracker.points.isEmpty)
                        ? null
                        : _saveSession,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: ZveltTokens.onBrand),
                          )
                        : Icon(_saved ? AppIcons.check : AppIcons.disk),
                    label: Text(_tracker.points.isEmpty
                        ? 'No route captured'
                        : (_saved
                            ? 'Saved'
                            : (_saving ? 'Saving…' : 'Save workout'))),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(
                        color: ZveltTokens.error, fontSize: 13)),
              ],
              const SizedBox(height: 4),
              Text(
                '© OpenStreetMap contributors',
                style: TextStyle(
                  color: ZveltTokens.text2.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Floating round map button ───────────────────────────────────────────────

class _RoundMapButton extends StatelessWidget {
  const _RoundMapButton(
      {required this.icon, required this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ZveltTokens.surface.withValues(alpha: 0.94),
      shape: const CircleBorder(),
      elevation: 2,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 20),
        color: ZveltTokens.text,
        onPressed: onTap,
      ),
    );
  }
}

// ─── Run / Bike pill toggle ──────────────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  const _ModeToggle(
      {required this.mode, required this.enabled, required this.onChanged});
  final String mode;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget pill(String value, IconData icon, String label) {
      final selected = mode == value;
      return GestureDetector(
        onTap: enabled ? () => onChanged(value) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: ZveltTokens.s3, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? ZveltTokens.brand : Colors.transparent,
            borderRadius: BorderRadius.circular(ZveltTokens.rPill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 15,
                  color: selected ? ZveltTokens.onBrand : ZveltTokens.text2),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? ZveltTokens.onBrand : ZveltTokens.text2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: ZveltTokens.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        border: Border.all(color: ZveltTokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          pill('run', AppIcons.running, 'Run'),
          pill('bike', AppIcons.bike, 'Bike'),
        ],
      ),
    );
  }
}
