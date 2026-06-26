import 'package:flutter/material.dart';

import '../../services/program_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/z/z_card.dart';
import 'program_detail_screen.dart';
import 'active_program_screen.dart';

/// Helpers shared by the program screens — human labels for the enum-ish fields.
String programSchemeLabel(String scheme) {
  switch (scheme) {
    case 'linear':
      return 'Progresie liniară';
    case 'double':
      return 'Progresie dublă';
    case 'percentage':
      return '% din 1RM';
    case 'reps_sum':
      return 'Volum';
    default:
      return 'Autoreglat';
  }
}

String programSplitLabel(String split) {
  switch (split) {
    case 'push_pull_legs':
      return 'PPL';
    case 'upper_lower':
      return 'Upper / Lower';
    case 'full_body':
      return 'Full Body';
    case 'arnold':
      return 'Arnold';
    default:
      return split;
  }
}

String programLevelLabel(String level) {
  switch (level) {
    case 'beginner':
      return 'Începător';
    case 'advanced':
      return 'Avansat';
    default:
      return 'Intermediar';
  }
}

/// The "Programe" library — browse multi-week templates and start one.
class ProgramsLibraryScreen extends StatefulWidget {
  const ProgramsLibraryScreen({super.key});

  @override
  State<ProgramsLibraryScreen> createState() => _ProgramsLibraryScreenState();
}

class _ProgramsLibraryScreenState extends State<ProgramsLibraryScreen> {
  final _service = ProgramService();
  bool _loading = true;
  String? _error;
  List<ProgramSummary> _templates = const [];
  ActiveProgram? _active;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        backgroundColor: ZveltTokens.bg,
        elevation: 0,
        title: Text('Programe', style: ZType.h3.copyWith(color: ZveltTokens.text)),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading && _templates.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: ZveltTokens.brand));
    }
    if (_error != null && _templates.isEmpty) {
      return _ErrorView(message: _error!, onRetry: _load);
    }
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
          if (_active != null) ...[
            _ActiveBanner(program: _active!, onTap: _openActive),
            const SizedBox(height: ZveltTokens.s5),
          ],
          Text('Alege un program',
              style: ZType.eyebrow.copyWith(color: ZveltTokens.text3)),
          const SizedBox(height: ZveltTokens.s3),
          for (final t in _templates) ...[
            _ProgramCard(summary: t, onTap: () => _openTemplate(t)),
            const SizedBox(height: ZveltTokens.cardGap),
          ],
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
                Text('Continuă programul',
                    style: ZType.eyebrow.copyWith(color: ZveltTokens.brandDeep)),
                const SizedBox(height: 2),
                Text(program.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZType.h4.copyWith(color: ZveltTokens.text)),
                Text('Săptămâna ${program.currentWeek} din ${program.totalWeeks}',
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

  @override
  Widget build(BuildContext context) {
    return ZCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(summary.title,
                    style: ZType.h4.copyWith(color: ZveltTokens.text)),
              ),
              Icon(AppIcons.angle_small_right, color: ZveltTokens.text3, size: 22),
            ],
          ),
          const SizedBox(height: ZveltTokens.s2),
          Text(summary.description,
              style: ZType.bodyS.copyWith(color: ZveltTokens.text2, height: 1.4)),
          const SizedBox(height: ZveltTokens.s3),
          Wrap(
            spacing: ZveltTokens.s2,
            runSpacing: ZveltTokens.s2,
            children: [
              _MetaChip(
                  icon: AppIcons.calendar,
                  label: '${summary.daysPerWeek}×/săpt · ${summary.defaultWeeks} săpt'),
              _MetaChip(icon: AppIcons.chart_line_up, label: programSchemeLabel(summary.scheme)),
              _MetaChip(icon: AppIcons.target, label: programLevelLabel(summary.level)),
              if (summary.requiresTrainingMax)
                const _MetaChip(icon: AppIcons.percentage, label: 'Necesită 1RM', accent: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label, this.accent = false});
  final IconData icon;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final fg = accent ? ZveltTokens.brandDeep : ZveltTokens.text2;
    final bg = accent ? ZveltTokens.brandTint : ZveltTokens.bg2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: ZveltTokens.s2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fg, size: 13),
          const SizedBox(width: ZveltTokens.s1),
          Text(label, style: ZType.monoXS.copyWith(color: fg)),
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
              child: const Text('Reîncearcă'),
            ),
          ],
        ),
      ),
    );
  }
}
