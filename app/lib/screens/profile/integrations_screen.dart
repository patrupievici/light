import 'dart:convert';
import 'package:zvelt_app/theme/app_icons.dart';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../config/api_config.dart' show v1Base;
import '../../services/_crash_reporter.dart';
import '../../services/auth_service.dart';
import '../../services/health_service.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/z/z_card.dart';

class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});

  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  final _auth = AuthService();
  bool _loading = true;
  Set<String> _connected = {};
  Map<String, DateTime> _lastSync = {};

  /// True only when Terra (wearable cloud aggregator) keys are set on the
  /// backend. While false, the 10 Terra wearable cards stay VISIBLE but render
  /// as disabled "Coming soon" tiles. Setting Terra keys server-side flips the
  /// `/integrations` response flag and auto-enables them — no client change.
  bool _aggregatorConfigured = false;

  /// Real connection state of the OS-level health integration (Apple Health on
  /// iOS, Health Connect on Android). `null` while we're still checking.
  bool? _nativeHealthConnected;
  /// On Android: false if the user needs to install Health Connect.
  bool _healthConnectNeedsInstall = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final token = await _auth.getAccessToken();
    if (token == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final res = await http.get(
        Uri.parse('$v1Base/integrations'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = data['integrations'] as List<dynamic>? ?? [];
        final agg = data['aggregator'];
        final aggregatorConfigured = agg is Map && agg['configured'] == true;
        // Parse defensively: each row comes from the network, so a single
        // null/missing `provider` or `updatedAt` must NOT abort the whole map
        // (which would silently render every integration as "Not connected").
        // Skip malformed rows instead.
        final connected = <String>{};
        final lastSync = <String, DateTime>{};
        for (final e in list) {
          if (e is! Map) continue;
          final provider = e['provider'] as String?;
          if (provider == null) continue;
          connected.add(provider);
          final updatedAt = e['updatedAt'] as String?;
          final parsed = updatedAt == null ? null : DateTime.tryParse(updatedAt);
          if (parsed != null) lastSync[provider] = parsed;
        }
        setState(() {
          _connected = connected;
          _lastSync = lastSync;
          _aggregatorConfigured = aggregatorConfigured;
        });
      }
    } catch (e, st) {
      reportError(e, st, reason: 'integrations:fetch-list');
    }
    // Native health integration (Apple Health iOS / Health Connect Android)
    // doesn't go through /v1/integrations — it's an on-device permission
    // managed by the system. Reflect REAL granted state here.
    if (!kIsWeb) {
      try {
        if (Platform.isAndroid) {
          final status = await HealthService.instance.checkAvailability();
          _healthConnectNeedsInstall =
              status == HealthConnectStatus.notInstalled ||
              status == HealthConnectStatus.updateRequired;
        }
        _nativeHealthConnected = await HealthService.instance.hasPermissions();
      } catch (e, st) {
        reportError(e, st, reason: 'integrations:native-health-status');
        _nativeHealthConnected = false;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Triggers the on-device Health Connect / Apple Health permission flow.
  /// Different from `_connect(provider)` which uses backend OAuth — native
  /// health is a system permission, never a backend OAuth.
  Future<void> _connectNativeHealth() async {
    final granted = await HealthService.instance.requestPermissions();
    var imported = 0;
    if (granted) {
      imported = await HealthService.instance.backfillRecentOnFirstGrant();
    }
    if (!mounted) return;
    setState(() => _nativeHealthConnected = granted);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(
      content: Text(granted
          ? (imported > 0
              ? 'Connected — recent history imported.'
              : 'Connected — recent health data is ready.')
          : 'Permission denied. You can re-try anytime in Settings.'),
    ));
  }

  Future<void> _openHealthConnectStore() async {
    final uri = Uri.parse(
      'https://play.google.com/store/apps/details?id=com.google.android.apps.healthdata',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _connect(String provider) async {
    final token = await _auth.getAccessToken();
    if (token == null) return;
    try {
      final res = await http.get(
        Uri.parse('$v1Base/integrations/$provider/auth-url'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final url = Uri.parse(data['url'] as String);
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      } else if (mounted) {
        // Non-200 (e.g. 501 when Terra/aggregator isn't configured) used to
        // silently do nothing — the button looked dead. Surface a friendly
        // notice so the user knows wearable cloud linking is on the way.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Coming soon — wearable cloud linking is on the way'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: ZveltTokens.error),
        );
      }
    }
  }

  Future<void> _sync(String provider) async {
    final token = await _auth.getAccessToken();
    if (token == null) return;
    try {
      final res = await http.post(
        Uri.parse('$v1Base/integrations/$provider/sync'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final count = data['imported'] as int? ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(count > 0 ? 'Imported $count activities' : 'Already up to date'),
            backgroundColor: ZveltTokens.recovery,
          ),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e'), backgroundColor: ZveltTokens.error),
        );
      }
    }
  }

  Future<void> _disconnect(String provider) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZveltTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        ),
        title: Text('Disconnect ${_providerLabel(provider)}?',
            style: ZType.h3.copyWith(color: ZveltTokens.text)),
        content: Text(
          'This removes access. Your imported workouts remain in Zvelt.',
          style: ZType.bodyM.copyWith(color: ZveltTokens.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: ZveltTokens.text2, fontWeight: FontWeight.w600)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ZveltTokens.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ZveltTokens.rPill),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final token = await _auth.getAccessToken();
    if (token == null) return;
    try {
      await http.delete(
        Uri.parse('$v1Base/integrations/$provider'),
        headers: {'Authorization': 'Bearer $token'},
      );
      await _load();
    } catch (e, st) {
      reportError(e, st, reason: 'integrations:disconnect');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(title: const Text('Connected apps')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: ZveltTokens.brand))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!kIsWeb && Platform.isIOS)
                    _IntegrationCard(
                      icon: AppIcons.heart,
                      name: 'Apple Health',
                      description: _nativeHealthConnected == true
                          ? 'Steps, calories, sleep, workouts — granted'
                          : 'Tap "Connect" to grant read & write access',
                      isConnected: _nativeHealthConnected == true,
                      onConnect: _connectNativeHealth,
                    ),
                  if (!kIsWeb && Platform.isAndroid)
                    _IntegrationCard(
                      icon: AppIcons.heart,
                      name: 'Health Connect',
                      description: _healthConnectNeedsInstall
                          ? 'Install Health Connect, or use cloud/bridge on Huawei'
                          : (_nativeHealthConnected == true
                              ? 'Steps, calories, sleep, workouts — granted'
                              : 'Tap "Connect" to grant read & write access'),
                      isConnected: _nativeHealthConnected == true,
                      onConnect: _healthConnectNeedsInstall
                          ? _openHealthConnectStore
                          : _connectNativeHealth,
                    ),
                  if (!kIsWeb && Platform.isAndroid) ...[
                    const SizedBox(height: 12),
                    _IntegrationCard(
                      icon: AppIcons.clock,
                      name: 'Galaxy Watch / Samsung Health',
                      description: _healthConnectNeedsInstall
                          ? 'Install Health Connect, then enable Samsung Health sync'
                          : (_nativeHealthConnected == true
                              ? 'Galaxy Watch data flows through Samsung Health'
                              : 'Enable Samsung Health -> Health Connect, then connect Zvelt'),
                      isConnected: _nativeHealthConnected == true,
                      onConnect: _healthConnectNeedsInstall
                          ? _openHealthConnectStore
                          : _connectNativeHealth,
                    ),
                  ],
                  // Strava — a FREE integration, independent of the Terra
                  // aggregator. Uses the same backend OAuth path as the other
                  // providers (GET /integrations/strava/auth-url).
                  const SizedBox(height: 12),
                  _IntegrationCard(
                    icon: AppIcons.running,
                    name: 'Strava',
                    description: 'Import runs and rides from Strava',
                    isConnected: _connected.contains('strava'),
                    lastSync: _lastSync['strava'],
                    onConnect: () => _connect('strava'),
                    onSync: () => _sync('strava'),
                    onDisconnect: () => _disconnect('strava'),
                  ),
                  const SizedBox(height: 12),
                  ...[
                    'garmin',
                    'fitbit',
                    'oura',
                    'polar',
                    'coros',
                    'whoop',
                    'suunto',
                    'withings',
                    'amazfit',
                    'huawei',
                    'wahoo',
                  ].map((provider) {
                    final meta = _providerMeta(provider);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _IntegrationCard(
                        icon: meta.icon,
                        name: meta.name,
                        description: meta.description,
                        isConnected: _connected.contains(provider),
                        lastSync: _lastSync[provider],
                        comingSoon: !_aggregatorConfigured,
                        onConnect: () => _connect(provider),
                        onSync: () => _sync(provider),
                        onDisconnect: () => _disconnect(provider),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }

  static String _providerLabel(String provider) {
    return _providerMeta(provider).name;
  }
}

class _ProviderMeta {
  const _ProviderMeta({
    required this.name,
    required this.description,
    required this.icon,
  });

  final String name;
  final String description;
  final IconData icon;
}

_ProviderMeta _providerMeta(String provider) {
  switch (provider) {
    case 'garmin':
      return const _ProviderMeta(
        name: 'Garmin Connect',
        description: 'Import activities and deep history from Garmin',
        icon: AppIcons.clock,
      );
    case 'fitbit':
      return const _ProviderMeta(
        name: 'Fitbit / Pixel Watch',
        description: 'Import activity, sleep and vitals from Fitbit',
        icon: AppIcons.running,
      );
    case 'oura':
      return const _ProviderMeta(
        name: 'Oura',
        description: 'Import sleep, readiness and activity from Oura',
        icon: AppIcons.moon,
      );
    case 'polar':
      return const _ProviderMeta(
        name: 'Polar Flow',
        description: 'Import workouts and heart-rate data from Polar',
        icon: AppIcons.heart,
      );
    case 'coros':
      return const _ProviderMeta(
        name: 'COROS',
        description: 'Import activities and training data from COROS',
        icon: AppIcons.clock,
      );
    case 'whoop':
      return const _ProviderMeta(
        name: 'WHOOP',
        description: 'Import strain, recovery and sleep through cloud sync',
        icon: AppIcons.heart,
      );
    case 'suunto':
      return const _ProviderMeta(
        name: 'Suunto',
        description: 'Import endurance workouts from Suunto',
        icon: AppIcons.navigation,
      );
    case 'withings':
      return const _ProviderMeta(
        name: 'Withings',
        description: 'Import scale, sleep and heart-health signals',
        icon: AppIcons.balance_scale_left,
      );
    case 'amazfit':
      return const _ProviderMeta(
        name: 'Amazfit / Zepp',
        description: 'Import health data from Amazfit and Zepp',
        icon: AppIcons.clock,
      );
    case 'huawei':
      return const _ProviderMeta(
        name: 'Huawei Health',
        description: 'Use cloud sync, Health Sync bridge or future HMS support',
        icon: AppIcons.shield_plus,
      );
    case 'wahoo':
      return const _ProviderMeta(
        name: 'Wahoo ELEMNT',
        description: 'Import rides and workouts from Wahoo',
        icon: AppIcons.bike,
      );
    // NOTE: no 'strava' case — Strava has its own dedicated card above and is
    // intentionally excluded from the cloud-wearable loop. Adding it here would
    // render Strava twice.
    default:
      return _ProviderMeta(
        name: provider,
        description: 'Connect your $provider account',
        icon: AppIcons.apps,
      );
  }
}

class _IntegrationCard extends StatelessWidget {
  const _IntegrationCard({
    required this.icon,
    required this.name,
    required this.description,
    required this.isConnected,
    this.comingSoon = false,
    this.lastSync,
    this.onConnect,
    this.onSync,
    this.onDisconnect,
  });

  final IconData icon;
  final String name;
  final String description;
  final bool isConnected;
  final bool isAlwaysOn = false;

  /// When true the card stays VISIBLE but is non-actionable: status pill reads
  /// "Coming soon" and the Connect/Sync/Disconnect row is omitted. Used to gate
  /// the Terra wearable providers while the aggregator isn't configured.
  final bool comingSoon;
  final DateTime? lastSync;
  final VoidCallback? onConnect;
  final VoidCallback? onSync;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final card = ZCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ZveltTokens.brandTint,
                  borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                ),
                child: Icon(icon, color: ZveltTokens.brand, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: ZType.h4.copyWith(
                            color: ZveltTokens.text, fontSize: 15)),
                    Text(description,
                        style: ZType.bodyS.copyWith(
                            color: ZveltTokens.text2, fontSize: 12)),
                  ],
                ),
              ),
              if (isConnected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: ZveltTokens.recovery.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                  ),
                  child: const Text('Connected',
                      style: TextStyle(
                        fontFamily: ZveltTokens.fontMono,
                        color: ZveltTokens.recovery,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      )),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: ZveltTokens.surface2,
                    borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                  ),
                  child: Text(comingSoon ? 'Coming soon' : 'Not connected',
                      style: TextStyle(
                        fontFamily: ZveltTokens.fontMono,
                        color: ZveltTokens.text3,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      )),
                ),
            ],
          ),
          if (lastSync != null) ...[
            const SizedBox(height: 6),
            Text(
              'Last synced: ${_formatRelative(lastSync!)}',
              style: TextStyle(
                fontFamily: ZveltTokens.fontMono,
                color: ZveltTokens.text3,
                fontSize: 11,
              ),
            ),
          ],
          if (!isAlwaysOn &&
              !comingSoon &&
              (!isConnected || onSync != null || onDisconnect != null)) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (!isConnected)
                  FilledButton.icon(
                    icon: const Icon(AppIcons.link, size: 16),
                    label: const Text('Connect'),
                    style: FilledButton.styleFrom(
                      backgroundColor: ZveltTokens.brand,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    onPressed: onConnect,
                  )
                else ...[
                  OutlinedButton.icon(
                    icon: const Icon(AppIcons.refresh, size: 16),
                    label: const Text('Sync now'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ZveltTokens.text,
                      side: BorderSide(color: ZveltTokens.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    onPressed: onSync,
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ZveltTokens.error,
                      side: const BorderSide(color: ZveltTokens.error),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    onPressed: onDisconnect,
                    child: const Text('Disconnect'),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
    return comingSoon ? Opacity(opacity: 0.6, child: card) : card;
  }

  static String _formatRelative(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
