import 'dart:ui' as ui;
import 'package:zvelt_app/theme/app_icons.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/journal_store.dart';
import '../../theme/zvelt_tokens.dart';
import '../../utils/formatters.dart';
import 'journal_entry_screen.dart';

/// JOURNAL tab — local-first daily wellness log.
///
/// v1.0 ships pure-offline (sqflite). Backend sync is deferred (see
/// [JournalStore] TODO).
class JournalTab extends StatefulWidget {
  const JournalTab({super.key});

  @override
  State<JournalTab> createState() => _JournalTabState();
}

class _JournalTabState extends State<JournalTab> {
  static const int _kRecentLimit = 30;

  bool _loading = true;
  List<JournalEntry> _recent = const [];
  Map<DateTime, JournalEntry> _chartRange = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = today.subtract(const Duration(days: 29));
    final results = await Future.wait([
      JournalStore.instance.getEntries(limit: _kRecentLimit),
      JournalStore.instance.rangeMap(from, today),
    ]);
    if (!mounted) return;
    setState(() {
      _recent = results[0] as List<JournalEntry>;
      _chartRange = results[1] as Map<DateTime, JournalEntry>;
      _loading = false;
    });
  }

  Future<void> _openComposer({JournalEntry? existing, DateTime? date}) async {
    final now = DateTime.now();
    final target = date ?? existing?.entryDate ?? DateTime(now.year, now.month, now.day);
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JournalEntryScreen(date: target, existing: existing),
      ),
    );
    if (!mounted) return;
    if (result is JournalEntry || JournalEntryScreen.isDeleted(result)) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: ZveltTokens.brand,
          backgroundColor: ZveltTokens.surface,
          child: _loading
              ? ListView(
                  // ListView keeps RefreshIndicator drag-to-refresh working
                  // even during the initial load.
                  children: const [
                    SizedBox(height: 240),
                    Center(child: CircularProgressIndicator(color: ZveltTokens.brand)),
                  ],
                )
              : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final today = _todayEntry();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s2, ZveltTokens.s4, ZveltTokens.s8),
      children: [
        _header(today),
        const SizedBox(height: ZveltTokens.s4),
        if (_recent.isEmpty)
          _emptyState()
        else ...[
          _chartCard(),
          const SizedBox(height: ZveltTokens.s4),
          _recentHeader(),
          const SizedBox(height: ZveltTokens.s2),
          ..._recent.map(_entryCard),
        ],
      ],
    );
  }

  JournalEntry? _todayEntry() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _chartRange[today];
  }

  Widget _header(JournalEntry? today) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'JOURNAL',
                style: ZType.h1.copyWith(color: ZveltTokens.text),
              ),
              const SizedBox(height: 2),
              Text(
                today == null
                    ? 'No entry for today yet'
                    : 'Logged today · ${_moodEmoji(today.mood)} ${_moodLabel(today.mood)}',
                style: TextStyle(color: ZveltTokens.text2, fontSize: 12),
              ),
            ],
          ),
        ),
        _addButton(today),
      ],
    );
  }

  Widget _addButton(JournalEntry? today) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        onTap: () => _openComposer(existing: today),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: ZveltTokens.brand,
            borderRadius: BorderRadius.circular(ZveltTokens.rPill),
            boxShadow: [
              BoxShadow(
                color: ZveltTokens.brand.withValues(alpha: 0.35),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(
            today == null ? AppIcons.plus : AppIcons.edit,
            color: Colors.white,
            size: 26,
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, ZveltTokens.s6, ZveltTokens.s5, ZveltTokens.s6),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: ZveltTokens.brandGlow,
              borderRadius: BorderRadius.circular(ZveltTokens.rMd),
              border: Border.all(color: ZveltTokens.brand.withValues(alpha: 0.4)),
            ),
            child: const Icon(
              AppIcons.book,
              color: ZveltTokens.brand,
              size: 26,
            ),
          ),
          const SizedBox(height: ZveltTokens.s4),
          Text(
            'START JOURNALING',
            style: ZType.h2.copyWith(color: ZveltTokens.text),
          ),
          const SizedBox(height: ZveltTokens.s1),
          Text(
            'Track how you feel as your training evolves. '
            'A 10-second log of mood, energy and soreness gives you '
            'patterns no plate can show.',
            style: TextStyle(color: ZveltTokens.text2, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: ZveltTokens.s4),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _openComposer(),
              icon: const Icon(AppIcons.plus, size: 18),
              label: const Text("WRITE TODAY'S ENTRY"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartCard() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = today.subtract(const Duration(days: 29));
    final days = List.generate(30, (i) => from.add(Duration(days: i)));
    return Container(
      padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s4, ZveltTokens.s4, ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '30-DAY TREND',
                style: ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 13),
              ),
              const Spacer(),
              _legendDot('Mood', ZveltTokens.brand3),
              const SizedBox(width: ZveltTokens.s3),
              _legendDot('Energy', ZveltTokens.info),
            ],
          ),
          const SizedBox(height: ZveltTokens.s3),
          SizedBox(
            height: 140,
            child: CustomPaint(
              size: Size.infinite,
              painter: _JournalTrendPainter(
                days: days,
                entries: _chartRange,
                moodColor: ZveltTokens.brand3,
                energyColor: ZveltTokens.info,
                gridColor: ZveltTokens.border,
                axisColor: ZveltTokens.text4,
              ),
            ),
          ),
          const SizedBox(height: ZveltTokens.s1),
          Row(
            children: [
              Text(
                DateFormat('MMM d').format(from),
                style: TextStyle(color: ZveltTokens.text3, fontSize: 11),
              ),
              const Spacer(),
              Text(
                DateFormat('MMM d').format(today),
                style: TextStyle(color: ZveltTokens.text3, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: ZveltTokens.s1),
        Text(
          label,
          style: TextStyle(color: ZveltTokens.text2, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _recentHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, ZveltTokens.s2, 2, 0),
      child: Row(
        children: [
          Text(
            'RECENT ENTRIES',
            style: ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 13),
          ),
          const Spacer(),
          Text(
            '${_recent.length}',
            style: TextStyle(
              color: ZveltTokens.text2,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _entryCard(JournalEntry e) {
    final now = DateTime.now();
    final isToday = e.entryDate.year == now.year &&
        e.entryDate.month == now.month &&
        e.entryDate.day == now.day;
    final dateLabel = isToday
        ? 'TODAY'
        : formatDate(e.entryDate, pattern: 'EEE, MMM d').toUpperCase();
    final notesPreview = e.notes.trim();
    final shownNotes = notesPreview.length > 80
        ? '${notesPreview.substring(0, 80)}…'
        : notesPreview;
    return Padding(
      padding: const EdgeInsets.only(bottom: ZveltTokens.s3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(ZveltTokens.rLg),
          onTap: () => _openComposer(existing: e),
          child: Container(
            padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s3, ZveltTokens.s4, ZveltTokens.s4),
            decoration: BoxDecoration(
              color: ZveltTokens.surface,
              borderRadius: BorderRadius.circular(ZveltTokens.rLg),
              border: Border.all(
                color: isToday ? ZveltTokens.brand.withValues(alpha: 0.4) : ZveltTokens.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      dateLabel,
                      style: TextStyle(
                        color: isToday ? ZveltTokens.brand : ZveltTokens.text3,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _moodEmoji(e.mood),
                      style: const TextStyle(fontSize: 18),
                    ),
                    const SizedBox(width: ZveltTokens.s3),
                    _energyBolts(e.energy),
                  ],
                ),
                if (e.soreness.isNotEmpty) ...[
                  const SizedBox(height: ZveltTokens.s3),
                  Wrap(
                    spacing: ZveltTokens.s2,
                    runSpacing: ZveltTokens.s2,
                    children: e.soreness.map((p) => _miniChip(_prettyPart(p))).toList(),
                  ),
                ],
                if (shownNotes.isNotEmpty) ...[
                  const SizedBox(height: ZveltTokens.s3),
                  Text(
                    shownNotes,
                    style: TextStyle(
                      color: ZveltTokens.text2,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _energyBolts(int energy) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = energy > i;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0.5),
          child: Icon(
            AppIcons.bolt,
            size: 14,
            color: filled ? ZveltTokens.brand : ZveltTokens.text4,
          ),
        );
      }),
    );
  }

  Widget _miniChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: ZveltTokens.s1),
      decoration: BoxDecoration(
        color: ZveltTokens.surface2,
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        border: Border.all(color: ZveltTokens.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: ZveltTokens.text2,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static const _kMoodEmojis = ['😞', '😕', '😐', '🙂', '😄'];
  static const _kMoodLabels = ['Awful', 'Low', 'Okay', 'Good', 'Great'];
  static String _moodEmoji(int m) => _kMoodEmojis[(m - 1).clamp(0, 4)];
  static String _moodLabel(int m) => _kMoodLabels[(m - 1).clamp(0, 4)];

  static String _prettyPart(String id) {
    switch (id) {
      case 'lower_back':
        return 'Lower back';
      default:
        return id[0].toUpperCase() + id.substring(1);
    }
  }
}

/// Two-series line chart for mood + energy across the last 30 days.
///
/// Y-axis: fixed 1..5 scale (matches the input range).
/// Missing days = gap; the line breaks at the absent slot and resumes
/// once an entry reappears. Dots are drawn only on real data points.
class _JournalTrendPainter extends CustomPainter {
  _JournalTrendPainter({
    required this.days,
    required this.entries,
    required this.moodColor,
    required this.energyColor,
    required this.gridColor,
    required this.axisColor,
  });

  final List<DateTime> days;
  final Map<DateTime, JournalEntry> entries;
  final Color moodColor;
  final Color energyColor;
  final Color gridColor;
  final Color axisColor;

  @override
  void paint(Canvas canvas, Size size) {
    const double leftPad = 22;
    const double rightPad = 6;
    const double topPad = 6;
    const double bottomPad = 16;

    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;
    if (chartW <= 0 || chartH <= 0) return;

    // Gridlines at y=1,2,3,4,5
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final labelStyle = TextStyle(color: axisColor, fontSize: 11);
    for (int v = 1; v <= 5; v++) {
      final t = (v - 1) / 4.0;
      final y = topPad + chartH - t * chartH;
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(leftPad + chartW, y),
        gridPaint,
      );
      final tp = TextPainter(
        text: TextSpan(text: '$v', style: labelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 4, y - tp.height / 2));
    }

    Offset pointFor(int i, int value) {
      final x = leftPad + (days.length == 1 ? 0 : i / (days.length - 1) * chartW);
      final t = (value - 1) / 4.0;
      final y = topPad + chartH - t * chartH;
      return Offset(x, y);
    }

    void drawSeries(Color color, int Function(JournalEntry) pick) {
      final linePaint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final dotPaint = Paint()..color = color;
      final dotBorder = Paint()
        ..color = ZveltTokens.bg
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      Offset? prev;
      final dots = <Offset>[];
      for (int i = 0; i < days.length; i++) {
        final d = days[i];
        final entry = entries[DateTime(d.year, d.month, d.day)];
        if (entry == null) {
          // Gap — break the line.
          prev = null;
          continue;
        }
        final pt = pointFor(i, pick(entry));
        if (prev != null) {
          canvas.drawLine(prev, pt, linePaint);
        }
        dots.add(pt);
        prev = pt;
      }
      for (final p in dots) {
        canvas.drawCircle(p, 3.0, dotPaint);
        canvas.drawCircle(p, 3.0, dotBorder);
      }
    }

    drawSeries(moodColor, (e) => e.mood);
    drawSeries(energyColor, (e) => e.energy);
  }

  @override
  bool shouldRepaint(covariant _JournalTrendPainter old) {
    return old.entries != entries ||
        old.days != days ||
        old.moodColor != moodColor ||
        old.energyColor != energyColor;
  }
}
