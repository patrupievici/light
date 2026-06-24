import 'dart:async';
import 'package:zvelt_app/theme/app_icons.dart';

import 'package:flutter/material.dart';
import '../../theme/zvelt_tokens.dart';
import '../../services/workout_service.dart';
import '../../widgets/zvelt_network_image.dart';
import 'exercise_detail_screen.dart';

/// Browse catalog exercises. Two-level: pick a muscle-group category, then the
/// exercises within it. A search query cuts across all categories (flat).
class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({
    super.key,
    this.selectionMode = false,
  });

  final bool selectionMode;

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  final WorkoutService _service = WorkoutService();
  final TextEditingController _query = TextEditingController();
  List<ExerciseDto> _items = [];
  bool _loading = true;
  String? _error;

  /// Currently drilled-into category, or null while showing the category list.
  String? _category;

  /// Debounced, normalized (trimmed + lowercased) search query that drives
  /// filtering. Updated [_debounceMs] after the last keystroke so the full
  /// list isn't re-filtered on every character.
  String _debouncedQuery = '';
  Timer? _debounce;
  static const int _debounceMs = 250;

  // Tracks whether the clear (X) suffix icon is currently shown, so we can
  // toggle it on the empty/non-empty edge without waiting for the debounce.
  bool _showClear = false;

  /// Memoized filtered list, keyed by the query+category that produced it, so
  /// [_buildExerciseList] doesn't re-scan [_items] on every rebuild.
  List<ExerciseDto>? _filteredCache;
  String? _filteredCacheKey;

  // Ordered muscle-group categories. Each exercise is bucketed by its
  // primaryMuscle (see [_groupOf]); empty groups are hidden.
  static const List<String> _groupOrder = [
    'Chest', 'Back', 'Shoulders', 'Arms', 'Legs', 'Core', 'Full Body', 'Other',
  ];

  static const Map<String, IconData> _groupIcons = {
    'Chest': AppIcons.gym,
    'Back': AppIcons.running,
    'Shoulders': AppIcons.user,
    'Arms': AppIcons.boxing_glove,
    'Legs': AppIcons.running,
    'Core': AppIcons.target,
    'Full Body': AppIcons.bolt,
    'Other': AppIcons.apps,
  };

  @override
  void initState() {
    super.initState();
    _query.addListener(_onQueryChanged);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.removeListener(_onQueryChanged);
    _query.dispose();
    super.dispose();
  }

  /// Fires on every keystroke. Toggles the clear icon immediately (cheap, only
  /// when the empty/non-empty edge flips) but debounces the actual query that
  /// drives filtering/rebuild by [_debounceMs] to avoid re-scanning [_items]
  /// per character.
  void _onQueryChanged() {
    final hasText = _query.text.isNotEmpty;
    if (hasText != _showClear) {
      setState(() => _showClear = hasText);
    }
    final next = _query.text.trim().toLowerCase();
    if (next == _debouncedQuery) {
      // No effective change (e.g. only whitespace/case differences); cancel any
      // pending rebuild so we don't redundantly setState.
      _debounce?.cancel();
      return;
    }
    _debounce?.cancel();
    if (next.isEmpty) {
      // Clearing the field should snap back to the category list immediately,
      // matching the pre-debounce behavior — no point waiting to show "more".
      setState(() => _debouncedQuery = '');
      return;
    }
    _debounce = Timer(const Duration(milliseconds: _debounceMs), () {
      if (!mounted) return;
      final q = _query.text.trim().toLowerCase();
      if (q == _debouncedQuery) return;
      setState(() => _debouncedQuery = q);
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _service.getExercises(limit: 300);
      if (!mounted) return;
      setState(() {
        _items = res.data;
        // The underlying data changed; drop any memoized filter result.
        _filteredCache = null;
        _filteredCacheKey = null;
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

  /// Bucket an exercise into one of [_groupOrder] by its primary muscle.
  String _groupOf(ExerciseDto e) {
    final m = (e.primaryMuscle ?? '').toLowerCase();
    if (m.contains('chest') || m.contains('pec')) return 'Chest';
    if (m.contains('back') || m.contains('lat') || m.contains('trap')) return 'Back';
    if (m.contains('shoulder') || m.contains('delt')) return 'Shoulders';
    if (m.contains('bicep') || m.contains('tricep') || m.contains('forearm') || m == 'arms') return 'Arms';
    if (m.contains('quad') ||
        m.contains('hamstring') ||
        m.contains('glute') ||
        m.contains('calf') ||
        m.contains('calves') ||
        m.contains('adduct') ||
        m.contains('abduct') ||
        m.contains('leg')) {
      return 'Legs';
    }
    if (m.contains('core') || m == 'abs' || m.contains('abdom') || m.contains('oblique')) return 'Core';
    if (m.contains('full')) return 'Full Body';
    return 'Other';
  }

  @override
  Widget build(BuildContext context) {
    final q = _debouncedQuery;
    final searching = q.isNotEmpty;
    final showCategories = !searching && _category == null;

    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        // While drilled into a category, the back button returns to the
        // category list instead of leaving the screen.
        leading: _category != null && !searching
            ? IconButton(
                icon: const Icon(AppIcons.arrow_small_left),
                onPressed: () => setState(() => _category = null),
              )
            : null,
        title: Text(
          _category != null && !searching
              ? _category!
              : widget.selectionMode
                  ? 'Select exercise'
                  : 'Exercise library',
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                ZveltTokens.screenPaddingH, 0, ZveltTokens.screenPaddingH, ZveltTokens.s2),
            child: Column(
              children: [
                TextField(
                  controller: _query,
                  style: ZType.bodyM,
                  decoration: InputDecoration(
                    hintText: 'Search all exercises',
                    prefixIcon: Icon(AppIcons.search, color: ZveltTokens.text2),
                    suffixIcon: _showClear
                        ? IconButton(
                            icon: Icon(AppIcons.cross_small, color: ZveltTokens.text2),
                            onPressed: () => _query.clear(),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: ZveltTokens.brand))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(ZveltTokens.s6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, style: ZType.bodyM.copyWith(color: ZveltTokens.error), textAlign: TextAlign.center),
                              const SizedBox(height: ZveltTokens.s3),
                              FilledButton(onPressed: _load, child: const Text('Retry')),
                            ],
                          ),
                        ),
                      )
                    : showCategories
                        ? _buildCategoryList()
                        : _buildExerciseList(q, searching),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryList() {
    final counts = <String, int>{};
    for (final e in _items) {
      final g = _groupOf(e);
      counts[g] = (counts[g] ?? 0) + 1;
    }
    final cats = _groupOrder.where((g) => (counts[g] ?? 0) > 0).toList();
    if (cats.isEmpty) {
      return Center(child: Text('No exercises found', style: TextStyle(color: ZveltTokens.text2)));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          ZveltTokens.screenPaddingH, 0, ZveltTokens.screenPaddingH, ZveltTokens.s6),
      itemCount: cats.length,
      separatorBuilder: (_, __) => const SizedBox(height: ZveltTokens.s2),
      itemBuilder: (context, i) {
        final cat = cats[i];
        return InkWell(
          borderRadius: BorderRadius.circular(ZveltTokens.rLg),
          onTap: () => setState(() => _category = cat),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s4),
            decoration: BoxDecoration(
              color: ZveltTokens.surface,
              borderRadius: BorderRadius.circular(ZveltTokens.rLg),
              boxShadow: ZveltTokens.shadowCard,
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: ZveltTokens.brandTint,
                    borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                  ),
                  child: Icon(_groupIcons[cat] ?? AppIcons.apps, color: ZveltTokens.brand, size: 22),
                ),
                const SizedBox(width: ZveltTokens.s4),
                Expanded(
                  child: Text(
                    cat,
                    style: ZType.h4.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${counts[cat]}',
                  style: ZType.bodyS.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: ZveltTokens.s2),
                Icon(AppIcons.angle_small_right, color: ZveltTokens.text3),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Returns the filtered exercise list for the current query/category,
  /// memoized so the full [_items] list is scanned at most once per distinct
  /// (search, query, category) combination rather than on every rebuild.
  /// The cache is invalidated whenever [_items] is reloaded (see [_load]).
  List<ExerciseDto> _filteredFor(String q, bool searching) {
    final key = searching ? 's:$q' : 'c:${_category ?? ''}';
    final cached = _filteredCache;
    if (cached != null && _filteredCacheKey == key) {
      return cached;
    }
    final List<ExerciseDto> list = searching
        ? _items.where((e) => e.name.toLowerCase().contains(q)).toList()
        : _items.where((e) => _groupOf(e) == _category).toList();
    _filteredCache = list;
    _filteredCacheKey = key;
    return list;
  }

  Widget _buildExerciseList(String q, bool searching) {
    final List<ExerciseDto> list = _filteredFor(q, searching);

    if (list.isEmpty) {
      return Center(child: Text('No exercises found', style: TextStyle(color: ZveltTokens.text2)));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          ZveltTokens.screenPaddingH, 0, ZveltTokens.screenPaddingH, ZveltTokens.s6),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: ZveltTokens.s2),
      itemBuilder: (context, i) {
        final ex = list[i];
        return InkWell(
          borderRadius: BorderRadius.circular(ZveltTokens.rLg),
          onTap: () {
            if (widget.selectionMode) {
              Navigator.of(context).pop(ex);
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ExerciseDetailScreen(exercise: ex),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
            decoration: BoxDecoration(
              color: ZveltTokens.surface,
              borderRadius: BorderRadius.circular(ZveltTokens.rLg),
              boxShadow: ZveltTokens.shadowCard,
            ),
            child: Row(
              children: [
                _ExerciseThumb(exercise: ex),
                const SizedBox(width: ZveltTokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ex.name,
                        style: ZType.bodyM.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (ex.primaryMuscle != null)
                        Text(
                          [
                            ex.primaryMuscle!,
                            if (ex.equipment != null && ex.equipment!.isNotEmpty) ex.equipment!,
                          ].join(' • '),
                          style: ZType.monoS,
                        ),
                      if (ex.secondaryMuscles.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: ZveltTokens.s1 + 2),
                          child: Wrap(
                            spacing: ZveltTokens.s1 + 2,
                            runSpacing: ZveltTokens.s1 + 2,
                            children: ex.secondaryMuscles.take(3).map((muscle) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s2, vertical: ZveltTokens.s1),
                                decoration: BoxDecoration(
                                  color: ZveltTokens.surface2,
                                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                                  border: Border.all(color: ZveltTokens.border),
                                ),
                                child: Text(
                                  muscle,
                                  style: ZType.monoXS,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
                if (ex.media.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: ZveltTokens.s2),
                    child: Icon(AppIcons.play, color: ZveltTokens.text2),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ExerciseThumb extends StatelessWidget {
  const _ExerciseThumb({required this.exercise});

  final ExerciseDto exercise;

  @override
  Widget build(BuildContext context) {
    final media = exercise.media.isNotEmpty ? exercise.media.first : null;
    final preview = media?.previewUrl;
    if (preview != null && preview.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(ZveltTokens.rSm),
        child: Container(
          width: 48,
          height: 48,
          color: ZveltTokens.surface2,
          child: ZveltNetworkImage(
            url: preview,
            fit: BoxFit.cover,
            cacheWidth: 144, // 48dp @ 3x
            errorWidget: (_) => _fallback(),
          ),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: ZveltTokens.brandGlow,
        borderRadius: BorderRadius.circular(ZveltTokens.rSm),
        border: Border.all(
          color: ZveltTokens.brand.withValues(alpha: 0.35),
        ),
      ),
      child: const Icon(AppIcons.gym, color: ZveltTokens.brand, size: 20),
    );
  }
}
