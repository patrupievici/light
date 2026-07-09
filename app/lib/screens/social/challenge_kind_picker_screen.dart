import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../../data/challenge_exercise_catalog.dart';
import '../../theme/zvelt_tokens.dart';

abstract class _PickerRow {
  const _PickerRow();
}

class _PickerHeader extends _PickerRow {
  const _PickerHeader(this.title);
  final String title;
}

class _PickerEntry extends _PickerRow {
  const _PickerEntry(this.entry);
  final ChallengeCatalogEntry entry;
}

/// Modal screen over a dimmed background: search + exercise list (gym / calisthenics).
/// Uses a [Hero] with the same [heroTag] as the sheet trigger for an “expand from button” transition.
class ChallengeKindPickerPage extends StatefulWidget {
  const ChallengeKindPickerPage({
    super.key,
    required this.heroTag,
    required this.selected,
  });

  final String heroTag;
  final ChallengeCatalogEntry selected;

  static Route<ChallengeCatalogEntry?> route({
    required String heroTag,
    required ChallengeCatalogEntry selected,
  }) {
    return PageRouteBuilder<ChallengeCatalogEntry?>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45), // scrim
      barrierLabel: 'Dismiss',
      transitionDuration: const Duration(milliseconds: 800),
      reverseTransitionDuration: const Duration(milliseconds: 800),
      pageBuilder: (context, animation, secondaryAnimation) {
        return ChallengeKindPickerPage(heroTag: heroTag, selected: selected);
      },
      // Don't fade the whole child: it would hide the Hero flight. The barrier stays route-animated.
      transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
    );
  }

  @override
  State<ChallengeKindPickerPage> createState() => _ChallengeKindPickerPageState();
}

class _ChallengeKindPickerPageState extends State<ChallengeKindPickerPage> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matchesEntry(ChallengeCatalogEntry e, String q) {
    if (q.isEmpty) return true;
    return e.displayName.toLowerCase().contains(q) || e.track.label.toLowerCase().contains(q);
  }

  bool _matchesManual(String q) {
    if (q.isEmpty) return true;
    final d = kChallengeCatalogManualEntry.displayName.toLowerCase();
    return d.contains(q) || q.contains('other') || q.contains('custom') || q.contains('title');
  }

  List<_PickerRow> get _rows {
    final q = _search.text.trim().toLowerCase();
    final gym = kChallengeExerciseCatalogCore
        .where((e) => e.track == ChallengeExerciseTrack.gym && _matchesEntry(e, q))
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final cal = kChallengeExerciseCatalogCore
        .where((e) => e.track == ChallengeExerciseTrack.calisthenicsFitness && _matchesEntry(e, q))
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    final rows = <_PickerRow>[];
    if (gym.isNotEmpty) {
      rows.add(const _PickerHeader('Gym'));
      for (final e in gym) {
        rows.add(_PickerEntry(e));
      }
    }
    if (cal.isNotEmpty) {
      rows.add(const _PickerHeader('Calisthenics & fitness'));
      for (final e in cal) {
        rows.add(_PickerEntry(e));
      }
    }
    if (_matchesManual(q)) {
      rows.add(const _PickerHeader('More'));
      rows.add(const _PickerEntry(kChallengeCatalogManualEntry));
    }
    return rows;
  }

  static ShapeBorder _cardShape() => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
        side: BorderSide(color: ZveltTokens.border),
      );

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final routeAnim = ModalRoute.of(context)?.animation;
    final openProgress = routeAnim != null
        ? CurvedAnimation(parent: routeAnim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)
        : const AlwaysStoppedAnimation<double>(1);

    final rows = _rows;

    Widget listBody;
    if (rows.isEmpty) {
      listBody = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No matches',
            style: ZType.bodyM.copyWith(color: ZveltTokens.text2.withValues(alpha: 0.9)),
          ),
        ),
      );
    } else {
      listBody = ListView.builder(
        padding: EdgeInsets.fromLTRB(0, 6, 0, 8 + bottomInset * 0.25),
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          final stagger = CurvedAnimation(
            parent: openProgress,
            curve: Interval(
              (index * 0.05).clamp(0.0, 0.45),
              (0.38 + index * 0.05).clamp(0.38, 1.0),
              curve: Curves.easeOutCubic,
            ),
          );

          if (row is _PickerHeader) {
            return FadeTransition(
              opacity: stagger,
              child: Padding(
                padding: EdgeInsets.fromLTRB(ZveltTokens.s4, index == 0 ? ZveltTokens.s1 : ZveltTokens.s4, ZveltTokens.s4, 6),
                child: Text(
                  row.title.toUpperCase(),
                  style: ZType.eyebrow.copyWith(
                    color: ZveltTokens.text2.withValues(alpha: 0.9),
                  ),
                ),
              ),
            );
          }

          final entry = (row as _PickerEntry).entry;
          final selected = entry.id == widget.selected.id;

          Widget tile = ListTile(
            title: Text(
              entry.displayName,
              style: ZType.bodyM.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: ZveltTokens.text,
              ),
            ),
            subtitle: entry.requiresManualTitle
                ? Text(
                    'Write your own challenge',
                    style: ZType.bodyS.copyWith(color: ZveltTokens.text2.withValues(alpha: 0.85)),
                  )
                : Text(
                    entry.track.label,
                    style: ZType.bodyS.copyWith(color: ZveltTokens.text2.withValues(alpha: 0.85)),
                  ),
            trailing: selected ? const Icon(AppIcons.badge_check, color: ZveltTokens.brand, size: 22) : null,
            onTap: () => Navigator.pop(context, entry),
          );

          if (index + 1 < rows.length && rows[index + 1] is _PickerEntry) {
            tile = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                tile,
                Divider(height: 1, thickness: 1, indent: 16, endIndent: 16, color: ZveltTokens.border.withValues(alpha: 0.65)),
              ],
            );
          }

          return FadeTransition(
            opacity: stagger,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.05),
                end: Offset.zero,
              ).animate(stagger),
              child: tile,
            ),
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Hero(
                tag: widget.heroTag,
                transitionOnUserGestures: true,
                child: Material(
                  color: ZveltTokens.surface,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  shape: _cardShape(),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 12, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(AppIcons.cross_small),
                              onPressed: () => Navigator.pop(context),
                              visualDensity: VisualDensity.compact,
                              style: IconButton.styleFrom(foregroundColor: ZveltTokens.text),
                            ),
                            Expanded(
                              child: Text(
                                'Exercise',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: ZveltTokens.text,
                                    ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(width: 48),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 8, right: 4, bottom: 2),
                          child: TextField(
                            controller: _search,
                            onChanged: (_) => setState(() {}),
                            style: ZType.bodyM.copyWith(color: ZveltTokens.text),
                            decoration: InputDecoration(
                              hintText: 'Search gym & calisthenics…',
                              hintStyle: ZType.bodyM.copyWith(color: ZveltTokens.text2.withValues(alpha: 0.85)),
                              prefixIcon: Icon(AppIcons.search, size: 22, color: ZveltTokens.text2),
                              filled: true,
                              fillColor: ZveltTokens.bg,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: ZveltTokens.s3),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: ZveltTokens.s3),
              Expanded(
                child: FadeTransition(
                  opacity: CurvedAnimation(
                    parent: openProgress,
                    curve: const Interval(0.12, 1.0, curve: Curves.easeOutCubic),
                  ),
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.04),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: openProgress,
                        curve: const Interval(0.12, 1.0, curve: Curves.easeOutCubic),
                      ),
                    ),
                    child: Material(
                      color: ZveltTokens.bg,
                      shape: _cardShape(),
                      clipBehavior: Clip.antiAlias,
                      child: listBody,
                    ),
                  ),
                ),
              ),
              SizedBox(height: bottomInset > 0 ? ZveltTokens.s1 : ZveltTokens.s3),
            ],
          ),
        ),
      ),
    );
  }
}
