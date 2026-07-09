import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config/api_config.dart' show v1Base;
import '../../l10n/app_strings.dart';
import '../../services/auth_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';
import '../profile_screen.dart';
import '../social/notifications_screen.dart';
import '../../services/social_notification_hub.dart';
import '../../widgets/z/z_card.dart';
import '../../widgets/z/z_loading.dart';
import '../../widgets/zvelt_secondary_button.dart';

/// Setări cont: date fizice, unități, privacy default, notificări în app, logout (Excel #8).
class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key, required this.onLogout});

  final Future<void> Function() onLogout;

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _auth = AuthService();
  String _unitSystem = 'metric';
  String _privacyDefault = 'friends';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = await _auth.getAccessToken();
    if (token == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final res = await http.get(
        Uri.parse('$v1Base/me'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final profile = data['profile'] as Map<String, dynamic>?;
        setState(() {
          _unitSystem = profile?['unitSystem'] as String? ?? 'metric';
          _privacyDefault = profile?['privacyDefault'] as String? ?? 'friends';
          _loading = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _patchProfile(Map<String, dynamic> body) async {
    final token = await _auth.getAccessToken();
    if (token == null) return;
    await http.patch(
      Uri.parse('$v1Base/me/profile'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
    await _load();
  }

  Future<void> _showUnits() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Units'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['metric', 'imperial']
              .map(
                (u) => ListTile(
                  title: Text(
                    u == 'metric' ? 'Metric (kg, cm)' : 'Imperial (lbs, in)',
                    style: TextStyle(color: ZveltTokens.text),
                  ),
                  trailing: _unitSystem == u
                      ? const Icon(AppIcons.check, color: ZveltTokens.brand)
                      : null,
                  onTap: () => Navigator.pop(ctx, u),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (result == null || !mounted) return;
    await _patchProfile({'unitSystem': result});
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Units updated')));
    }
  }

  Future<void> _showPrivacy() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Default post privacy'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            {'value': 'private', 'label': 'Private — only you'},
            {'value': 'friends', 'label': 'Friends — your connections'},
            {'value': 'public', 'label': 'Public — everyone'},
          ]
              .map(
                (item) => ListTile(
                  title: Text(
                    item['label']!,
                    style: ZType.bodyS
                        .copyWith(color: ZveltTokens.text, fontSize: 14),
                  ),
                  onTap: () => Navigator.pop(ctx, item['value']),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (result == null || !mounted) return;
    await _patchProfile({'privacyDefault': result});
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Privacy updated')));
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: Text(
          'You will need to sign in again.',
          style: TextStyle(color: ZveltTokens.text2),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ZveltTokens.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.of(context).pop();
      await widget.onLogout();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(title: const Text('Account settings')),
      body: _loading
          ? const ZPageSkeleton(showHeader: false, itemCount: 3)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Card(
                  children: [
                    _Tile(
                      icon: AppIcons.user,
                      title: 'Physical data',
                      subtitle: 'Body weight, height',
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const ProfileScreen()),
                        );
                        await _load();
                      },
                    ),
                    const _Divider(),
                    _Tile(
                      icon: AppIcons.ruler_horizontal,
                      title: 'Units',
                      subtitle: _unitSystem == 'metric'
                          ? 'Metric (kg, cm)'
                          : 'Imperial (lbs, in)',
                      onTap: _showUnits,
                    ),
                    const _Divider(),
                    _Tile(
                      icon: AppIcons.shield_check,
                      title: 'Default post privacy',
                      subtitle: _privacyLabel(_privacyDefault),
                      onTap: _showPrivacy,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Card(
                  children: [
                    _Tile(
                      icon: AppIcons.bell,
                      title: 'In-app notifications',
                      subtitle: 'Likes, comments, friend requests',
                      onTap: () async {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute(
                              builder: (_) => const NotificationsScreen()),
                        );
                        SocialNotificationHub.refresh();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Card(
                  children: [
                    _Tile(
                      icon: AppIcons.restaurant,
                      title: 'Nutrition goals',
                      subtitle:
                          'Set daily calories & macros in the Nutrition tab',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Open the Nutrition tab to edit goals and log meals.'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ZveltSecondaryButton(
                  label: AppStrings.logOut,
                  icon: AppIcons.sign_out_alt,
                  onTap: _confirmLogout,
                ),
              ],
            ),
    );
  }

  static String _privacyLabel(String v) {
    switch (v) {
      case 'private':
        return 'Private';
      case 'public':
        return 'Public';
      default:
        return 'Friends';
    }
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ZCard(
      padding: EdgeInsets.zero,
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: ZveltTokens.border);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: ZveltTokens.text2),
      title:
          Text(title, style: ZType.bodyM.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: ZType.bodyS),
      trailing: Icon(AppIcons.angle_small_right, color: ZveltTokens.text2),
      onTap: onTap,
    );
  }
}
