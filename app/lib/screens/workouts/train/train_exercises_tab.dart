import 'package:flutter/material.dart';

import '../../../theme/app_icons.dart';
import '../../../theme/zvelt_tokens.dart';

/// View model for a single row in [TrainExercisesTab].
class TrainExerciseVM {
  const TrainExerciseVM({
    required this.name,
    required this.equipment,
    required this.level,
    required this.lastLabel,
    required this.bestLabel,
    required this.trendLabel,
    required this.group,
    required this.bars,
  });

  /// Display name, e.g. "Bench Press".
  final String name;

  /// Equipment label, e.g. "Barbell".
  final String equipment;

  /// Difficulty label; may be '' — when empty the " · " separator is omitted.
  final String level;

  /// Most-recent set label, e.g. "70 kg × 8" or "BW × 6".
  final String lastLabel;

  /// Best set label.
  final String bestLabel;

  /// Trend label, e.g. "+8%", "0%", "-3%".
  final String trendLabel;

  /// Lowercase muscle group: chest|back|legs|shoulders|arms|other.
  final String group;

  /// 7 ints in 0..100 for the sparkline (renders what's given if not 7).
  final List<int> bars;
}

/// EXERCISES sub-tab of the Train screen — search + filter chips + an exercise
/// list with per-exercise trend + sparkline, then a "create custom" CTA.
///
/// Returns a [Column] (start-aligned, mainAxisSize.min) so the parent can drop
/// it into an existing scrolling ListView — it is NOT a Scaffold and owns no
/// scroll view of its own. Internal state: live search text + active muscle
/// filter. Tapping a card reports the exercise's index in the original
/// [exercises] list (not the filtered view) via [onOpenExercise].
///
/// When [exercises] is empty, an honest empty state is shown instead of the
/// search bar + chips + list.
class TrainExercisesTab extends StatefulWidget {
  const TrainExercisesTab({
    super.key,
    this.exercises = const <TrainExerciseVM>[],
    this.onOpenExercise,
    this.onCreateCustom,
    this.onBrowseLibrary,
  });

  /// The exercises to render.
  final List<TrainExerciseVM> exercises;

  /// Index into [exercises] (the original passed list) of the tapped card.
  final ValueChanged<int>? onOpenExercise;

  /// Tapped the bottom "Create custom exercise" row.
  final VoidCallback? onCreateCustom;

  /// Tapped "Browse exercise library" in the empty state.
  final VoidCallback? onBrowseLibrary;

  @override
  State<TrainExercisesTab> createState() => _TrainExercisesTabState();
}

class _TrainExercisesTabState extends State<TrainExercisesTab> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _filter = 'all';

  static const List<_FilterChip> _filters = [
    _FilterChip('All', 'all'),
    _FilterChip('Chest', 'chest'),
    _FilterChip('Back', 'back'),
    _FilterChip('Legs', 'legs'),
    _FilterChip('Shoulders', 'shoulders'),
    _FilterChip('Arms', 'arms'),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Honest empty state: no exercises at all → skip search/chips/list.
    if (widget.exercises.isEmpty) {
      return _emptyState();
    }

    // Keep original indices so onOpenExercise reports a stable index into the
    // full list even while filtered/searched.
    final query = _query.trim().toLowerCase();
    final visible = <int>[];
    for (var i = 0; i < widget.exercises.length; i++) {
      final ex = widget.exercises[i];
      final matchesFilter = _filter == 'all' || ex.group == _filter;
      final matchesQuery = query.isEmpty || ex.name.toLowerCase().contains(query);
      if (matchesFilter && matchesQuery) visible.add(i);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _searchBar(),
        const SizedBox(height: 16),
        _filterChips(),
        const SizedBox(height: 16),
        for (final i in visible)
          _ExerciseCard(
            exercise: widget.exercises[i],
            onTap: () => widget.onOpenExercise?.call(i),
          ),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s4),
            child: Text(
              'No exercises match your search.',
              style: ZType.bodyM.copyWith(color: ZveltTokens.text2),
            ),
          ),
        const SizedBox(height: 4),
        _createCustom(),
      ],
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────
  Widget _emptyState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.gym, size: 48, color: ZveltTokens.text3),
              const SizedBox(height: 16),
              Text(
                'No training history yet',
                textAlign: TextAlign.center,
                style: ZType.h4,
              ),
              const SizedBox(height: 8),
              Text(
                'Log a few workouts and your exercises show up here with trends.',
                textAlign: TextAlign.center,
                style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _browseLibraryButton(),
        const SizedBox(height: 12),
        _createCustom(),
      ],
    );
  }

  Widget _browseLibraryButton() {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: widget.onBrowseLibrary,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ZveltTokens.brand,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'Browse exercise library',
            style: ZType.bodyM.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: ZveltTokens.onBrand,
            ),
          ),
        ),
      ),
    );
  }

  // ── A. Search bar ─────────────────────────────────────────────────────────
  Widget _searchBar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Row(
        children: [
          Icon(AppIcons.search, size: 18, color: ZveltTokens.text3),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              cursorColor: ZveltTokens.brand,
              style: ZType.bodyM.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: ZveltTokens.text,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
                hintText: 'Search exercises…',
                hintStyle: ZType.bodyM.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: ZveltTokens.text3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── B. Filter chips ───────────────────────────────────────────────────────
  Widget _filterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (var i = 0; i < _filters.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _chip(_filters[i]),
          ],
        ],
      ),
    );
  }

  Widget _chip(_FilterChip chip) {
    final active = _filter == chip.value;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => setState(() => _filter = chip.value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            color: active ? ZveltTokens.brand : ZveltTokens.surface,
            borderRadius: BorderRadius.circular(999),
            boxShadow: active ? null : ZveltTokens.shadowCard,
          ),
          child: Text(
            chip.label,
            style: ZType.bodyS.copyWith(
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              color: active ? ZveltTokens.onBrand : ZveltTokens.text2,
            ),
          ),
        ),
      ),
    );
  }

  // ── D. Create custom exercise ─────────────────────────────────────────────
  Widget _createCustom() {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: widget.onCreateCustom,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ZveltTokens.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: ZveltTokens.shadowCard,
            border: Border.all(
              color: ZveltTokens.surface3,
              width: 2,
              style: BorderStyle.solid,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ZveltTokens.brandTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(AppIcons.plus, color: ZveltTokens.brand, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Create custom exercise',
                  style: ZType.bodyM.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: ZveltTokens.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── C. Exercise list card ───────────────────────────────────────────────────
class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.exercise, required this.onTap});

  final TrainExerciseVM exercise;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ZveltTokens.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: ZveltTokens.shadowCard,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left icon tile.
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ZveltTokens.brandTint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(AppIcons.gym, color: ZveltTokens.brand, size: 22),
                ),
                const SizedBox(width: 14),
                // Middle.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        exercise.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZType.h4.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: ZveltTokens.text,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        exercise.level.isEmpty
                            ? exercise.equipment
                            : '${exercise.equipment} · ${exercise.level}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZType.bodyS.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: ZveltTokens.text2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _statsRow(),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Right: trend + sparkline.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      exercise.trendLabel,
                      style: ZType.bodyS.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _trendUp ? ZveltTokens.success : ZveltTokens.warn,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _Sparkline(bars: exercise.bars),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Positive trend = starts with '+' and is not "+0".
  bool get _trendUp =>
      exercise.trendLabel.startsWith('+') && !exercise.trendLabel.startsWith('+0');

  Widget _statsRow() {
    final meta = ZType.bodyS.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: ZveltTokens.text2,
    );
    final value = meta.copyWith(fontWeight: FontWeight.w600, color: ZveltTokens.text2);
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: meta,
        children: [
          const TextSpan(text: 'Last: '),
          TextSpan(text: exercise.lastLabel, style: value),
          const TextSpan(text: '   Best: '),
          TextSpan(text: exercise.bestLabel, style: value),
        ],
      ),
    );
  }
}

/// 7-bar mini sparkline. Each bar 4px wide, ~3px gap, max height ~34px; the 3
/// most-recent (rightmost) bars use the brand accent, older 4 the lighter ac2.
class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.bars});

  final List<int> bars;

  static const double _maxHeight = 34;

  @override
  Widget build(BuildContext context) {
    final maxVal = bars.fold<int>(0, (m, v) => v > m ? v : m);
    final divisor = maxVal <= 0 ? 1 : maxVal;
    return SizedBox(
      height: _maxHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < bars.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Container(
              width: 4,
              height: (bars[i] / divisor * _maxHeight).clamp(2.0, _maxHeight),
              decoration: BoxDecoration(
                color: i >= bars.length - 3 ? ZveltTokens.brand : ZveltTokens.brand2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip {
  const _FilterChip(this.label, this.value);
  final String label;
  final String value;
}
