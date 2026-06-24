import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../../services/stats_charts_service.dart';
import '../../theme/zvelt_tokens.dart';

/// PR feed for the Progress hub.
///
/// Shows rep-range personal records from the last [days] window. The value
/// over pure-1RM tracking: catches PRs that pure 1RM misses (100×5 after
/// 100×4 is a PR even though weight didn't move). This is how the app
/// surfaces 6-10 wins per month for a consistent user instead of 0-1.
class RecentPrsCard extends StatefulWidget {
  const RecentPrsCard({super.key, this.days = 30, this.maxItems = 8, this.service});

  final int days;
  final int maxItems;
  final StatsChartsService? service;

  @override
  State<RecentPrsCard> createState() => _RecentPrsCardState();
}

class _RecentPrsCardState extends State<RecentPrsCard> {
  late final StatsChartsService _service;
  List<RecentPr>? _prs;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? StatsChartsService();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _service.getRecentPrs(days: widget.days);
      if (!mounted) return;
      setState(() {
        _prs = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s4, ZveltTokens.s4, ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(AppIcons.trophy, color: ZveltTokens.brand, size: 18),
              const SizedBox(width: ZveltTokens.s2),
              Expanded(
                child: Text(
                  'PRs IN LAST ${widget.days} DAYS',
                  style: ZType.eyebrow.copyWith(color: ZveltTokens.text2),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: Icon(AppIcons.refresh, color: ZveltTokens.text2, size: 20),
                onPressed: _loading ? null : _load,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildBody(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: ZveltTokens.brand, strokeWidth: 2)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: ZType.bodyS,
        ),
      );
    }
    final prs = _prs ?? const <RecentPr>[];
    if (prs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: Text(
          "No PRs yet in this window — log a few work sets and we'll surface them here.",
          textAlign: TextAlign.center,
          style: ZType.bodyS,
        ),
      );
    }
    final shown = prs.take(widget.maxItems).toList();
    return Semantics(
      container: true,
      label: 'Personal records in the last ${widget.days} days',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) Divider(color: ZveltTokens.hairline, height: 1),
            _PrRow(pr: shown[i]),
          ],
          if (prs.length > shown.length)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '+${prs.length - shown.length} more',
                textAlign: TextAlign.center,
                style: ZType.monoXS.copyWith(color: ZveltTokens.text2),
              ),
            ),
        ],
      ),
    );
  }
}

class _PrRow extends StatelessWidget {
  const _PrRow({required this.pr});
  final RecentPr pr;

  String _relativeDate(String iso) {
    DateTime? dt;
    try {
      dt = DateTime.parse(iso).toLocal();
    } catch (_) {}
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inDays >= 7) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    return 'just now';
  }

  @override
  Widget build(BuildContext context) {
    final delta = pr.deltaKg;
    final deltaLabel = delta > 0
        ? '+${delta.toStringAsFixed(delta % 1 == 0 ? 0 : 1)} kg'
        : 'first';
    final deltaColor = delta > 0 ? ZveltTokens.success : ZveltTokens.brand;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: ZveltTokens.brand.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(ZveltTokens.rSm),
            ),
            alignment: Alignment.center,
            child: Text(
              '${pr.reps}',
              style: ZType.num_.copyWith(
                color: ZveltTokens.brand,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: ZveltTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pr.exerciseName,
                  style: ZType.clean.copyWith(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  pr.headline,
                  style: ZType.bodyS,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                deltaLabel,
                style: ZType.num_.copyWith(color: deltaColor, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                _relativeDate(pr.date),
                style: ZType.monoXS.copyWith(color: ZveltTokens.text2),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
