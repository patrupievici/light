import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../../services/_crash_reporter.dart';
import '../../services/moderation_service.dart';
import '../../services/report_outbox_service.dart';
import '../../theme/zvelt_tokens.dart';

/// Apple §1.2 / Play UGC moderation sheet — single-select category + optional
/// note, submitted to [ModerationService.reportUser].
///
/// Wave 22 P0.2 — on 404 (endpoint not deployed) we *no longer* tell the user
/// "Report submitted" (that was misleading — the backend never received it,
/// risking Apple §1.2 rejection). Instead the report is queued in the
/// encrypted [ReportOutboxService] and retried on every app foreground until
/// the backend ships. The UI copy honestly says "Queued for review" and the
/// blocked-users screen shows pending-report count.
class ReportUserSheet extends StatefulWidget {
  const ReportUserSheet({
    super.key,
    required this.userId,
    this.username,
    this.displayName,
    ModerationService? service,
  }) : _service = service;

  final String userId;
  final String? username;
  final String? displayName;
  final ModerationService? _service;

  /// Convenience launcher — call this from any overflow menu / long-press
  /// instead of constructing the sheet manually.
  static Future<void> show(
    BuildContext context, {
    required String userId,
    String? username,
    String? displayName,
    ModerationService? service,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ZveltTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
      ),
      builder: (_) => ReportUserSheet(
        userId: userId,
        username: username,
        displayName: displayName,
        service: service,
      ),
    );
  }

  @override
  State<ReportUserSheet> createState() => _ReportUserSheetState();
}

class _ReportUserSheetState extends State<ReportUserSheet> {
  late final ModerationService _service =
      widget._service ?? ModerationService();
  final _noteCtrl = TextEditingController();

  String? _category;
  bool _submitting = false;
  String? _inlineError;

  static const List<_ReportCategory> _categories = [
    _ReportCategory('spam', 'Spam or fake account'),
    _ReportCategory('harassment', 'Harassment or hate'),
    _ReportCategory('inappropriate', 'Inappropriate content'),
    _ReportCategory('impersonation', 'Impersonation'),
    _ReportCategory('csam', 'Child sexual abuse material'),
    _ReportCategory('other', 'Other'),
  ];

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  String get _title {
    final u = widget.username?.trim();
    if (u != null && u.isNotEmpty) return 'Report user @$u';
    final dn = widget.displayName?.trim();
    if (dn != null && dn.isNotEmpty) return 'Report $dn';
    return 'Report user';
  }

  Future<void> _submit() async {
    final cat = _category;
    if (cat == null || _submitting) return;
    setState(() {
      _submitting = true;
      _inlineError = null;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    try {
      await _service.reportUser(widget.userId, category: cat, note: _noteCtrl.text);
      if (!mounted) return;
      navigator.pop();
      messenger?.showSnackBar(
        const SnackBar(content: Text("Report submitted. We'll review within 24h.")),
      );
    } on ModerationException catch (e, st) {
      // Wave 22 P0.2 — 404 means backend isn't deployed yet. We must NOT lie
      // and say "Report submitted." Instead, queue the report in the
      // encrypted outbox so it retries on every foreground until the
      // endpoint goes live. Honest copy: "Queued for review".
      if (e.isNotDeployed) {
        try {
          await ReportOutboxService.shared().enqueue(
            targetUserId: widget.userId,
            category: cat,
            note: _noteCtrl.text,
          );
        } catch (qErr, qSt) {
          reportError(qErr, qSt, reason: 'moderation:report-enqueue');
        }
        if (!mounted) return;
        navigator.pop();
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              "Queued for review — we'll submit it as soon as our moderation service is online.",
            ),
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }
      reportError(e, st, reason: 'moderation:report-submit');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _inlineError = e.isNetworkError
            ? 'Network error — try again.'
            : 'Could not submit report. Try again.';
      });
    } catch (e, st) {
      reportError(e, st, reason: 'moderation:report-submit');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _inlineError = 'Could not submit report. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ZveltTokens.border,
                    borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                  ),
                ),
              ),
              const SizedBox(height: ZveltTokens.s4),
              Text(
                _title,
                style: ZType.h4.copyWith(
                  color: ZveltTokens.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: ZveltTokens.s2),
              Text(
                "Help us keep Zvelt safe. We'll review and take action.",
                style: ZType.bodyS.copyWith(color: ZveltTokens.text2, height: 1.4),
              ),
              const SizedBox(height: ZveltTokens.s4),
              ..._categories.map((c) => _CategoryTile(
                    category: c,
                    selected: _category == c.value,
                    onTap: () => setState(() => _category = c.value),
                  )),
              const SizedBox(height: ZveltTokens.s3),
              TextField(
                controller: _noteCtrl,
                maxLength: 500,
                maxLines: 3,
                style: TextStyle(color: ZveltTokens.text),
                decoration: const InputDecoration(
                  hintText: 'Add a note (optional)',
                ),
              ),
              if (_inlineError != null) ...[
                const SizedBox(height: ZveltTokens.s1),
                Text(
                  _inlineError!,
                  style: ZType.bodyS.copyWith(color: ZveltTokens.error),
                ),
              ],
              const SizedBox(height: ZveltTokens.s2),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_category == null || _submitting) ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ZveltTokens.onBrand,
                          ),
                        )
                      : const Text('Submit report'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportCategory {
  const _ReportCategory(this.value, this.label);
  final String value;
  final String label;
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final _ReportCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s2, horizontal: ZveltTokens.s1),
        child: Row(
          children: [
            Icon(
              selected ? AppIcons.badge_check : AppIcons.circle,
              size: 20,
              color: selected ? ZveltTokens.brand : ZveltTokens.text2,
            ),
            const SizedBox(width: ZveltTokens.s3),
            Expanded(
              child: Text(
                category.label,
                style: ZType.bodyM.copyWith(
                  color: ZveltTokens.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
