import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/program_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/z/z_card.dart';
import 'workout_tracker_screen.dart';

String _fmtKg(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// The active program: week progress, today's materialized session, and the
/// button that opens the live tracker with auto-filled targets. Also handles the
/// completed-program state and setting training maxes for percentage programs.
class ActiveProgramScreen extends StatefulWidget {
  const ActiveProgramScreen({super.key});

  @override
  State<ActiveProgramScreen> createState() => _ActiveProgramScreenState();
}

class _ActiveProgramScreenState extends State<ActiveProgramScreen> {
  final _service = ProgramService();
  bool _loading = true;
  bool _starting = false;
  String? _error;
  ActiveProgramView? _view;
  List<String> _tmLifts = const [];

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
      final v = await _service.getActive();
      if (!mounted) return;
      // For percentage programs we need the lift names to prompt for / edit 1RMs.
      List<String> lifts = const [];
      final prog = v.program;
      if (prog != null && prog.progressionScheme == 'percentage') {
        try {
          final tpl = await _service.getTemplate(prog.templateId);
          lifts = tpl.trainingMaxLifts;
        } catch (_) {/* best-effort — banner just won't show */}
      }
      if (!mounted) return;
      setState(() {
        _view = v;
        _tmLifts = lifts;
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

  void _toast(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZveltTokens.rSm)),
    ));
  }

  Future<void> _startSession() async {
    final program = _view?.program;
    if (program == null) return;
    setState(() => _starting = true);
    try {
      final workoutId = await _service.startProgramDay(program.id);
      if (!mounted) return;
      // The tracker fires onComplete only when the session is actually finished.
      // We capture that as a local flag and advance AFTER the tracker closes —
      // awaited, on a mounted state — instead of firing advance from inside a
      // callback that may run on a disposed widget (avoids the race + crash).
      var completedWorkout = false;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => WorkoutTrackerScreen(
            workoutId: workoutId,
            onComplete: () => completedWorkout = true,
          ),
        ),
      );
      if (completedWorkout) {
        try {
          await _service.advance(program.id);
        } catch (_) {/* best-effort; _load reflects server truth below */}
      }
      if (!mounted) return;
      await _load();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), ZveltTokens.error);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _skipSession() async {
    final program = _view?.program;
    if (program == null) return;
    try {
      await _service.advance(program.id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), ZveltTokens.error);
    }
  }

  Future<void> _archive() async {
    final program = _view?.program;
    if (program == null) return;
    try {
      await _service.archive(program.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), ZveltTokens.error);
    }
  }

  Future<void> _openTmSheet() async {
    final program = _view?.program;
    if (program == null || _tmLifts.isEmpty) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TrainingMaxSheet(
        service: _service,
        programId: program.id,
        lifts: _tmLifts,
        current: program.trainingMaxes,
      ),
    );
    if (!mounted) return;
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final program = _view?.program;
    final isActive = program != null && !(_view?.completed ?? false);
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        backgroundColor: ZveltTokens.bg,
        elevation: 0,
        title: Text('My Program', style: ZType.h4.copyWith(color: ZveltTokens.text)),
        actions: [
          if (isActive)
            PopupMenuButton<String>(
              icon: Icon(AppIcons.menu_dots_vertical, color: ZveltTokens.text2, size: 18),
              onSelected: (v) {
                if (v == 'tm') _openTmSheet();
                if (v == 'skip') _skipSession();
                if (v == 'archive') _archive();
              },
              itemBuilder: (_) => [
                if (_tmLifts.isNotEmpty)
                  const PopupMenuItem<String>(value: 'tm', child: Text('Edit 1RM')),
                const PopupMenuItem<String>(value: 'skip', child: Text('Skip session')),
                const PopupMenuItem<String>(value: 'archive', child: Text('Archive program')),
              ],
            ),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: ZveltTokens.brand));
    }
    final program = _view?.program;
    final completed = _view?.completed ?? false;

    if (program == null) {
      return _EmptyState(
        message: _error ?? 'No active program',
        onPick: () => Navigator.of(context).pop(),
      );
    }
    if (completed) {
      return _CompletionCard(program: program, onPick: () => Navigator.of(context).pop());
    }

    final today = _view?.today;
    final needsTm = _tmLifts.isNotEmpty &&
        _tmLifts.any((l) => !(program.trainingMaxes[l] != null && program.trainingMaxes[l]! > 0));
    final progress = (program.currentWeek / program.totalWeeks).clamp(0.0, 1.0);

    return RefreshIndicator(
      color: ZveltTokens.brand,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          ZveltTokens.screenPaddingH,
          ZveltTokens.s4,
          ZveltTokens.screenPaddingH,
          ZveltTokens.s10,
        ),
        children: [
          ZCard(
            shadow: ZveltTokens.shadowHero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(program.title, style: ZType.h3.copyWith(color: ZveltTokens.text)),
                const SizedBox(height: ZveltTokens.s1),
                Text('Week ${program.currentWeek} of ${program.totalWeeks}',
                    style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
                const SizedBox(height: ZveltTokens.s3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: ZveltTokens.bg2,
                    valueColor: const AlwaysStoppedAnimation<Color>(ZveltTokens.brand),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: ZveltTokens.s5),
          if (needsTm) ...[
            _NeedsTmBanner(onTap: _openTmSheet),
            const SizedBox(height: ZveltTokens.s4),
          ],
          if (today != null && today.isDeload) ...[
            const _DeloadBanner(),
            const SizedBox(height: ZveltTokens.s4),
          ],
          if (today == null)
            Text('No session to show.', style: ZType.bodyM.copyWith(color: ZveltTokens.text2))
          else
            _TodayCard(day: today, starting: _starting, onStart: _startSession),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, required this.onPick});
  final String message;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZveltTokens.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.gym, color: ZveltTokens.text3, size: 40),
            const SizedBox(height: ZveltTokens.s4),
            Text(message,
                textAlign: TextAlign.center, style: ZType.bodyM.copyWith(color: ZveltTokens.text2)),
            const SizedBox(height: ZveltTokens.s4),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: ZveltTokens.brand, foregroundColor: ZveltTokens.onBrand),
              onPressed: onPick,
              child: const Text('Choose a program'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletionCard extends StatelessWidget {
  const _CompletionCard({required this.program, required this.onPick});
  final ActiveProgram program;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZveltTokens.s5),
        child: ZCard(
          shadow: ZveltTokens.shadowHero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(color: ZveltTokens.brand, shape: BoxShape.circle),
                child: const Icon(AppIcons.trophy, color: ZveltTokens.onBrand, size: 28),
              ),
              const SizedBox(height: ZveltTokens.s4),
              Text('Program complete!', style: ZType.h3.copyWith(color: ZveltTokens.text)),
              const SizedBox(height: ZveltTokens.s1),
              Text('${program.title} · ${program.totalWeeks} weeks',
                  textAlign: TextAlign.center,
                  style: ZType.bodyM.copyWith(color: ZveltTokens.text2)),
              const SizedBox(height: ZveltTokens.s2),
              Text('Great work — you finished the full block.',
                  textAlign: TextAlign.center,
                  style: ZType.bodyS.copyWith(color: ZveltTokens.text3)),
              const SizedBox(height: ZveltTokens.s5),
              SizedBox(
                height: 50,
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: ZveltTokens.brand,
                    foregroundColor: ZveltTokens.onBrand,
                    shape:
                        RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZveltTokens.rMd)),
                  ),
                  onPressed: onPick,
                  child: const Text('Choose next program'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NeedsTmBanner extends StatelessWidget {
  const _NeedsTmBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
        child: Container(
          padding: const EdgeInsets.all(ZveltTokens.s4),
          decoration: BoxDecoration(
            color: ZveltTokens.brandTint,
            borderRadius: BorderRadius.circular(ZveltTokens.rMd),
          ),
          child: Row(
            children: [
              const Icon(AppIcons.percentage, color: ZveltTokens.brandDeep, size: 20),
              const SizedBox(width: ZveltTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Set your 1RMs',
                        style: ZType.bodyM.copyWith(
                            color: ZveltTokens.text, fontWeight: FontWeight.w600)),
                    Text('The program calculates working weights from 1RM. Tap to enter them.',
                        style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
                  ],
                ),
              ),
              const Icon(AppIcons.angle_small_right, color: ZveltTokens.brandDeep, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeloadBanner extends StatelessWidget {
  const _DeloadBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.stress2,
        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
      ),
      child: Row(
        children: [
          const Icon(AppIcons.moon, color: ZveltTokens.stress, size: 20),
          const SizedBox(width: ZveltTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Deload week',
                    style: ZType.bodyM.copyWith(
                        color: ZveltTokens.text, fontWeight: FontWeight.w600)),
                Text('Reduced weight and volume so fatigue can drop.',
                    style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.day, required this.starting, required this.onStart});
  final MaterializedDay day;
  final bool starting;
  final VoidCallback onStart;

  String _target(MaterializedExercise e) {
    if (e.setsDetail.isNotEmpty) {
      final weights = e.setsDetail.map((s) => s.weightKg).whereType<double>().toList();
      final top = weights.isEmpty ? null : weights.reduce((a, b) => a > b ? a : b);
      final amrap = e.setsDetail.any((s) => s.amrap);
      return '${e.setsDetail.length} sets'
          '${top != null ? ' · top ${_fmtKg(top)}kg' : ' · set 1RM'}'
          '${amrap ? ' · AMRAP' : ''}';
    }
    final w = e.suggestedWeightKg;
    return '${e.sets}×${e.reps}${w != null && w > 0 ? ' @ ${_fmtKg(w)}kg' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    return ZCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("TODAY'S SESSION",
                        style: ZType.eyebrow.copyWith(color: ZveltTokens.brandDeep)),
                    const SizedBox(height: 2),
                    Text(day.title, style: ZType.h4.copyWith(color: ZveltTokens.text)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: ZveltTokens.s3, vertical: ZveltTokens.s1),
                decoration: BoxDecoration(
                    color: ZveltTokens.bg2,
                    borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
                child: Text('S${day.week}',
                    style: ZType.monoXS.copyWith(color: ZveltTokens.text2)),
              ),
            ],
          ),
          const SizedBox(height: ZveltTokens.s4),
          for (int i = 0; i < day.exercises.length; i++) ...[
            if (i > 0)
              Divider(height: ZveltTokens.s4, thickness: 0.5, color: ZveltTokens.hairline),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(day.exercises[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ZType.bodyM.copyWith(color: ZveltTokens.text)),
                      ),
                      if (day.exercises[i].warmups.isNotEmpty) ...[
                        const SizedBox(width: ZveltTokens.s2),
                        const Icon(AppIcons.flame, color: ZveltTokens.warn, size: 13),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: ZveltTokens.s2),
                Text(_target(day.exercises[i]),
                    style: ZType.monoS.copyWith(color: ZveltTokens.text2)),
              ],
            ),
          ],
          const SizedBox(height: ZveltTokens.s5),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: ZveltTokens.brand,
                foregroundColor: ZveltTokens.onBrand,
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZveltTokens.rMd)),
              ),
              onPressed: starting ? null : onStart,
              icon: starting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: ZveltTokens.onBrand))
                  : const Icon(AppIcons.play, size: 18),
              label: Text('Start session',
                  style: ZType.bodyM.copyWith(
                      color: ZveltTokens.onBrand, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sheet to set/refresh training maxes (entered as 1RM, converted server-side).
class _TrainingMaxSheet extends StatefulWidget {
  const _TrainingMaxSheet({
    required this.service,
    required this.programId,
    required this.lifts,
    required this.current,
  });
  final ProgramService service;
  final String programId;
  final List<String> lifts;
  final Map<String, double> current;

  @override
  State<_TrainingMaxSheet> createState() => _TrainingMaxSheetState();
}

class _TrainingMaxSheetState extends State<_TrainingMaxSheet> {
  final Map<String, TextEditingController> _controllers = {};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final lift in widget.lifts) {
      // Prefill with the implied 1RM from the stored training max (TM ≈ 90% 1RM).
      final tm = widget.current[lift];
      final orm = tm != null && tm > 0 ? (tm / 0.9) : null;
      _controllers[lift] =
          TextEditingController(text: orm != null ? _fmtKg(orm) : '');
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final oneRepMaxes = <String, double>{};
    _controllers.forEach((lift, c) {
      final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
      if (v != null && v > 0) oneRepMaxes[lift] = v;
    });
    if (oneRepMaxes.isEmpty) {
      setState(() => _error = 'Enter at least one 1RM');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.setTrainingMaxes(widget.programId, oneRepMaxes);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: ZveltTokens.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
        ),
        padding: const EdgeInsets.fromLTRB(
            ZveltTokens.s5, ZveltTokens.s4, ZveltTokens.s5, ZveltTokens.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: ZveltTokens.s4),
                decoration: BoxDecoration(
                    color: ZveltTokens.border,
                    borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
              ),
            ),
            Text('Training max (1RM)', style: ZType.h3.copyWith(color: ZveltTokens.text)),
            const SizedBox(height: ZveltTokens.s1),
            Text('Enter your 1RM (kg) for each lift. Working weights are calculated from it.',
                style: ZType.bodyS.copyWith(color: ZveltTokens.text3)),
            const SizedBox(height: ZveltTokens.s4),
            for (final lift in widget.lifts) ...[
              Row(
                children: [
                  Expanded(child: Text(lift, style: ZType.bodyM.copyWith(color: ZveltTokens.text))),
                  SizedBox(
                    width: 96,
                    child: TextField(
                      controller: _controllers[lift],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      textAlign: TextAlign.center,
                      style: ZType.num_.copyWith(color: ZveltTokens.text),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'kg',
                        hintStyle: ZType.bodyS.copyWith(color: ZveltTokens.text4),
                        filled: true,
                        fillColor: ZveltTokens.bg2,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: ZveltTokens.s3, vertical: ZveltTokens.s3),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ZveltTokens.s2),
            ],
            if (_error != null) ...[
              const SizedBox(height: ZveltTokens.s2),
              Text(_error!, style: ZType.bodyS.copyWith(color: ZveltTokens.error)),
            ],
            const SizedBox(height: ZveltTokens.s4),
            SizedBox(
              height: 52,
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: ZveltTokens.brand,
                  foregroundColor: ZveltTokens.onBrand,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ZveltTokens.rMd)),
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: ZveltTokens.onBrand))
                    : Text('Save',
                        style: ZType.bodyM.copyWith(
                            color: ZveltTokens.onBrand, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
