import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../config/api_config.dart' show mediaAbsoluteUrl;
import '../../services/program_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/z/z_card.dart';
import '../../widgets/zvelt_network_image.dart';
import 'active_program_screen.dart';
import 'program_builder_screen.dart';
import 'program_detail_screen.dart';
import 'quick_launch_sheet.dart';

String programLevelLabel(String level) {
  switch (level) {
    case 'beginner':
      return 'Beginner';
    case 'advanced':
      return 'Advanced';
    default:
      return 'Intermediate';
  }
}

/// Human label for a progression scheme (used by the program detail screen).
String programSchemeLabel(String scheme) {
  switch (scheme) {
    case 'linear':
      return 'Linear progression';
    case 'double':
      return 'Double progression';
    case 'percentage':
      return '% of 1RM';
    case 'reps_sum':
      return 'Volume';
    default:
      return 'Auto-regulated';
  }
}

/// The Programs library — browse multi-week templates (Liftosaur-style cards)
/// with search, a natural-language filter, and sort, then start one.
class ProgramsLibraryScreen extends StatefulWidget {
  const ProgramsLibraryScreen({super.key});

  @override
  State<ProgramsLibraryScreen> createState() => _ProgramsLibraryScreenState();
}

enum _Sort { none, name, daysAsc, daysDesc }

class _ProgramsLibraryScreenState extends State<ProgramsLibraryScreen> {
  final _service = ProgramService();
  bool _loading = true;
  String? _error;
  List<ProgramSummary> _templates = const [];
  ActiveProgram? _active;

  // Filters
  String _query = '';
  String? _level; // null = any
  int? _days; // null = any
  String? _goal; // null = any
  _Sort _sort = _Sort.none;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.getTemplates(),
        _service.getActive(),
      ]);
      if (!mounted) return;
      setState(() {
        _templates = results[0] as List<ProgramSummary>;
        _active = (results[1] as ActiveProgramView).program;
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

  List<ProgramSummary> get _filtered {
    var list = _templates.where((t) {
      if (_query.isNotEmpty &&
          !t.title.toLowerCase().contains(_query.toLowerCase())) {
        return false;
      }
      if (_level != null && t.level != _level) return false;
      if (_days != null && t.daysPerWeek != _days) return false;
      if (_goal != null && !t.goalTags.contains(_goal)) return false;
      return true;
    }).toList();
    switch (_sort) {
      case _Sort.name:
        list.sort((a, b) => a.title.compareTo(b.title));
      case _Sort.daysAsc:
        list.sort((a, b) => a.daysPerWeek.compareTo(b.daysPerWeek));
      case _Sort.daysDesc:
        list.sort((a, b) => b.daysPerWeek.compareTo(a.daysPerWeek));
      case _Sort.none:
        break;
    }
    return list;
  }

  Future<void> _openActive() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const ActiveProgramScreen()),
    );
    if (mounted) _load();
  }

  Future<void> _openTemplate(ProgramSummary t) async {
    final started = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => ProgramDetailScreen(templateId: t.id)),
    );
    if (!mounted) return;
    if (started == true) {
      _openActive();
    } else {
      _load();
    }
  }

  Future<void> _createNew() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const ProgramBuilderScreen()),
    );
    if (mounted) _load();
  }

  Future<void> _goWithout() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const QuickLaunchSheet()),
    );
  }

  // ── filter pickers ──────────────────────────────────────────────────────────
  Future<void> _pickLevel() async {
    final v = await _pickOne('Experience', _level, const [
      (null, 'Any experience'),
      ('beginner', 'Beginner'),
      ('intermediate', 'Intermediate'),
      ('advanced', 'Advanced'),
    ]);
    if (mounted && v.picked) setState(() => _level = v.value);
  }

  Future<void> _pickDays() async {
    final v = await _pickOne<int?>('Days per week', _days, const [
      (null, 'Any number of days'),
      (2, '2 days'),
      (3, '3 days'),
      (4, '4 days'),
      (5, '5 days'),
      (6, '6 days'),
    ]);
    if (mounted && v.picked) setState(() => _days = v.value);
  }

  Future<void> _pickGoal() async {
    final v = await _pickOne('Goal', _goal, const [
      (null, 'Any goal'),
      ('strength', 'Strength'),
      ('hypertrophy', 'Hypertrophy'),
    ]);
    if (mounted && v.picked) setState(() => _goal = v.value);
  }

  Future<void> _pickSort() async {
    final v = await _pickOne<_Sort>('Sort by', _sort, const [
      (_Sort.none, 'None'),
      (_Sort.name, 'Name'),
      (_Sort.daysAsc, 'Days / week ↑'),
      (_Sort.daysDesc, 'Days / week ↓'),
    ]);
    if (mounted && v.picked) setState(() => _sort = v.value);
  }

  Future<({bool picked, T value})> _pickOne<T>(
      String title, T current, List<(T, String)> options) async {
    T? result;
    var picked = false;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: ZveltTokens.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
        ),
        padding: const EdgeInsets.fromLTRB(
            ZveltTokens.s5, ZveltTokens.s4, ZveltTokens.s5, ZveltTokens.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ZveltTokens.borderStrong,
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                ),
              ),
            ),
            const SizedBox(height: ZveltTokens.s4),
            Text(title, style: ZType.h4.copyWith(color: ZveltTokens.text)),
            const SizedBox(height: ZveltTokens.s2),
            for (final (value, label) in options)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(label, style: ZType.bodyM.copyWith(color: ZveltTokens.text)),
                trailing: value == current
                    ? const Icon(AppIcons.check, color: ZveltTokens.brand, size: 20)
                    : null,
                onTap: () {
                  result = value;
                  picked = true;
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      ),
    );
    return (picked: picked, value: picked ? result as T : current);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        backgroundColor: ZveltTokens.bg,
        elevation: 0,
        title: Text('Choose a program', style: ZType.h3.copyWith(color: ZveltTokens.text)),
        actions: [
          TextButton(
            onPressed: _createNew,
            child: Text('New', style: ZType.bodyM.copyWith(color: ZveltTokens.brand, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
      bottomNavigationBar: _bottomBar(),
    );
  }

  Widget _body() {
    if (_loading && _templates.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: ZveltTokens.brand));
    }
    if (_error != null && _templates.isEmpty) {
      return _ErrorView(message: _error!, onRetry: _load);
    }
    final list = _filtered;
    return RefreshIndicator(
      color: ZveltTokens.brand,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            ZveltTokens.screenPaddingH, ZveltTokens.s3, ZveltTokens.screenPaddingH, ZveltTokens.s8),
        children: [
          if (_active != null) ...[
            _ActiveBanner(program: _active!, onTap: _openActive),
            const SizedBox(height: ZveltTokens.s4),
          ],
          _searchField(),
          const SizedBox(height: ZveltTokens.s4),
          _FilterSentence(
            level: _level,
            days: _days,
            goal: _goal,
            onLevel: _pickLevel,
            onDays: _pickDays,
            onGoal: _pickGoal,
          ),
          const SizedBox(height: ZveltTokens.s3),
          _sortRow(list.length),
          const SizedBox(height: ZveltTokens.s3),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s8),
              child: Center(
                child: Text('No programs match these filters.',
                    style: ZType.bodyM.copyWith(color: ZveltTokens.text3)),
              ),
            )
          else
            for (final t in list) ...[
              RepaintBoundary(child: _ProgramCard(summary: t, onTap: () => _openTemplate(t))),
              const SizedBox(height: ZveltTokens.cardGap),
            ],
        ],
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      onChanged: (v) => setState(() => _query = v),
      style: ZType.bodyM.copyWith(color: ZveltTokens.text),
      decoration: InputDecoration(
        hintText: 'Search by name',
        hintStyle: ZType.bodyM.copyWith(color: ZveltTokens.text4),
        prefixIcon: Icon(AppIcons.search, color: ZveltTokens.text3, size: 18),
        filled: true,
        fillColor: ZveltTokens.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: ZveltTokens.s3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZveltTokens.rMd),
          borderSide: BorderSide(color: ZveltTokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZveltTokens.rMd),
          borderSide: BorderSide(color: ZveltTokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZveltTokens.rMd),
          borderSide: const BorderSide(color: ZveltTokens.brand, width: 1.5),
        ),
      ),
    );
  }

  Widget _sortRow(int count) {
    final label = switch (_sort) {
      _Sort.name => 'Name',
      _Sort.daysAsc => 'Days ↑',
      _Sort.daysDesc => 'Days ↓',
      _Sort.none => 'None',
    };
    return Row(
      children: [
        Text('$count program${count == 1 ? '' : 's'}',
            style: ZType.bodyS.copyWith(color: ZveltTokens.text3)),
        const Spacer(),
        GestureDetector(
          onTap: _pickSort,
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              Text('Sort: ', style: ZType.bodyS.copyWith(color: ZveltTokens.text3)),
              Text(label, style: ZType.bodyS.copyWith(color: ZveltTokens.brand, fontWeight: FontWeight.w600)),
              const Icon(AppIcons.angle_small_down, color: ZveltTokens.brand, size: 16),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: ZveltTokens.surface,
          border: Border(top: BorderSide(color: ZveltTokens.border)),
        ),
        padding: const EdgeInsets.fromLTRB(
            ZveltTokens.s4, ZveltTokens.s3, ZveltTokens.s4, ZveltTokens.s3),
        child: Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: _createNew,
                child: Text('Create New Program',
                    style: ZType.bodyM.copyWith(color: ZveltTokens.brand, fontWeight: FontWeight.w700)),
              ),
            ),
            Container(width: 1, height: 28, color: ZveltTokens.border),
            Expanded(
              child: TextButton(
                onPressed: _goWithout,
                child: Text('Go Without Program',
                    textAlign: TextAlign.center,
                    style: ZType.bodyM.copyWith(color: ZveltTokens.text2)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The natural-language filter line with tappable, underlined parameters.
class _FilterSentence extends StatelessWidget {
  const _FilterSentence({
    required this.level,
    required this.days,
    required this.goal,
    required this.onLevel,
    required this.onDays,
    required this.onGoal,
  });

  final String? level;
  final int? days;
  final String? goal;
  final VoidCallback onLevel, onDays, onGoal;

  @override
  Widget build(BuildContext context) {
    final base = ZType.bodyM.copyWith(color: ZveltTokens.text2, height: 1.5);
    TextSpan link(String text, VoidCallback onTap) => TextSpan(
          text: text,
          style: base.copyWith(
            color: ZveltTokens.brand,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: ZveltTokens.brand,
          ),
          recognizer: TapGestureRecognizer()..onTap = onTap,
        );

    final lvl = level == null ? 'any experience' : programLevelLabel(level!).toLowerCase();
    final dys = days == null ? 'any number of days' : '$days days';
    final gl = goal == null ? 'any goal' : goal!;

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: 'I have '),
          link(lvl, onLevel),
          const TextSpan(text: '. I can train '),
          link(dys, onDays),
          const TextSpan(text: ' a week. My goal is '),
          link(gl, onGoal),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }
}

class _ActiveBanner extends StatelessWidget {
  const _ActiveBanner({required this.program, required this.onTap});
  final ActiveProgram program;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ZCard(
      onTap: onTap,
      color: ZveltTokens.surfaceTinted,
      shadow: ZveltTokens.shadowHero,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(color: ZveltTokens.brand, shape: BoxShape.circle),
            child: const Icon(AppIcons.gym, color: ZveltTokens.onBrand, size: 22),
          ),
          const SizedBox(width: ZveltTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Continue program',
                    style: ZType.eyebrow.copyWith(color: ZveltTokens.brandDeep)),
                const SizedBox(height: 2),
                Text(program.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZType.h4.copyWith(color: ZveltTokens.text)),
                Text('Week ${program.currentWeek} of ${program.totalWeeks}',
                    style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
              ],
            ),
          ),
          Icon(AppIcons.angle_small_right, color: ZveltTokens.text3, size: 22),
        ],
      ),
    );
  }
}

class _ProgramCard extends StatelessWidget {
  const _ProgramCard({required this.summary, required this.onTap});
  final ProgramSummary summary;
  final VoidCallback onTap;

  static const _maxThumbs = 10;

  @override
  Widget build(BuildContext context) {
    final thumbs = summary.thumbnails.take(_maxThumbs).toList();
    final weeks = summary.defaultWeeks;
    final freq = '${weeks > 1 ? '$weeks weeks, ' : ''}${summary.daysPerWeek}×/week, ${summary.exercisesPerDay} exercises/day';
    return ZCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(summary.title,
                    style: ZType.h4.copyWith(color: ZveltTokens.text)),
              ),
              if (summary.sessionTime.isNotEmpty) ...[
                const SizedBox(width: ZveltTokens.s2),
                Icon(AppIcons.stopwatch, color: ZveltTokens.text3, size: 14),
                const SizedBox(width: 3),
                Text(summary.sessionTime,
                    style: ZType.bodyS.copyWith(color: ZveltTokens.text3)),
              ],
            ],
          ),
          const SizedBox(height: ZveltTokens.s2),
          Text(summary.description,
              style: ZType.bodyS.copyWith(color: ZveltTokens.text2, height: 1.4)),
          if (thumbs.isNotEmpty) ...[
            const SizedBox(height: ZveltTokens.s3),
            Wrap(
              spacing: ZveltTokens.s2,
              runSpacing: ZveltTokens.s2,
              children: [
                for (final url in thumbs)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                    child: Container(
                      width: 40,
                      height: 40,
                      color: ZveltTokens.bg2,
                      child: ZveltNetworkImage(
                        url: mediaAbsoluteUrl(url),
                        fit: BoxFit.cover,
                        width: 40,
                        height: 40,
                        cacheWidth: ZveltImageCacheWidth.storyThumb,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: ZveltTokens.s3),
          Row(
            children: [
              Icon(AppIcons.calendar, color: ZveltTokens.text3, size: 13),
              const SizedBox(width: ZveltTokens.s1),
              Expanded(
                child: Text(freq,
                    style: ZType.bodyS.copyWith(color: ZveltTokens.text3, fontSize: 12)),
              ),
            ],
          ),
          if (summary.equipment.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(AppIcons.gym, color: ZveltTokens.text3, size: 13),
                const SizedBox(width: ZveltTokens.s1),
                Expanded(
                  child: Text(summary.equipment.join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZType.bodyS.copyWith(color: ZveltTokens.text3, fontSize: 12)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZveltTokens.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.cloud_disabled, color: ZveltTokens.text3, size: 40),
            const SizedBox(height: ZveltTokens.s4),
            Text(message,
                textAlign: TextAlign.center,
                style: ZType.bodyM.copyWith(color: ZveltTokens.text2)),
            const SizedBox(height: ZveltTokens.s4),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: ZveltTokens.brand,
                foregroundColor: ZveltTokens.onBrand,
              ),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
