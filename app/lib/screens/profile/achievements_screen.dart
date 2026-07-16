import 'dart:async';
import 'package:zvelt_app/theme/app_icons.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config/api_config.dart' show v1Base;
import '../../services/auth_service.dart';
import '../../theme/zvelt_tokens.dart';

enum _LoadError { auth, server, network, parse, unknown }

/// Lista completă achievement-uri (Excel #42 UI).
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  final _auth = AuthService();
  bool _loading = true;
  _LoadError? _loadError;
  List<Map<String, dynamic>> _achievements = [];
  int _totalEarned = 0;
  int _totalXp = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final token = await _auth.getAccessToken();
    if (token == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = _LoadError.auth;
        });
      }
      return;
    }
    try {
      final res = await http
          .get(
            Uri.parse('$v1Base/achievements/me'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode == 401 || res.statusCode == 403) {
        debugPrint('[Achievements] auth: HTTP ${res.statusCode}');
        setState(() {
          _loading = false;
          _loadError = _LoadError.auth;
        });
        return;
      }
      if (res.statusCode >= 500) {
        debugPrint('[Achievements] server: HTTP ${res.statusCode}');
        setState(() {
          _loading = false;
          _loadError = _LoadError.server;
        });
        return;
      }
      if (res.statusCode != 200) {
        debugPrint('[Achievements] unknown: HTTP ${res.statusCode}');
        setState(() {
          _loading = false;
          _loadError = _LoadError.unknown;
        });
        return;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (data['achievements'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _achievements = list;
        _totalEarned = data['totalEarned'] as int? ?? 0;
        _totalXp = data['totalXp'] as int? ?? 0;
        _loading = false;
      });
    } catch (e, stackTrace) {
      final _LoadError kind;
      if (e is SocketException || e is TimeoutException || e is http.ClientException) {
        kind = _LoadError.network;
      } else if (e is FormatException) {
        kind = _LoadError.parse;
      } else {
        kind = _LoadError.unknown;
      }
      debugPrint('[Achievements] ${kind.name}: $e\n$stackTrace');
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = kind;
        });
      }
    }
  }

  static final _errorCopy = <_LoadError, (String, String, IconData, Color)>{
    // 'Go back' not 'Sign in' — the button just pops to the shell; there is
    // no in-place re-auth flow, so promising a sign-in was a dead end.
    _LoadError.auth: ('Your session expired. Log out and back in from Profile.', 'Go back', AppIcons.lock, ZveltTokens.warn),
    _LoadError.server: ('Our backend hiccupped. Try again.', 'Retry', AppIcons.cloud_disabled, ZveltTokens.error),
    _LoadError.network: ('Check your connection.', 'Retry', AppIcons.cloud_disabled, ZveltTokens.warn),
    _LoadError.parse: ('Something went wrong reading the response.', 'Retry', AppIcons.picture, ZveltTokens.error),
    _LoadError.unknown: ("Couldn't load achievements.", 'Retry', AppIcons.exclamation, ZveltTokens.text2),
  };

  void _handleErrorAction(_LoadError kind) {
    if (kind == _LoadError.auth) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        title: const Text('Achievements'),
        actions: [
          IconButton(
            icon: const Icon(AppIcons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: ZveltTokens.brand))
          : _loadError != null
              ? _ErrorView(
                  copy: _errorCopy[_loadError!]!,
                  onAction: () => _handleErrorAction(_loadError!),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s3, ZveltTokens.s4, ZveltTokens.s2),
                      child: Row(
                        children: [
                          _SummaryChip(label: 'Unlocked', value: '$_totalEarned'),
                          const SizedBox(width: ZveltTokens.s3),
                          _SummaryChip(label: 'XP earned', value: '$_totalXp'),
                        ],
                      ),
                    ),
                    if (_achievements.isEmpty)
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(ZveltTokens.s8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(AppIcons.trophy,
                                    color: ZveltTokens.text3, size: 40),
                                const SizedBox(height: ZveltTokens.s3),
                                Text(
                                  'No achievements yet',
                                  style: TextStyle(
                                      color: ZveltTokens.text,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Complete workouts, build streaks and hit PRs to unlock your first one.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: ZveltTokens.text2, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, 0, ZveltTokens.s4, ZveltTokens.s8),
                        itemCount: _achievements.length,
                        separatorBuilder: (_, __) => const SizedBox(height: ZveltTokens.s2),
                        itemBuilder: (_, i) {
                          final a = _achievements[i];
                          final earned = a['earned'] == true;
                          return Container(
                            padding: const EdgeInsets.all(ZveltTokens.s4),
                            decoration: BoxDecoration(
                              color: ZveltTokens.surface,
                              borderRadius: BorderRadius.circular(ZveltTokens.rLg),
                              border: Border.all(
                                color: earned ? ZveltTokens.brand.withValues(alpha: 0.5) : ZveltTokens.border,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  earned ? AppIcons.trophy : AppIcons.lock,
                                  color: earned ? ZveltTokens.brand : ZveltTokens.text2,
                                  size: 28,
                                ),
                                const SizedBox(width: ZveltTokens.s3),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        a['title'] as String? ?? '',
                                        style: ZType.bodyM.copyWith(
                                          color: earned ? ZveltTokens.text : ZveltTokens.text2,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if ((a['description'] as String?)?.isNotEmpty == true) ...[
                                        const SizedBox(height: ZveltTokens.s1),
                                        Text(
                                          a['description'] as String,
                                          style: ZType.bodyS.copyWith(
                                            color: ZveltTokens.text2,
                                            height: 1.35,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 6),
                                      Text(
                                        'Tier ${a['tier'] ?? '?'} · +${a['xpReward'] ?? 0} XP',
                                        style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.copy, required this.onAction});
  final (String, String, IconData, Color) copy;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final (msg, cta, icon, color) = copy;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZveltTokens.s6),
        child: Container(
          padding: const EdgeInsets.all(ZveltTokens.s5),
          decoration: BoxDecoration(
            color: ZveltTokens.surface,
            borderRadius: BorderRadius.circular(ZveltTokens.rLg),
            boxShadow: ZveltTokens.shadowCard,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 36),
              const SizedBox(height: ZveltTokens.s3),
              Text(msg, textAlign: TextAlign.center, style: ZType.bodyM.copyWith(color: ZveltTokens.text2, height: 1.4)),
              const SizedBox(height: ZveltTokens.s4),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(backgroundColor: ZveltTokens.brand, foregroundColor: ZveltTokens.onBrand),
                child: Text(cta),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s3, horizontal: ZveltTokens.s4),
        decoration: BoxDecoration(
          color: ZveltTokens.surface,
          borderRadius: BorderRadius.circular(ZveltTokens.rLg),
          boxShadow: ZveltTokens.shadowCard,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: ZType.num_.copyWith(color: ZveltTokens.text, fontSize: 18, fontWeight: FontWeight.w700)),
            Text(label, style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
          ],
        ),
      ),
    );
  }
}
