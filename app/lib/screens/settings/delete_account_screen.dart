import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:flutter/services.dart';

import '../../services/auth_service.dart';
import '../../theme/zvelt_tokens.dart';

/// Permanent account deletion flow.
///
/// Google Play policy requires every app with user accounts to expose a
/// reachable, in-app deletion path. This screen is that path.
///
/// Behavior:
///   1. Lists exactly what will be deleted (transparency).
///   2. Requires the user to type DELETE in a confirmation field.
///   3. Calls [AuthService.deleteAccount] which hits `DELETE /v1/me/account`.
///   4. On success, wipes ALL local prefs and invokes [onAccountDeleted] so
///      the host (AuthGate) can route the user back to the Welcome screen.
///   5. On failure, surfaces the real backend error (no silent dismissal).
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key, required this.onAccountDeleted});

  /// Called after a successful deletion. Host clears its own state and
  /// navigates the user out (typically to Welcome).
  final Future<void> Function() onAccountDeleted;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _auth = AuthService();
  final _confirmCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  static const _whatGetsDeleted = [
    ('Your profile', 'Name, photo, bio, preferences', AppIcons.user),
    ('All workouts', 'Sets, reps, PRs, history, rankings', AppIcons.gym),
    (
      'All posts & comments',
      'Your feed, likes, comments you authored',
      AppIcons.comment_alt
    ),
    ('Social graph', 'Friends, followers, segment memberships', AppIcons.users),
    (
      'Health data cache',
      'Heart rate, sleep, weight — local copies',
      AppIcons.heart
    ),
    (
      'Subscriptions',
      'Any active Pro entitlement (refunds via store)',
      AppIcons.crown
    ),
  ];

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool get _confirmValid => _confirmCtrl.text.trim().toUpperCase() == 'DELETE';

  Future<void> _doDelete() async {
    if (!_confirmValid || _busy) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.deleteAccount(confirmation: _confirmCtrl.text);
      if (!mounted) return;
      // Show a brief acknowledgement before navigating out, so user knows it
      // worked (avoids feeling like the app crashed).
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: ZveltTokens.surface,
          icon: const Icon(AppIcons.badge_check,
              color: ZveltTokens.success, size: 48),
          title: const Text('Account deleted'),
          content: Text(
            'Your account and personal data have been permanently deleted. '
            'You can reinstall Zvelt anytime to start fresh.',
            style: TextStyle(color: ZveltTokens.text2),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child:
                  const Text('OK', style: TextStyle(color: ZveltTokens.info)),
            ),
          ],
        ),
      );
      if (!mounted) return;
      await widget.onAccountDeleted();
    } on AccountDeletionException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Unexpected error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        backgroundColor: ZveltTokens.bg,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: Icon(AppIcons.angle_small_left,
              color: ZveltTokens.text, size: 28),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Delete account',
          style: ZType.h4
              .copyWith(color: ZveltTokens.text, fontWeight: FontWeight.w700),
        ),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              ZveltTokens.s5, ZveltTokens.s2, ZveltTokens.s5, ZveltTokens.s8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Warning banner
            Container(
              padding: const EdgeInsets.all(ZveltTokens.s4),
              decoration: BoxDecoration(
                color: ZveltTokens.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                border:
                    Border.all(color: ZveltTokens.error.withValues(alpha: 0.3)),
              ),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(AppIcons.exclamation,
                    color: ZveltTokens.error, size: 24),
                const SizedBox(width: ZveltTokens.s3),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'This is permanent',
                          style: ZType.bodyM.copyWith(
                              color: ZveltTokens.text,
                              fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: ZveltTokens.s1),
                        Text(
                          'Once deleted your account cannot be recovered. '
                          'If you only need a break, log out instead — your data stays safe.',
                          style: ZType.bodyS.copyWith(
                              color: ZveltTokens.text2.withValues(alpha: 0.95),
                              height: 1.45),
                        ),
                      ]),
                ),
              ]),
            ),
            const SizedBox(height: ZveltTokens.s6),
            Text(
              'What gets deleted',
              style: ZType.bodyS.copyWith(
                  color: ZveltTokens.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 0.4),
            ),
            const SizedBox(height: ZveltTokens.s2),
            Container(
              decoration: BoxDecoration(
                color: ZveltTokens.surface,
                borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                boxShadow: ZveltTokens.shadowCard,
              ),
              child: Column(
                children: List.generate(_whatGetsDeleted.length, (i) {
                  final item = _whatGetsDeleted[i];
                  return Container(
                    padding: const EdgeInsets.fromLTRB(ZveltTokens.s4,
                        ZveltTokens.s3, ZveltTokens.s4, ZveltTokens.s3),
                    decoration: BoxDecoration(
                      border: i == _whatGetsDeleted.length - 1
                          ? null
                          : Border(
                              bottom: BorderSide(
                                  color: ZveltTokens.border
                                      .withValues(alpha: 0.5))),
                    ),
                    child: Row(children: [
                      Icon(item.$3,
                          color: ZveltTokens.error.withValues(alpha: 0.85),
                          size: 18),
                      const SizedBox(width: ZveltTokens.s3),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.$1,
                                  style: ZType.bodyS.copyWith(
                                      color: ZveltTokens.text,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(item.$2,
                                  style: ZType.bodyS.copyWith(
                                      color: ZveltTokens.text2
                                          .withValues(alpha: 0.85),
                                      fontSize: 11)),
                            ]),
                      ),
                    ]),
                  );
                }),
              ),
            ),
            const SizedBox(height: ZveltTokens.s6),
            Container(
              padding: const EdgeInsets.all(ZveltTokens.s4),
              decoration: BoxDecoration(
                color: ZveltTokens.surface,
                borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                boxShadow: ZveltTokens.shadowCard,
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(AppIcons.stopwatch,
                          color: ZveltTokens.text2, size: 16),
                      const SizedBox(width: ZveltTokens.s2),
                      Text(
                        'Deletion timeline',
                        style: ZType.eyebrow.copyWith(
                            color: ZveltTokens.text2.withValues(alpha: 0.95),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4),
                      ),
                    ]),
                    const SizedBox(height: ZveltTokens.s2),
                    const _TimelineRow('Now',
                        'Account and personal data are permanently deleted.'),
                    const SizedBox(height: ZveltTokens.s2),
                    const _TimelineRow('Media',
                        'Profile, post and story media can no longer be accessed.'),
                    const SizedBox(height: ZveltTokens.s2),
                    const _TimelineRow('Note',
                        'Anonymous aggregate statistics may be retained per our privacy policy.'),
                  ]),
            ),
            const SizedBox(height: ZveltTokens.s6),
            Text(
              'Type DELETE to confirm',
              style: ZType.bodyS.copyWith(
                  color: ZveltTokens.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 0.4),
            ),
            const SizedBox(height: ZveltTokens.s2),
            Semantics(
              textField: true,
              label: 'Type DELETE to confirm',
              child: TextField(
                controller: _confirmCtrl,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                    color: ZveltTokens.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: 2),
                decoration: InputDecoration(
                  hintText: 'DELETE',
                  hintStyle: TextStyle(
                      color: ZveltTokens.text2.withValues(alpha: 0.4),
                      letterSpacing: 2),
                  filled: true,
                  fillColor: ZveltTokens.surface,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: ZveltTokens.s4, vertical: ZveltTokens.s4),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                      borderSide: BorderSide(color: ZveltTokens.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                      borderSide: BorderSide(color: ZveltTokens.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                      borderSide: const BorderSide(
                          color: ZveltTokens.error, width: 1.5)),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: ZveltTokens.s4),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
                decoration: BoxDecoration(
                  color: ZveltTokens.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                  border: Border.all(
                      color: ZveltTokens.error.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(AppIcons.exclamation,
                      color: ZveltTokens.error, size: 16),
                  const SizedBox(width: ZveltTokens.s2),
                  Expanded(
                      child: Text(_error!,
                          style: ZType.bodyS.copyWith(
                              color: ZveltTokens.error,
                              fontWeight: FontWeight.w600))),
                ]),
              ),
            ],
            const SizedBox(height: ZveltTokens.s6),
            // Destructive CTA
            Semantics(
              button: true,
              enabled: _confirmValid && !_busy,
              label: _busy ? 'Deleting account' : 'Delete my account',
              child: GestureDetector(
                onTap: _confirmValid && !_busy ? _doDelete : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 54,
                  decoration: BoxDecoration(
                    color: _confirmValid && !_busy
                        ? ZveltTokens.error
                        : ZveltTokens.error.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                    boxShadow: _confirmValid && !_busy
                        ? [
                            BoxShadow(
                                color: ZveltTokens.error.withValues(alpha: 0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 8))
                          ]
                        : null,
                  ),
                  child: Center(
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: ZveltTokens.onBrand))
                        : const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(AppIcons.trash,
                                color: ZveltTokens.onBrand, size: 18),
                            SizedBox(width: ZveltTokens.s2),
                            Text(
                              'DELETE MY ACCOUNT',
                              style: TextStyle(
                                  color: ZveltTokens.onBrand,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  letterSpacing: 1.8),
                            ),
                          ]),
                  ),
                ),
              ),
            ),
            const SizedBox(height: ZveltTokens.s3),
            // Cancel
            Center(
              child: TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: Text('Cancel',
                    style: ZType.bodyS.copyWith(
                        color: ZveltTokens.text2, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow(this.when, this.what);
  final String when;
  final String what;
  @override
  Widget build(BuildContext context) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 96,
          child: Text(
            when.toUpperCase(),
            style: ZType.eyebrow.copyWith(
                color: ZveltTokens.text2.withValues(alpha: 0.95),
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4),
          ),
        ),
        Expanded(
          child: Text(
            what,
            style: ZType.bodyS.copyWith(
                color: ZveltTokens.text,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.4),
          ),
        ),
      ]);
}
