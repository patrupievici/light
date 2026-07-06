import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/program_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/z/z_card.dart';
import 'programs_library_screen.dart' show programSchemeLabel;

/// Preview a program template (weeks × days × slots) and start it.
class ProgramDetailScreen extends StatefulWidget {
  const ProgramDetailScreen({super.key, required this.templateId});
  final String templateId;

  @override
  State<ProgramDetailScreen> createState() => _ProgramDetailScreenState();
}

class _ProgramDetailScreenState extends State<ProgramDetailScreen> {
  final _service = ProgramService();
  bool _loading = true;
  String? _error;
  ProgramTemplateDetail? _detail;

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
      final d = await _service.getTemplate(widget.templateId);
      if (!mounted) return;
      setState(() {
        _detail = d;
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

  Future<void> _openStartSheet() async {
    final detail = _detail;
    if (detail == null) return;
    final started = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StartProgramSheet(detail: detail, service: _service),
    );
    if (!mounted) return;
    if (started == true) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        backgroundColor: ZveltTokens.bg,
        elevation: 0,
        title: Text(detail?.title ?? 'Program', style: ZType.h4.copyWith(color: ZveltTokens.text)),
      ),
      body: SafeArea(child: _body()),
      bottomNavigationBar: detail == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(
                ZveltTokens.screenPaddingH,
                ZveltTokens.s2,
                ZveltTokens.screenPaddingH,
                ZveltTokens.s3,
              ),
              child: SizedBox(
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: ZveltTokens.brand,
                    foregroundColor: ZveltTokens.onBrand,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ZveltTokens.rMd)),
                  ),
                  onPressed: _openStartSheet,
                  icon: const Icon(AppIcons.play, size: 18),
                  label: Text('Start program',
                      style: ZType.bodyM.copyWith(
                          color: ZveltTokens.onBrand, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: ZveltTokens.brand));
    }
    final detail = _detail;
    if (detail == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(ZveltTokens.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? 'Error',
                  textAlign: TextAlign.center,
                  style: ZType.bodyM.copyWith(color: ZveltTokens.text2)),
              const SizedBox(height: ZveltTokens.s4),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: ZveltTokens.brand, foregroundColor: ZveltTokens.onBrand),
                onPressed: _load,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ZveltTokens.screenPaddingH,
        ZveltTokens.s4,
        ZveltTokens.screenPaddingH,
        ZveltTokens.s8,
      ),
      children: [
        Text(detail.description, style: ZType.bodyM.copyWith(color: ZveltTokens.text2, height: 1.5)),
        const SizedBox(height: ZveltTokens.s3),
        Wrap(
          spacing: ZveltTokens.s2,
          runSpacing: ZveltTokens.s2,
          children: [
            _pill('${detail.daysPerWeek}×/week'),
            _pill('${detail.defaultWeeks} weeks'),
            _pill(programSchemeLabel(detail.scheme)),
          ],
        ),
        const SizedBox(height: ZveltTokens.s5),
        Text('SESSIONS', style: ZType.eyebrow.copyWith(color: ZveltTokens.text3)),
        const SizedBox(height: ZveltTokens.s3),
        for (final d in detail.days) ...[
          _DayCard(day: d),
          const SizedBox(height: ZveltTokens.cardGap),
        ],
      ],
    );
  }

  Widget _pill(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: ZveltTokens.s2),
        decoration: BoxDecoration(
            color: ZveltTokens.bg2, borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
        child: Text(label, style: ZType.monoXS.copyWith(color: ZveltTokens.text2)),
      );
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day});
  final ProgramDayView day;

  @override
  Widget build(BuildContext context) {
    return ZCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(day.title, style: ZType.h4.copyWith(color: ZveltTokens.text)),
          const SizedBox(height: ZveltTokens.s3),
          for (int i = 0; i < day.slots.length; i++) ...[
            if (i > 0)
              Divider(height: ZveltTokens.s4, thickness: 0.5, color: ZveltTokens.hairline),
            _SlotRow(slot: day.slots[i]),
          ],
        ],
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({required this.slot});
  final ProgramSlotView slot;

  @override
  Widget build(BuildContext context) {
    final isMain = slot.role == 'main';
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(slot.exercise,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (isMain ? ZType.bodyM : ZType.bodyS).copyWith(
                      color: isMain ? ZveltTokens.text : ZveltTokens.text2,
                      fontWeight: isMain ? FontWeight.w600 : FontWeight.w400,
                    )),
              ),
              if (slot.warmup) ...[
                const SizedBox(width: ZveltTokens.s2),
                const Icon(AppIcons.flame, color: ZveltTokens.warn, size: 13),
              ],
            ],
          ),
        ),
        Text(slot.setsLabel, style: ZType.monoS.copyWith(color: ZveltTokens.text2)),
      ],
    );
  }
}

/// Bottom sheet: choose weeks + (for percentage programs) enter 1RMs, then start.
class _StartProgramSheet extends StatefulWidget {
  const _StartProgramSheet({required this.detail, required this.service});
  final ProgramTemplateDetail detail;
  final ProgramService service;

  @override
  State<_StartProgramSheet> createState() => _StartProgramSheetState();
}

/// User equipment tags (value, label) — matches the backend's
/// equipment-compatibility mapping. Empty selection = no filtering (full gym).
const List<(String, String)> kEquipmentOptions = [
  ('full_commercial_gym', 'Full gym'),
  ('barbell_rack', 'Barbell + rack'),
  ('dumbbells', 'Dumbbells'),
  ('cables', 'Cables'),
  ('machines', 'Machines'),
  ('pullup_bar', 'Pull-up bar'),
  ('kettlebells', 'Kettlebells'),
  ('resistance_bands', 'Resistance bands'),
  ('bodyweight_only', 'Bodyweight only'),
];

class _StartProgramSheetState extends State<_StartProgramSheet> {
  late int _weeks;
  final Map<String, TextEditingController> _tmControllers = {};
  final Set<String> _equipment = {};
  bool _starting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _weeks = widget.detail.defaultWeeks;
    for (final lift in widget.detail.trainingMaxLifts) {
      _tmControllers[lift] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _tmControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    final oneRepMaxes = <String, double>{};
    _tmControllers.forEach((lift, c) {
      final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
      if (v != null && v > 0) oneRepMaxes[lift] = v;
    });
    try {
      await widget.service.startProgram(
        templateId: widget.detail.id,
        weeks: _weeks,
        oneRepMaxes: oneRepMaxes.isEmpty ? null : oneRepMaxes,
        equipmentTags: _equipment.isEmpty ? null : _equipment.toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
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
            Text('Start ${detail.title}',
                style: ZType.h3.copyWith(color: ZveltTokens.text)),
            const SizedBox(height: ZveltTokens.s4),
            Text('DURATION', style: ZType.eyebrow.copyWith(color: ZveltTokens.text3)),
            const SizedBox(height: ZveltTokens.s2),
            Wrap(
              spacing: ZveltTokens.s2,
              children: [
                for (final w in detail.weeksOptions)
                  _WeekChip(
                    weeks: w,
                    selected: w == _weeks,
                    onTap: () => setState(() => _weeks = w),
                  ),
              ],
            ),
            const SizedBox(height: ZveltTokens.s5),
            Text('EQUIPMENT (optional)', style: ZType.eyebrow.copyWith(color: ZveltTokens.text3)),
            const SizedBox(height: ZveltTokens.s1),
            Text("Leave blank for a full gym. Choose what you have and we'll automatically swap incompatible exercises.",
                style: ZType.bodyS.copyWith(color: ZveltTokens.text3)),
            const SizedBox(height: ZveltTokens.s3),
            Wrap(
              spacing: ZveltTokens.s2,
              runSpacing: ZveltTokens.s2,
              children: [
                for (final opt in kEquipmentOptions)
                  _EquipChip(
                    label: opt.$2,
                    selected: _equipment.contains(opt.$1),
                    onTap: () => setState(() {
                      if (!_equipment.remove(opt.$1)) _equipment.add(opt.$1);
                    }),
                  ),
              ],
            ),
            if (detail.requiresTrainingMax) ...[
              const SizedBox(height: ZveltTokens.s5),
              Text('1RM (kg) — for working weights',
                  style: ZType.eyebrow.copyWith(color: ZveltTokens.text3)),
              const SizedBox(height: ZveltTokens.s1),
              Text('Optional — you can also set them later in the workout.',
                  style: ZType.bodyS.copyWith(color: ZveltTokens.text3)),
              const SizedBox(height: ZveltTokens.s3),
              for (final lift in detail.trainingMaxLifts) ...[
                _TmField(label: lift, controller: _tmControllers[lift]!),
                const SizedBox(height: ZveltTokens.s2),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: ZveltTokens.s3),
              Text(_error!, style: ZType.bodyS.copyWith(color: ZveltTokens.error)),
            ],
            const SizedBox(height: ZveltTokens.s5),
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
                onPressed: _starting ? null : _start,
                child: _starting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: ZveltTokens.onBrand))
                    : Text('Start',
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

class _WeekChip extends StatelessWidget {
  const _WeekChip({required this.weeks, required this.selected, required this.onTap});
  final int weeks;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
        decoration: BoxDecoration(
          color: selected ? ZveltTokens.brand : ZveltTokens.bg2,
          borderRadius: BorderRadius.circular(ZveltTokens.rMd),
        ),
        child: Text('$weeks weeks',
            style: ZType.bodyM.copyWith(
              color: selected ? ZveltTokens.onBrand : ZveltTokens.text2,
              fontWeight: FontWeight.w600,
            )),
      ),
    );
  }
}

class _EquipChip extends StatelessWidget {
  const _EquipChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: ZveltTokens.s2),
        decoration: BoxDecoration(
          color: selected ? ZveltTokens.brandTint : ZveltTokens.bg2,
          borderRadius: BorderRadius.circular(ZveltTokens.rPill),
          border: Border.all(
            color: selected ? ZveltTokens.brand : ZveltTokens.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(label,
            style: ZType.bodyS.copyWith(
              color: selected ? ZveltTokens.brandDeep : ZveltTokens.text2,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            )),
      ),
    );
  }
}

class _TmField extends StatelessWidget {
  const _TmField({required this.label, required this.controller});
  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: ZType.bodyM.copyWith(color: ZveltTokens.text)),
        ),
        SizedBox(
          width: 96,
          child: TextField(
            controller: controller,
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
    );
  }
}
