import 'dart:io';
import 'package:zvelt_app/theme/app_icons.dart';

import 'package:flutter/material.dart';

import '../../services/_crash_reporter.dart';
import '../../services/body_measurements_service.dart';
import '../../services/social_notification_hub.dart';
import '../../services/stats_charts_service.dart';
import '../../services/nutrition_service.dart';
import '../../services/profile_service.dart';
import '../../services/photo_progress_service.dart';
import '../../services/workout_service.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/muscle_map_widget.dart';
import '../../widgets/zvelt_error_state.dart';
import '../../widgets/z/z_card.dart';
import '../../widgets/z/z_clean_stat_card.dart';
import '../../widgets/z/z_eyebrow.dart';
import '../../widgets/z/z_performance_trend.dart';
import '../../widgets/charts/volume_progression_chart.dart';
import '../../widgets/charts/workout_consistency_heatmap.dart';
import '../../widgets/charts/personal_records_timeline.dart';
import '../../widgets/charts/muscle_balance_chart.dart';
import '../../widgets/charts/rest_time_trend.dart';
import 'strength_analytics_screen.dart';
import 'hall_of_fame_screen.dart';
import 'photo_progress_screen.dart';
import 'training_metric_detail_screen.dart';
import '../social/notifications_screen.dart';
import '../../widgets/z/zvelt_charts.dart';

// Animated chart widgets moved to ../../widgets/z/zvelt_charts.dart —
// re-exported here so existing references keep working.
export '../../widgets/z/zvelt_charts.dart';

// (Fake hypnogram painter removed — sleep stages now render a real
// proportional bar from SleepDetails in the Biology tab.)

/// Push a TrainingMetricDetailScreen — shared by the Training/Health tab
/// cards (the design's `metric:*` routing contract).
void _pushMetric(BuildContext context, TrainingMetric m) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TrainingMetricDetailScreen(metric: m),
    ),
  );
}

/// Tappable navigator row used by the Training tab's metric list.
class _MetricNavRow extends StatelessWidget {
  const _MetricNavRow({
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
    return Semantics(
      button: true,
      label: title,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: ZveltTokens.brandTint,
                  borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                ),
                child: Icon(icon, size: 18, color: ZveltTokens.brand),
              ),
              const SizedBox(width: ZveltTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: ZType.h4
                            .copyWith(color: ZveltTokens.text, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
                  ],
                ),
              ),
              Icon(AppIcons.angle_small_right,
                  color: ZveltTokens.text3, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  PROGRESS HUB SCREEN
// ════════════════════════════════════════════════════════════════════

class ProgressHubScreen extends StatefulWidget {
  const ProgressHubScreen({super.key});

  @override
  State<ProgressHubScreen> createState() => _ProgressHubScreenState();
}

class _ProgressHubScreenState extends State<ProgressHubScreen> {
  int _tabIdx = 0;
  int _totalLp = 0;

  // Lazy-build flags: a sub-tab is only constructed the first time it is
  // visited (Training is built up front). Once built it is retained by its
  // AutomaticKeepAliveClientMixin, so revisits stay instant — but opening the
  // Progress tab no longer builds + paints all 5 heavy sub-tabs in one frame.
  final List<bool> _built = [true, false, false];

  // Light redesign (mockup 13): biology/health stripped — 3 tabs only.
  static const _tabs = ['Workouts', 'Nutrition', 'Body'];

  @override
  void initState() {
    super.initState();
    _loadTotalLp();
  }

  Future<void> _loadTotalLp() async {
    try {
      final points = await StatsChartsService().getRankLp(limit: 50);
      if (mounted) {
        setState(() => _totalLp = points.fold(0, (sum, p) => sum + p.lpTotal));
      }
    } catch (e, st) {
      reportError(e, st, reason: 'progress-hub:lp-total');
    }
  }

  void _go(String route) {
    if (route == 'strength') {
      Navigator.push<void>(context,
          MaterialPageRoute(builder: (_) => const StrengthAnalyticsScreen()));
    } else if (route == 'hof') {
      Navigator.push<void>(context,
          MaterialPageRoute(builder: (_) => const HallOfFameScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(
                  top: top + 6,
                  left: ZveltTokens.s5,
                  right: ZveltTokens.s5,
                  bottom: ZveltTokens.s4),
              child: _buildHeader(context),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  ZveltTokens.s4, 0, ZveltTokens.s4, ZveltTokens.s3),
              child: Column(
                children: [
                  _buildTopCards(),
                  const SizedBox(height: ZveltTokens.s3),
                  _buildTabPills(),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                ZveltTokens.s4, 0, ZveltTokens.s4, ZveltTokens.s8),
            sliver: SliverToBoxAdapter(child: _buildTabContent()),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 40),
        const Spacer(),
        Text(
          'Progress',
          style: ZType.h3.copyWith(color: ZveltTokens.text),
        ),
        const Spacer(),
        ValueListenableBuilder<int>(
          valueListenable: SocialNotificationHub.unreadCount,
          builder: (_, count, __) => Stack(
            clipBehavior: Clip.none,
            children: [
              Semantics(
                button: true,
                label: count > 0
                    ? 'Notifications, $count unread'
                    : 'Notifications',
                child: _IconBtn(
                  icon: AppIcons.bell,
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                  ),
                ),
              ),
              if (count > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: ZveltTokens.brand,
                      shape: BoxShape.circle,
                      border: Border.all(color: ZveltTokens.bg, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopCards() {
    // ── V2: white surface cards, brandTint icon halo, no aggressive gradients
    //    (orange = signal only per design-system §2).
    return Row(
      children: [
        Expanded(
          child: _TopCard(
            icon: AppIcons.bolt,
            iconHaloBg: ZveltTokens.brandTint,
            iconColor: ZveltTokens.brand,
            title: 'Strength',
            subtitle: 'e1RM & PRs',
            onTap: () => _go('strength'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _TopCard(
            icon: AppIcons.trophy,
            iconHaloBg: ZveltTokens.brandTint,
            iconColor: ZveltTokens.stress,
            title: 'Hall of Fame',
            subtitle: _totalLp > 0 ? '$_totalLp LP' : '— LP',
            onTap: () => _go('hof'),
          ),
        ),
      ],
    );
  }

  Widget _buildTabPills() {
    // ── V2 segmented control: light bg2 track, brand-tinted active pill,
    //    Inter labels — replaces the dark V1 nav strip.
    return Container(
      decoration: BoxDecoration(
        color: ZveltTokens.bg2,
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(_tabs.length, (i) {
          final active = _tabIdx == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _tabIdx = i;
                _built[i] = true;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                height: 34,
                decoration: BoxDecoration(
                  color: active ? ZveltTokens.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                  boxShadow: active ? ZveltTokens.shadowCard : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  _tabs[i],
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    letterSpacing: -0.01 * 12,
                    color: active ? ZveltTokens.text : ZveltTokens.text3,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTabContent() {
    // A lazy, gap-free tab host. IndexedStack sizes to the MAX height of all
    // its children, so switching to a shorter tab left a blank scroll gap under
    // it. A Stack of Offstage children instead lays out + sizes to ONLY the
    // active tab, while keeping visited tabs mounted (their State + loaded data
    // survive). Four layers of cost control:
    //   1. Lazy build — unvisited tabs are SizedBox.shrink() (never built); the
    //      active tab is always built (its _built flag is set in the pill tap).
    //   2. Offstage — inactive built tabs are neither laid out nor painted.
    //   3. TickerMode — inactive tabs pause their AnimationControllers (the
    //      coach-read shimmer + chart entry animations) instead of ticking.
    //   4. RepaintBoundary — isolates each tab's raster layer.
    Widget slot(int i, Widget child) {
      if (!_built[i]) return const SizedBox.shrink();
      return Offstage(
        offstage: _tabIdx != i,
        child: TickerMode(
          enabled: _tabIdx == i,
          child: RepaintBoundary(child: child),
        ),
      );
    }

    return Stack(
      key: const ValueKey('progress_tab_stack'),
      children: [
        slot(0, const _TrainingTab(key: ValueKey('training'))),
        slot(1, const _NutritionTab(key: ValueKey('nutrition'))),
        slot(2, const _BodyTab(key: ValueKey('body'))),
      ],
    );
  }
}

// ─── Top Card helper ─────────────────────────────────────────────────────────

class _TopCard extends StatelessWidget {
  const _TopCard({
    required this.icon,
    required this.iconHaloBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconHaloBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ZCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
          ZveltTokens.s4, ZveltTokens.s4, ZveltTokens.s4, ZveltTokens.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconHaloBg,
              borderRadius: BorderRadius.circular(ZveltTokens.rSm),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: ZType.h4.copyWith(color: ZveltTokens.text),
          ),
          const SizedBox(height: 2),
          ZEyebrow(subtitle),
        ],
      ),
    );
  }
}

// ─── Icon Button helper ───────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: ZveltTokens.surface,
            shape: BoxShape.circle,
            boxShadow: ZveltTokens.shadowCard,
          ),
          child: Icon(icon, size: 18, color: ZveltTokens.text2),
        ),
      );
}

// ════════════════════════════════════════════════════════════════════
//  TRAINING TAB
// ════════════════════════════════════════════════════════════════════

class _TrainingTab extends StatefulWidget {
  const _TrainingTab({super.key});

  @override
  State<_TrainingTab> createState() => _TrainingTabState();
}

class _TrainingTabState extends State<_TrainingTab>
    with AutomaticKeepAliveClientMixin {
  final _statsService = StatsChartsService();
  List<DailyTrainingPoint> _daily = [];
  bool _loading = true;
  // Set when the daily-training fetch fails — drives the ZveltErrorState +
  // RefreshIndicator retry path (previously a failure left a stub layout with
  // no way to recover without leaving the screen).
  bool _loadError = false;

  // ── Memoized build()-time aggregations ───────────────────────────────
  // Computed once in _recompute() when _daily lands in state, instead of as
  // getters re-derived on every build (each rebuild previously re-walked,
  // -reversed and re-parsed the 30-day series multiple times).
  List<double> _weekVolume = const [];
  List<String> _weekLabels = const [];
  int _sessionsThisMonth = 0;
  int _activeDaysThisWeek = 0;
  double? _volumeDeltaPct;
  List<String> _trendXLabels = const [];

  @override
  bool get wantKeepAlive => true;

  // Photo Progress preview state — last two photos shown on the hub card.
  List<ProgressPhoto> _recentPhotos = const [];

  /// AI weekly coach read. Null while loading; stays null on failure so the
  /// card hides itself cleanly without breaking the layout.
  String? _coachRead;
  bool _coachLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _loadRecentPhotos();
    _loadCoachRead();
  }

  Future<void> _loadCoachRead() async {
    // Try/finally so _coachLoading always flips off — the card hides itself
    // when both _coachRead is null AND _coachLoading is false (vs the
    // ambiguous "still loading" state where it shows a shimmer). Without
    // try/finally a slow Render cold-start would leave the shimmer forever.
    String? read;
    try {
      read = await WorkoutService().fetchWeeklyCoachRead();
    } catch (e, st) {
      reportError(e, st, reason: 'progress-hub:coach-read');
      read = null;
    } finally {
      if (mounted) {
        setState(() {
          _coachRead = read;
          _coachLoading = false;
        });
      }
    }
  }

  Future<void> _load() async {
    try {
      final data = await _statsService.getDailyTraining(days: 30);
      if (mounted) {
        setState(() {
          _daily = data;
          _loadError = false;
          _loading = false;
          _recompute();
        });
      }
    } catch (e, st) {
      reportError(e, st, reason: 'progress-hub:daily-training');
      if (mounted) {
        setState(() {
          _loadError = true;
          _loading = false;
        });
      }
    }
  }

  /// The last [n] elements of [list], preserving order. Fewer than [n] → all.
  static List<T> _lastN<T>(List<T> list, int n) =>
      list.length <= n ? List<T>.from(list) : list.sublist(list.length - n);

  /// Derive every chart/stat aggregation once when [_daily] changes — these
  /// used to be getters recomputed on each build().
  void _recompute() {
    // _daily arrives oldest-first (backend ORDER BY day ASC; the service does
    // not reverse). "This week" is therefore the LAST 7 entries, not the first —
    // taking the head showed ~30-day-old data as the current week.
    final last7 = _lastN(_daily, 7); // already chronological (oldest→newest)
    _weekVolume = last7.map((d) => d.volumeKg).toList();

    const dayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    _weekLabels = last7.map((d) {
      final dt = DateTime.tryParse(d.day);
      if (dt == null) return '';
      return dayInitials[dt.weekday - 1];
    }).toList();

    final now = DateTime.now();
    _sessionsThisMonth = _daily.where((d) {
      final dt = DateTime.tryParse(d.day);
      return dt != null &&
          dt.month == now.month &&
          dt.year == now.year &&
          d.sessions > 0;
    }).length;

    _activeDaysThisWeek = last7.where((d) => d.sessions > 0).length;

    // Volume change last 7 days vs prior 7 days, as signed percent. Null when
    // prior week has zero volume (would divide by zero / be meaningless).
    if (_daily.length < 14) {
      _volumeDeltaPct = null;
    } else {
      final lastWeek = last7.fold<double>(0, (a, d) => a + d.volumeKg);
      final priorWeek = _daily
          .sublist(_daily.length - 14, _daily.length - 7)
          .fold<double>(0, (a, d) => a + d.volumeKg);
      _volumeDeltaPct =
          priorWeek <= 0 ? null : ((lastWeek - priorWeek) / priorWeek) * 100;
    }

    _trendXLabels = _computeTrendXLabels();
  }

  /// 5 date labels evenly spaced across the trend series — first, last and
  /// 3 intermediates. Last is bolded by ZPerformanceTrend automatically.
  List<String> _computeTrendXLabels() {
    if (_daily.isEmpty) return const [];
    const monthNames = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    String fmt(String ymd) {
      final dt = DateTime.tryParse(ymd);
      if (dt == null) return '';
      return '${monthNames[dt.month - 1]} ${dt.day}';
    }
    // _daily is oldest-first; the last 7 entries are the current week already
    // in the oldest-first order the trend chart expects.
    final week = _lastN(_daily, 7);
    if (week.length < 5) return [for (final d in week) fmt(d.day)];
    return [
      fmt(week[0].day),
      fmt(week[(week.length * 0.25).round()].day),
      fmt(week[(week.length * 0.5).round()].day),
      fmt(week[(week.length * 0.75).round()].day),
      fmt(week.last.day),
    ];
  }

  Future<void> _loadRecentPhotos() async {
    try {
      final list = await PhotoProgressService.instance.listPhotos(limit: 2);
      if (mounted) setState(() => _recentPhotos = list);
    } catch (e, st) {
      reportError(e, st, reason: 'progress-hub:recent-photos');
      // Leave _recentPhotos as the previous list (empty on first load).
    }
  }

  Future<void> _openPhotoProgress() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const PhotoProgressScreen()),
    );
    // Reload preview thumbs in case the user added/deleted photos.
    if (mounted) await _loadRecentPhotos();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(color: ZveltTokens.brand, strokeWidth: 2),
        ),
      );
    }
    if (_loadError) {
      // Pull-to-refresh + explicit retry — matches the resilience pattern used
      // by sibling tabs (Health/Biology recover via their connect CTA's
      // onChanged: _load). The bounded RefreshIndicator works inside the
      // parent CustomScrollView's SliverToBoxAdapter.
      return RefreshIndicator(
        color: ZveltTokens.brand,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          shrinkWrap: true,
          children: [
            const SizedBox(height: 24),
            ZveltErrorState(
              tier: ZveltErrorTier.server,
              title: "Couldn't load your training",
              message: 'Pull down or tap to retry.',
              onRetry: () {
                setState(() => _loading = true);
                _load();
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
    }
    final volumeData = _weekVolume;
    final hasData = volumeData.isNotEmpty && volumeData.any((v) => v > 0);
    return Column(
      children: [
        // Weekly coach read — AI summary of the user's last 7 days
        _WeeklyCoachReadCard(read: _coachRead, loading: _coachLoading),
        if (_coachRead != null || _coachLoading) const SizedBox(height: 12),

        // ── V2 — Performance trend (volume series, 30-day) ─────────────
        ZPerformanceTrend(
          eyebrow: 'Training load · 30 days',
          value: volumeData.isNotEmpty ? volumeData.last.round().toString() : '—',
          unit: 'kg-reps',
          points: volumeData.isEmpty ? [0, 0, 0, 0, 0, 0, 0] : volumeData,
          deltaPct: _volumeDeltaPct,
          deltaLabel: (_volumeDeltaPct ?? 0) >= 0 ? 'improving' : 'pulling back',
          xLabels: _trendXLabels,
        ),
        const SizedBox(height: 12),

        // ── V2 — Sessions + active days side-by-side (CleanStatCard row)
        // Both tap into the Consistency detail (365-day view).
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _pushMetric(context, TrainingMetric.consistency),
                behavior: HitTestBehavior.opaque,
                child: ZCleanStatCard(
                  eyebrow: 'Sessions',
                  icon: AppIcons.gym,
                  value: '$_sessionsThisMonth',
                  unit: 'this month',
                  sparkValues: volumeData,
                  sparkBars: true,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () => _pushMetric(context, TrainingMetric.consistency),
                behavior: HitTestBehavior.opaque,
                child: ZCleanStatCard(
                  eyebrow: 'Active days',
                  icon: AppIcons.flame,
                  iconColor: ZveltTokens.brand,
                  value: '$_activeDaysThisWeek',
                  unit: '/ 7 this week',
                  sparkValues: volumeData.isNotEmpty
                      ? volumeData.map((v) => v > 0 ? 1.0 : 0.0).toList()
                      : const <double>[],
                  sparkBars: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Metric navigator rows (design: each Training metric card taps
        // into its MetricDetail screen) ─────────────────────────────────
        ZCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _MetricNavRow(
                icon: AppIcons.chart_histogram,
                title: 'Weekly volume',
                subtitle: 'Last 12 weeks · kg × reps',
                onTap: () => _pushMetric(context, TrainingMetric.volume),
              ),
              Divider(height: 1, color: ZveltTokens.border),
              _MetricNavRow(
                icon: AppIcons.arrow_trend_up,
                title: 'Strength progression',
                subtitle: 'e1RM trend per lift',
                onTap: () => _pushMetric(context, TrainingMetric.strength),
              ),
              Divider(height: 1, color: ZveltTokens.border),
              _MetricNavRow(
                icon: AppIcons.list,
                title: 'Top exercises',
                subtitle: 'Where your volume went · 30 days',
                onTap: () => _pushMetric(context, TrainingMetric.exercises),
              ),
              Divider(height: 1, color: ZveltTokens.border),
              _MetricNavRow(
                icon: AppIcons.calendar,
                title: 'Consistency',
                subtitle: 'Streaks & training days · 365 days',
                onTap: () => _pushMetric(context, TrainingMetric.consistency),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Daily Volume — taps into the Weekly volume detail.
        GestureDetector(
          onTap: () => _pushMetric(context, TrainingMetric.volume),
          behavior: HitTestBehavior.opaque,
          child: ZCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Daily Volume',
                          style: ZType.h3.copyWith(color: ZveltTokens.text)),
                      const SizedBox(height: 4),
                      const ZEyebrow('kg × reps'),
                    ]),
                    const _ChipBadge('7 Days'),
                  ],
                ),
                const SizedBox(height: 16),
                if (hasData)
                  Semantics(
                    label: 'Daily volume in kilograms times reps, last 7 days. '
                        'Latest ${volumeData.last.round()}',
                    child: ZveltBarChart(
                      data: volumeData,
                      height: 140,
                      activeIdx: volumeData.length - 1,
                      labels: _weekLabels,
                      delay: const Duration(milliseconds: 200),
                    ),
                  )
                else
                  Container(
                    height: 80,
                    alignment: Alignment.center,
                    child: Text('No workouts logged yet',
                        style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Detailed strength/volume charts (ported from the retired V1
        // analytics hub) — each fetches its own data. ─────────────────────
        const VolumeProgressionChart(),
        const SizedBox(height: 12),
        const WorkoutConsistencyHeatmap(),
        const SizedBox(height: 12),
        const PersonalRecordsTimeline(),
        const SizedBox(height: 12),
        const MuscleBalanceChart(),
        const SizedBox(height: 12),
        const RestTimeTrendChart(),
        const SizedBox(height: 12),

        // Photo Progress card — taps into the live PhotoProgressScreen.
        Semantics(
          button: true,
          label: 'Photo progress',
          child: GestureDetector(
          onTap: _openPhotoProgress,
          behavior: HitTestBehavior.opaque,
          child: ZCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const ZEyebrow('Photo Progress'),
                      Icon(AppIcons.angle_small_right,
                          color: ZveltTokens.text3, size: 18),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      ZveltTokens.s4, ZveltTokens.s1, ZveltTokens.s4, ZveltTokens.s5),
                  child: _recentPhotos.isEmpty
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                              child: Text(
                                'Track your transformation — take your first photo.',
                                style: ZType.bodyS.copyWith(
                                  color: ZveltTokens.text2,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            const Row(
                              children: [
                                Expanded(child: _PhotoProgressCard(label: 'Before')),
                                SizedBox(width: 10),
                                Expanded(child: _PhotoProgressCard(label: 'After')),
                              ],
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: _recentPhotos.length >= 2
                                  ? _PhotoProgressCard.fromFile(
                                      label: 'Before',
                                      file: _recentPhotos.last.file,
                                    )
                                  : const _PhotoProgressCard(label: 'Before'),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _PhotoProgressCard.fromFile(
                                label: 'After',
                                file: _recentPhotos.first.file,
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          ),
        ),
      ],
    );
  }
}

class _ChipBadge extends StatelessWidget {
  const _ChipBadge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: ZveltTokens.s3, vertical: ZveltTokens.s1),
        decoration: BoxDecoration(
          color: ZveltTokens.brandTint,
          borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: ZveltTokens.fontMono,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: ZveltTokens.brandDeep,
            letterSpacing: 0.02 * 11,
          ),
        ),
      );
}

class _PhotoProgressCard extends StatelessWidget {
  const _PhotoProgressCard({required this.label}) : file = null;
  const _PhotoProgressCard.fromFile({required this.label, required this.file});

  final String label;
  final File? file;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ZveltTokens.rMd),
          color: ZveltTokens.bg2,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            if (file != null)
              Positioned.fill(
                child: Semantics(
                  label: '$label progress photo',
                  image: true,
                  // Decode at ~2× the rendered width (cards sit two-up, each
                  // roughly half the content column) instead of the photo's
                  // full capture resolution — keeps memory/decode cost down
                  // without visible quality loss. LayoutBuilder reads the real
                  // box width so it stays correct across screen sizes.
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final dpr = MediaQuery.devicePixelRatioOf(context);
                      final cacheW =
                          (constraints.maxWidth * 2 * dpr).round().clamp(1, 4096).toInt();
                      return Image.file(
                        file!,
                        fit: BoxFit.cover,
                        cacheWidth: cacheW,
                      );
                    },
                  ),
                ),
              )
            else
              Center(
                child: Semantics(
                  label: 'No $label photo yet',
                  image: true,
                  child: CustomPaint(
                    size: const Size(60, 100),
                    painter: _BodySilhouettePainter(),
                  ),
                ),
              ),
            Positioned(
              top: 10,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: file != null
                      ? Colors.black.withValues(alpha: 0.45)
                      : ZveltTokens.surface,
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                  boxShadow: file != null ? null : ZveltTokens.shadowCard,
                ),
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontMono,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: file != null ? Colors.white : ZveltTokens.text2,
                    letterSpacing: 0.08 * 10,
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

class _BodySilhouettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = ZveltTokens.text4.withValues(alpha: 0.55);
    canvas.drawCircle(Offset(size.width / 2, 14), 9, p);
    final body = Path()
      ..moveTo(18, 26)
      ..lineTo(42, 26)
      ..lineTo(40, 50)
      ..quadraticBezierTo(30, 58, 20, 50)
      ..close();
    canvas.drawPath(body, p..color = ZveltTokens.text4.withValues(alpha: 0.45));
    final legPaint = Paint()..color = ZveltTokens.text4.withValues(alpha: 0.35);
    canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(20, 58, 8, 32), const Radius.circular(3)), legPaint);
    canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(32, 58, 8, 32), const Radius.circular(3)), legPaint);
  }

  @override
  bool shouldRepaint(_BodySilhouettePainter _) => false;
}

// ════════════════════════════════════════════════════════════════════
//  NUTRITION TAB
// ════════════════════════════════════════════════════════════════════

class _NutritionTab extends StatefulWidget {
  const _NutritionTab({super.key});

  @override
  State<_NutritionTab> createState() => _NutritionTabState();
}

class _NutritionTabState extends State<_NutritionTab>
    with AutomaticKeepAliveClientMixin {
  final _nutritionService = NutritionService.instance;
  DailyNutrition? _today;
  NutritionGoals _goals = const NutritionGoals();
  List<NutritionDaySnapshot> _history = [];
  bool _loading = true;

  // ── Memoized build()-time aggregations (computed in _recompute when data
  // lands, instead of as getters re-derived on every build). ──────────────
  int _loggedDays = 0;
  double _avgCalories = 0;
  List<NutritionDaySnapshot> _week = const [];
  List<String> _weekDayLabels = const [];
  // Today's 3 most-recent meals, sorted once here instead of on every build.
  List<MealEntry> _recentMeals = const [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _nutritionService.getDay(DateTime.now()),
        _nutritionService.getGoals(),
        _nutritionService.loadNutritionHistory(days: 28),
      ]);
      if (mounted) {
        setState(() {
          _today = results[0] as DailyNutrition;
          _goals = results[1] as NutritionGoals;
          _history = (results[2] as List).cast<NutritionDaySnapshot>();
          _loading = false;
          _recompute();
        });
      }
    } catch (e, st) {
      reportError(e, st, reason: 'progress-hub:nutrition-load');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Derive the chart/stat aggregations once when [_history] changes.
  void _recompute() {
    _loggedDays = _history.where((d) => d.calories > 0).length;

    final logged = _history.where((d) => d.calories > 0).toList();
    _avgCalories = logged.isEmpty
        ? 0
        : logged.fold(0.0, (sum, d) => sum + d.calories) / logged.length;

    // Last 7 days oldest-first — the design's "Weekly calories" bar chart.
    // _history is built oldest-first, so the CURRENT week is the last 7 entries
    // (taking the head + reversing showed the oldest week, newest-bar-first).
    _week = _history.length <= 7
        ? List<NutritionDaySnapshot>.from(_history)
        : _history.sublist(_history.length - 7);

    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    _weekDayLabels = [for (final d in _week) days[d.date.weekday - 1]];

    final entries = _today?.entries;
    if (entries == null || entries.isEmpty) {
      _recentMeals = const [];
    } else {
      final sorted = entries.toList()
        ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
      _recentMeals = sorted.take(3).toList();
    }
  }

  double _pct(double val, double total) => total > 0 ? (val / total * 100).clamp(0, 100) : 0;

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(color: ZveltTokens.brand, strokeWidth: 2),
        ),
      );
    }
    final today = _today;
    final todayKcal = today?.totalCalories ?? 0.0;
    final proteinG = today?.totalProtein ?? 0.0;
    final carbsG = today?.totalCarbs ?? 0.0;
    final fatG = today?.totalFat ?? 0.0;
    final week = _week;
    final weekPoints = [for (final d in week) d.calories];
    return Column(
      children: [
        // Weekly calories — design: 7 bars with M–S labels (was a 28-day
        // area chart). Stat = 28-day logged average, same real history.
        ZCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Weekly calories',
                        style: ZType.h3.copyWith(color: ZveltTokens.text)),
                    const SizedBox(height: 4),
                    const ZEyebrow('Last 7 days'),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(_avgCalories > 0 ? _avgCalories.round().toString() : '—',
                        style: ZType.stat.copyWith(fontSize: 28, color: ZveltTokens.text)),
                    const SizedBox(height: 4),
                    const ZEyebrow('avg kcal · 28d'),
                  ]),
                ],
              ),
              const SizedBox(height: ZveltTokens.s5),
              if (weekPoints.isNotEmpty && weekPoints.any((v) => v > 0))
                Semantics(
                  label: 'Weekly calories, last 7 days. '
                      'Average ${_avgCalories.round()} kcal over 28 days',
                  child: ZveltBarChart(
                    data: weekPoints,
                    height: 90,
                    labels: _weekDayLabels,
                    activeIdx: weekPoints.length - 1,
                    delay: const Duration(milliseconds: 200),
                  ),
                )
              else
                Container(
                  height: 60,
                  alignment: Alignment.center,
                  child: Text('No nutrition data yet',
                      style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Macro rings
        ZCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const ZEyebrow('Macros · Today'),
                  Text(
                    '${todayKcal.round()} / ${_goals.calories} kcal',
                    style: TextStyle(
                      fontFamily: ZveltTokens.fontMono,
                      fontSize: 11,
                      color: ZveltTokens.text3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ZveltTokens.s5),
              Row(
                children: [
                  _MacroRing(
                    label: 'Protein',
                    value: _pct(proteinG, _goals.proteinG.toDouble()),
                    grams: '${proteinG.round()}g',
                    total: '${_goals.proteinG}g',
                    color: ZveltTokens.strength,
                  ),
                  _MacroRing(
                    label: 'Carbs',
                    value: _pct(carbsG, _goals.carbsG.toDouble()),
                    grams: '${carbsG.round()}g',
                    total: '${_goals.carbsG}g',
                    color: ZveltTokens.brand,
                  ),
                  _MacroRing(
                    label: 'Fats',
                    value: _pct(fatG, _goals.fatG.toDouble()),
                    grams: '${fatG.round()}g',
                    total: '${_goals.fatG}g',
                    color: ZveltTokens.strain,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Hydration — design: 10 cups, filled ∝ today's real water intake
        // (same NutritionService store the Nutrition tab's +water writes to).
        ZCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const ZEyebrow('Hydration · Today'),
                  Text(
                    '${((today?.waterMl ?? 0) / 1000).toStringAsFixed(1)} / ${(_goals.waterMl / 1000).toStringAsFixed(1)} L',
                    style: TextStyle(
                      fontFamily: ZveltTokens.fontMono,
                      fontSize: 11,
                      color: ZveltTokens.text3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ZveltTokens.s4),
              _HydrationCups(
                filled: _goals.waterMl > 0
                    ? ((today?.waterMl ?? 0) / _goals.waterMl * 10)
                        .floor()
                        .clamp(0, 10)
                    : 0,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Recent meals — design: last meals list; real entries from today.
        ZCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ZEyebrow('Recent meals'),
              const SizedBox(height: 4),
              if (today == null || today.entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text('No meals logged today',
                      style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
                )
              else
                for (var i = 0; i < _recentMeals.length; i++) ...[
                  if (i > 0) Container(height: 1, color: ZveltTokens.border),
                  _RecentMealRow(entry: _recentMeals[i]),
                ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Consistency score
        ZCard(
          color: ZveltTokens.surfaceTinted,
          padding: const EdgeInsets.fromLTRB(
              ZveltTokens.s5, ZveltTokens.s4, ZveltTokens.s5, ZveltTokens.s4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ZEyebrow('Consistency score'),
                    const SizedBox(height: 6),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '$_loggedDays / ${_history.length} ',
                            style: ZType.stat.copyWith(
                              fontSize: 24,
                              color: ZveltTokens.text,
                            ),
                          ),
                          TextSpan(
                            text: 'days',
                            style: ZType.bodyS.copyWith(
                              color: ZveltTokens.text3,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _history.isEmpty
                          ? 'No data yet'
                          : '↑ Logged ${(_loggedDays / _history.length * 100).round()}% of days',
                      style: const TextStyle(
                        fontSize: 11,
                        color: ZveltTokens.success,
                        fontWeight: FontWeight.w600,
                        fontFamily: ZveltTokens.fontPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Semantics(
                label: 'Consistency score: logged $_loggedDays of '
                    '${_history.length} days'
                    '${_history.isEmpty ? '' : ', ${(_loggedDays / _history.length * 100).round()} percent'}',
                child: ZveltRingChart(
                  value: _history.isEmpty ? 0 : _loggedDays / _history.length * 100,
                  size: 70,
                  strokeWidth: 6,
                  delay: const Duration(milliseconds: 300),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Design's hydration row: 10 cup slots, filled ones get the blue water
/// gradient, empty ones stay surface-2. Filled count comes from REAL intake.
class _HydrationCups extends StatelessWidget {
  const _HydrationCups({required this.filled});
  final int filled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Hydration: $filled of 10 cups filled',
      child: Row(
        children: [
          for (var i = 0; i < 10; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Expanded(
              child: Container(
                height: 34,
                decoration: BoxDecoration(
                  gradient: i < filled
                      ? const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [ZveltTokens.recovery2, ZveltTokens.recovery],
                        )
                      : null,
                  color: i < filled ? null : ZveltTokens.surface2,
                  borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                ),
                child: i < filled
                    ? const Icon(AppIcons.water_bottle,
                        color: Colors.white, size: 13)
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One row in the Recent-meals card — food name, meal slot, real kcal.
class _RecentMealRow extends StatelessWidget {
  const _RecentMealRow({required this.entry});
  final MealEntry entry;

  String get _mealLabel {
    final m = entry.meal;
    if (m.isEmpty) return '';
    return m[0].toUpperCase() + m.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.food.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_mealLabel · ${entry.grams.round()}g',
                  style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${entry.calories.round()} kcal',
            style: TextStyle(
              fontFamily: ZveltTokens.fontMono,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ZveltTokens.text2,
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroRing extends StatelessWidget {
  const _MacroRing({
    required this.label,
    required this.value,
    required this.grams,
    required this.total,
    required this.color,
  });
  final String label;
  final double value;
  final String grams;
  final String total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Semantics(
            label: '$label: $grams of $total, ${value.round()} percent',
            child: ZveltRingChart(value: value, size: 68, strokeWidth: 6,
                color: color, delay: const Duration(milliseconds: 250)),
          ),
          const SizedBox(height: 8),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              children: [
                TextSpan(
                  text: grams,
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontMono,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: ZveltTokens.text,
                  ),
                ),
                TextSpan(
                  text: ' / $total',
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontMono,
                    fontSize: 11,
                    color: ZveltTokens.text3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          ZEyebrow(label),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  HEALTH TAB
// ════════════════════════════════════════════════════════════════════

class _BodyTab extends StatefulWidget {
  const _BodyTab({super.key});

  @override
  State<_BodyTab> createState() => _BodyTabState();
}

class _BodyTabState extends State<_BodyTab>
    with AutomaticKeepAliveClientMixin {
  double? _currentWeightKg;
  List<double> _weightHistory = [];
  List<BodyMeasurement> _measurements = [];
  bool _loading = true;

  // Period state lives here (not on the parent) so _BodyTab can be a const
  // child of the hub's tab Stack — a tab-pill tap or LP/notification setState
  // on the hub no longer re-creates and rebuilds this whole subtree.
  String _period = '1W';

  /// Period → history window. The picker actually re-fetches when changed.
  static const _periodDays = {'1W': 7, '1M': 30, '3M': 90, '1Y': 365};
  int get _days => _periodDays[_period] ?? 30;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _onPeriodChange(String p) {
    if (p == _period) return;
    setState(() => _period = p);
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ProfileService().getMe(),
        NutritionService.instance.loadNutritionHistory(days: _days),
        BodyMeasurementsService.instance.list(),
      ]);
      final profile = results[0] as Map<String, dynamic>?;
      final history = (results[1] as List).cast<NutritionDaySnapshot>();
      final measurements = (results[2] as List).cast<BodyMeasurement>();
      final weightPoints = history
          .where((d) => d.weightKg != null && d.weightKg! > 0)
          .map((d) => d.weightKg!)
          .toList();
      if (mounted) {
        setState(() {
          // bodyweightKg is a Prisma Decimal → arrives as a JSON string, so a
          // raw `as num` cast throws and aborts this setState (weight history +
          // measurements then silently fail to load).
          final bw = profile?['bodyweightKg'];
          _currentWeightKg =
              bw is num ? bw.toDouble() : double.tryParse(bw?.toString() ?? '');
          _weightHistory = weightPoints;
          _measurements = measurements;
          _loading = false;
        });
      }
    } catch (e, st) {
      reportError(e, st, reason: 'progress-hub:weight-load');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openLogMeasurements() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ZveltTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
      ),
      builder: (_) => _LogMeasurementsSheet(
        latest: _measurements.isNotEmpty ? _measurements.first : null,
      ),
    );
    if (saved == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(color: ZveltTokens.brand, strokeWidth: 2),
        ),
      );
    }
    final weightKg = _currentWeightKg;
    return Column(
      children: [
        // Period header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Body',
                style: ZType.h3.copyWith(color: ZveltTokens.text)),
            _PeriodPicker(value: _period, onChanged: _onPeriodChange),
          ],
        ),
        const SizedBox(height: 12),

        // ── Body composition (design: silhouette + weight / body fat /
        // lean mass). REAL inputs: weight from the profile/nutrition log,
        // body fat from the user's measurements log; lean mass derived
        // (weight × (1 − bf)). Missing pieces show honest dashes.
        Builder(builder: (context) {
          final bf = BodyMeasurementsService.latestWithDelta(
              _measurements, (m) => m.bodyFatPct);
          final double? lean = (weightKg != null && bf != null)
              ? weightKg * (1 - bf.value / 100)
              : null;
          return ZCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 64,
                  height: 92,
                  child: Semantics(
                    label: 'Body composition illustration',
                    image: true,
                    child: CustomPaint(
                      size: const Size(60, 92),
                      painter: _BodySilhouettePainter(),
                    ),
                  ),
                ),
                const SizedBox(width: ZveltTokens.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ZEyebrow('Body composition'),
                      const SizedBox(height: 4),
                      Text(
                        weightKg != null
                            ? '${weightKg.toStringAsFixed(1)} kg'
                            : '— kg',
                        style: ZType.h4,
                      ),
                      const SizedBox(height: 6),
                      Text.rich(
                        TextSpan(
                          text: 'Body fat: ',
                          children: [
                            TextSpan(
                              text: bf != null
                                  ? '${bf.value.toStringAsFixed(1)}%'
                                  : 'not logged',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        style: TextStyle(
                            fontSize: 12, color: ZveltTokens.text2),
                      ),
                      Text.rich(
                        TextSpan(
                          text: 'Lean mass: ',
                          children: [
                            TextSpan(
                              text: lean != null
                                  ? '${lean.toStringAsFixed(1)} kg'
                                  : '—',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        style: TextStyle(
                            fontSize: 12, color: ZveltTokens.text2),
                      ),
                      if (bf == null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Log body fat under Measurements to complete this card.',
                          style: ZType.bodyS.copyWith(
                              color: ZveltTokens.text3, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 12),

        // Muscle recovery map (moved here from the Train tab).
        const MuscleMapCard(),
        const SizedBox(height: 12),

        // Weight area chart hero
        ZCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const ZEyebrow('Body Weight'),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(weightKg != null ? weightKg.toStringAsFixed(1) : '—',
                            style: ZType.stat.copyWith(fontSize: 42, color: ZveltTokens.text)),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6, left: 6),
                          child: Text('kg',
                              style: TextStyle(
                                fontFamily: ZveltTokens.fontMono,
                                fontSize: 13,
                                color: ZveltTokens.text3,
                                fontWeight: FontWeight.w500,
                              )),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      weightKg != null ? 'Update in Nutrition tab' : 'Log weight in Nutrition tab',
                      style: ZType.bodyS.copyWith(color: ZveltTokens.text3, fontSize: 12),
                    ),
                  ]),
                  _ChipBadge(_period),
                ],
              ),
              const SizedBox(height: ZveltTokens.s4),
              if (_weightHistory.length >= 2)
                Semantics(
                  label: 'Body weight trend over $_period'
                      '${weightKg != null ? ', latest ${weightKg.toStringAsFixed(1)} kg' : ''}',
                  child: ZveltAreaChart(
                    points: _weightHistory,
                    height: 120,
                    xLabels: const [],
                    delay: const Duration(milliseconds: 200),
                  ),
                )
              else
                Container(
                  height: 60,
                  alignment: Alignment.center,
                  child: Text('Log weight daily to see trend',
                      style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Measurements — design's list (Chest / Waist / Arms / Thighs with
        // deltas). Replaces the old all-"Not tracked" placeholder grid:
        // values are user-logged via the "+ Log" sheet (local-first store),
        // deltas computed vs the previous log — real numbers or honest copy.
        ZCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const ZEyebrow('Measurements'),
                    Semantics(
                      button: true,
                      label: 'Log measurements',
                      child: GestureDetector(
                      onTap: _openLogMeasurements,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: ZveltTokens.s3, vertical: ZveltTokens.s1),
                        decoration: BoxDecoration(
                          color: ZveltTokens.brandTint,
                          borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                        ),
                        child: const Text('+ Log',
                            style: TextStyle(
                              fontFamily: ZveltTokens.fontPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: ZveltTokens.brandDeep,
                            )),
                      ),
                    ),
                    ),
                  ],
                ),
              ),
              if (_measurements.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                  child: Text(
                    'Log chest, waist, arms & thighs to track changes over time.',
                    style: ZType.bodyS.copyWith(color: ZveltTokens.text2, height: 1.45),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                  child: Column(
                    children: [
                      _MeasurementRow(label: 'Chest', unit: 'cm', all: _measurements, pick: (m) => m.chestCm),
                      _MeasurementRow(label: 'Waist', unit: 'cm', all: _measurements, pick: (m) => m.waistCm, lowerIsBetter: true),
                      _MeasurementRow(label: 'Arms', unit: 'cm', all: _measurements, pick: (m) => m.armsCm),
                      _MeasurementRow(label: 'Thighs', unit: 'cm', all: _measurements, pick: (m) => m.thighsCm),
                      _MeasurementRow(label: 'Body fat', unit: '%', all: _measurements, pick: (m) => m.bodyFatPct, lowerIsBetter: true, last: true),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Visual Evidence
        ZCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const ZEyebrow('Visual Evidence'),
                    Semantics(
                      button: true,
                      label: 'Add progress photo',
                      child: GestureDetector(
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(builder: (_) => const PhotoProgressScreen()),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: ZveltTokens.s3, vertical: ZveltTokens.s1),
                        decoration: BoxDecoration(
                          color: ZveltTokens.brandTint,
                          borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                        ),
                        child: const Text('+ Add photo',
                            style: TextStyle(
                              fontFamily: ZveltTokens.fontPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: ZveltTokens.brandDeep,
                            )),
                      ),
                    ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(
                    ZveltTokens.s4, ZveltTokens.s1, ZveltTokens.s4, ZveltTokens.s5),
                child: Row(
                  children: [
                    Expanded(child: _PhotoProgressCard(label: 'Before')),
                    SizedBox(width: 10),
                    Expanded(child: _PhotoProgressCard(label: 'After')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One measurement row — design's list: label left, latest value + signed
/// delta vs the previous log on the right. Skips nothing: a never-logged
/// field shows an honest '—'.
class _MeasurementRow extends StatelessWidget {
  const _MeasurementRow({
    required this.label,
    required this.unit,
    required this.all,
    required this.pick,
    this.lowerIsBetter = false,
    this.last = false,
  });

  final String label;
  final String unit;
  final List<BodyMeasurement> all;
  final double? Function(BodyMeasurement) pick;
  /// Waist & body fat: a decrease reads as progress (green).
  final bool lowerIsBetter;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final latest = BodyMeasurementsService.latestWithDelta(all, pick);
    final delta = latest?.delta;
    String deltaLabel = '';
    Color deltaColor = ZveltTokens.text3;
    if (latest != null && delta != null && delta.abs() >= 0.05) {
      deltaLabel = '${delta > 0 ? '+' : '−'}${delta.abs().toStringAsFixed(1)} $unit';
      final improving = lowerIsBetter ? delta < 0 : delta > 0;
      deltaColor = improving ? ZveltTokens.success : ZveltTokens.text3;
    } else if (latest != null && delta != null) {
      deltaLabel = 'no change';
    } else if (latest != null) {
      deltaLabel = 'first log';
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s3),
      decoration: last
          ? null
          : BoxDecoration(
              border: Border(bottom: BorderSide(color: ZveltTokens.border)),
            ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: ZType.bodyS.copyWith(color: ZveltTokens.text2, fontSize: 13)),
          ),
          if (deltaLabel.isNotEmpty) ...[
            Text(deltaLabel,
                style: TextStyle(
                  fontFamily: ZveltTokens.fontPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: deltaColor,
                )),
            const SizedBox(width: 10),
          ],
          Text(
            latest != null ? '${latest.value.toStringAsFixed(1)} $unit' : '—',
            style: TextStyle(
              fontFamily: ZveltTokens.fontMono,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: latest != null ? ZveltTokens.text : ZveltTokens.text3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet behind "+ Log" — numeric fields for the design's four
/// measurements + optional body fat. Pre-fills from the latest log; saves
/// only the fields the user filled (validated against sanity bounds).
class _LogMeasurementsSheet extends StatefulWidget {
  const _LogMeasurementsSheet({this.latest});
  final BodyMeasurement? latest;

  @override
  State<_LogMeasurementsSheet> createState() => _LogMeasurementsSheetState();
}

class _LogMeasurementsSheetState extends State<_LogMeasurementsSheet> {
  late final TextEditingController _chest;
  late final TextEditingController _waist;
  late final TextEditingController _arms;
  late final TextEditingController _thighs;
  late final TextEditingController _bodyFat;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    String pre(double? v) => v != null ? v.toStringAsFixed(1) : '';
    _chest = TextEditingController(text: pre(widget.latest?.chestCm));
    _waist = TextEditingController(text: pre(widget.latest?.waistCm));
    _arms = TextEditingController(text: pre(widget.latest?.armsCm));
    _thighs = TextEditingController(text: pre(widget.latest?.thighsCm));
    _bodyFat = TextEditingController(text: pre(widget.latest?.bodyFatPct));
  }

  @override
  void dispose() {
    _chest.dispose();
    _waist.dispose();
    _arms.dispose();
    _thighs.dispose();
    _bodyFat.dispose();
    super.dispose();
  }

  double? _parse(TextEditingController c, double min, double max, String label) {
    final raw = c.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    final v = double.tryParse(raw);
    if (v == null || v < min || v > max) {
      throw FormatException('$label must be ${min.round()}–${max.round()}');
    }
    return v;
  }

  Future<void> _save() async {
    setState(() => _error = null);
    final BodyMeasurement m;
    try {
      m = BodyMeasurement(
        date: DateTime.now(),
        chestCm: _parse(_chest, BodyMeasurementsService.minCm, BodyMeasurementsService.maxCm, 'Chest'),
        waistCm: _parse(_waist, BodyMeasurementsService.minCm, BodyMeasurementsService.maxCm, 'Waist'),
        armsCm: _parse(_arms, BodyMeasurementsService.minCm, BodyMeasurementsService.maxCm, 'Arms'),
        thighsCm: _parse(_thighs, BodyMeasurementsService.minCm, BodyMeasurementsService.maxCm, 'Thighs'),
        bodyFatPct: _parse(_bodyFat, BodyMeasurementsService.minBodyFatPct, BodyMeasurementsService.maxBodyFatPct, 'Body fat'),
      );
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    if (m.isEmpty) {
      setState(() => _error = 'Fill in at least one measurement.');
      return;
    }
    setState(() => _saving = true);
    await BodyMeasurementsService.instance.log(m);
    if (mounted) Navigator.of(context).pop(true);
  }

  Widget _field(String label, String unit, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: ZType.bodyS.copyWith(color: ZveltTokens.text, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          suffixText: unit,
          labelStyle: ZType.bodyS.copyWith(color: ZveltTokens.text3),
          suffixStyle: ZType.bodyS.copyWith(color: ZveltTokens.text3),
          filled: true,
          fillColor: ZveltTokens.bg,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(ZveltTokens.rMd),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ZveltTokens.border,
                    borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                  ),
                ),
              ),
              const SizedBox(height: ZveltTokens.s5),
              Text('Log measurements',
                  style: ZType.h3.copyWith(color: ZveltTokens.text)),
              const SizedBox(height: 4),
              Text('Stored on this device. Fill what you measured — the rest stays untouched.',
                  style: ZType.bodyS.copyWith(color: ZveltTokens.text3, fontSize: 12)),
              const SizedBox(height: 16),
              _field('Chest', 'cm', _chest),
              _field('Waist', 'cm', _waist),
              _field('Arms', 'cm', _arms),
              _field('Thighs', 'cm', _thighs),
              _field('Body fat (optional)', '%', _bodyFat),
              if (_error != null) ...[
                const SizedBox(height: 2),
                Text(_error!,
                    style: ZType.bodyS.copyWith(color: ZveltTokens.error)),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: ZveltTokens.brand,
                    foregroundColor: ZveltTokens.onBrand,
                    padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                    ),
                  ),
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  // Design spec: 1W / 1M / 3M / 1Y.
  static const _opts = ['1W', '1M', '3M', '1Y'];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ZveltTokens.bg2,
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _opts.map((p) {
          final active = value == p;
          return GestureDetector(
            onTap: () => onChanged(p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: active ? ZveltTokens.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                boxShadow: active ? ZveltTokens.shadowCard : null,
              ),
              child: Text(p,
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontMono,
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: active ? ZveltTokens.text : ZveltTokens.text3,
                  )),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  BIOLOGY TAB
// ════════════════════════════════════════════════════════════════════

class _WeeklyCoachReadCard extends StatelessWidget {
  const _WeeklyCoachReadCard({required this.read, required this.loading});

  final String? read;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (!loading && (read == null || read!.isEmpty)) {
      return const SizedBox.shrink();
    }

    return ZCard(
      padding: const EdgeInsets.all(ZveltTokens.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(ZveltTokens.s2),
                decoration: BoxDecoration(
                  color: ZveltTokens.brandTint,
                  borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                ),
                child: const Icon(
                  AppIcons.chart_line_up,
                  color: ZveltTokens.brand,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(child: ZEyebrow("Coach's read — this week")),
            ],
          ),
          const SizedBox(height: ZveltTokens.s4),
          if (loading)
            const _CoachReadShimmer()
          else
            _CoachReadBody(text: read!),
        ],
      ),
    );
  }
}

/// Renders the coach read text. Treats `**Label:**` as bold leading span on
/// each line; the rest of the line renders as body text. Designed for the
/// 4-bullet structure the backend prompt enforces.
class _CoachReadBody extends StatelessWidget {
  const _CoachReadBody({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _CoachReadLine(raw: lines[i]),
        ],
      ],
    );
  }
}

class _CoachReadLine extends StatelessWidget {
  const _CoachReadLine({required this.raw});
  final String raw;

  @override
  Widget build(BuildContext context) {
    final match = RegExp(r'^\*\*([^*]+)\*\*\s*').firstMatch(raw);
    if (match == null) {
      return Text(raw, style: ZType.bodyM.copyWith(color: ZveltTokens.text, height: 1.5));
    }
    final label = match.group(1)!.trim();
    final body = raw.substring(match.end).trim();
    return RichText(
      text: TextSpan(
        style: ZType.bodyM.copyWith(color: ZveltTokens.text, height: 1.5),
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(
              fontFamily: ZveltTokens.fontPrimary,
              color: ZveltTokens.text,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
          TextSpan(text: body),
        ],
      ),
    );
  }
}

class _CoachReadShimmer extends StatefulWidget {
  const _CoachReadShimmer();

  @override
  State<_CoachReadShimmer> createState() => _CoachReadShimmerState();
}

class _CoachReadShimmerState extends State<_CoachReadShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final opacity = 0.18 + (_ctrl.value * 0.18);
        Widget line(double widthFrac) => Container(
              height: 12,
              width: MediaQuery.sizeOf(context).width * widthFrac,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: ZveltTokens.text.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(4),
              ),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [line(0.78), line(0.62), line(0.85), line(0.55)],
        );
      },
    );
  }
}

