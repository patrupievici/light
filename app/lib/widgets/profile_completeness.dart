import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../services/profile_service.dart';
import '../theme/zvelt_tokens.dart';

class ProfileCompleteness {
  const ProfileCompleteness({
    required this.bodyweightOk,
    required this.birthYearOk,
    required this.sexOk,
    required this.displayNameOk,
  });

  final bool bodyweightOk;
  final bool birthYearOk;
  final bool sexOk;
  final bool displayNameOk;

  int get filledCount =>
      [bodyweightOk, birthYearOk, sexOk, displayNameOk].where((x) => x).length;

  int get total => 4;

  bool get isComplete => filledCount >= total;

  static ProfileCompleteness fromProfile(Map<String, dynamic>? profile) {
    if (profile == null) {
      return const ProfileCompleteness(
        bodyweightOk: false,
        birthYearOk: false,
        sexOk: false,
        displayNameOk: false,
      );
    }
    final bw = profile['bodyweightKg'];
    final bwVal = bw is num ? bw.toDouble() : double.tryParse('$bw');
    final birth = profile['birthYear'];
    final birthVal = birth is num ? birth.toInt() : int.tryParse('$birth');
    final sex = (profile['sex'] as String?)?.trim();
    final name = (profile['displayName'] as String?)?.trim();
    return ProfileCompleteness(
      bodyweightOk: bwVal != null && bwVal >= 30 && bwVal <= 250,
      birthYearOk: birthVal != null && birthVal >= 1920 && birthVal <= DateTime.now().year - 10,
      sexOk: sex == 'male' || sex == 'female' || sex == 'other',
      displayNameOk: name != null && name.isNotEmpty,
    );
  }
}

class ProfileCompletenessChip extends StatelessWidget {
  const ProfileCompletenessChip({super.key, required this.completeness, this.onTap});

  final ProfileCompleteness completeness;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (completeness.isComplete) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: ZveltTokens.info.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ZveltTokens.rMd),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ZveltTokens.rMd),
              border: Border.all(color: ZveltTokens.info.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(AppIcons.user, color: ZveltTokens.info, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Complete profile (${completeness.filledCount}/${completeness.total})',
                        style: TextStyle(
                          color: ZveltTokens.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _missingLabel(completeness),
                        style: TextStyle(color: ZveltTokens.text2, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Icon(AppIcons.angle_small_right, color: ZveltTokens.text2),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _missingLabel(ProfileCompleteness c) {
    final missing = <String>[];
    if (!c.bodyweightOk) missing.add('bodyweight');
    if (!c.birthYearOk) missing.add('birth year');
    if (!c.sexOk) missing.add('sex');
    if (!c.displayNameOk) missing.add('name');
    return 'Unlock fair XP & ranks: ${missing.join(', ')}';
  }
}

/// 30-second wizard for missing profile fields.
class ProfileCompletenessSheet extends StatefulWidget {
  const ProfileCompletenessSheet({super.key, required this.initial});

  final ProfileCompleteness initial;

  @override
  State<ProfileCompletenessSheet> createState() => _ProfileCompletenessSheetState();
}

class _ProfileCompletenessSheetState extends State<ProfileCompletenessSheet> {
  final _profile = ProfileService();
  final _nameCtrl = TextEditingController();
  final _bwCtrl = TextEditingController();
  final _birthCtrl = TextEditingController();
  String? _sex;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bwCtrl.dispose();
    _birthCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      if (!widget.initial.displayNameOk && _nameCtrl.text.trim().isEmpty &&
          !widget.initial.bodyweightOk && _bwCtrl.text.trim().isEmpty &&
          !widget.initial.birthYearOk && _birthCtrl.text.trim().isEmpty &&
          (!widget.initial.sexOk && _sex == null)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fill at least one missing field.')),
          );
        }
        return;
      }
      await _profile.updateProfile(
        displayName: !widget.initial.displayNameOk && _nameCtrl.text.trim().isNotEmpty
            ? _nameCtrl.text.trim()
            : null,
        bodyweightKg: !widget.initial.bodyweightOk
            ? double.tryParse(_bwCtrl.text.replaceAll(',', '.'))
            : null,
        birthYear: !widget.initial.birthYearOk ? int.tryParse(_birthCtrl.text.trim()) : null,
        sex: !widget.initial.sexOk ? _sex : null,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          const SizedBox(height: 16),
          Text(
            'Quick profile setup',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ZveltTokens.text),
          ),
          const SizedBox(height: 6),
          Text(
            'Used for fair XP, masters bonus, and strength ranks.',
            style: TextStyle(color: ZveltTokens.text2, fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (!widget.initial.displayNameOk) ...[
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            const SizedBox(height: 12),
          ],
          if (!widget.initial.bodyweightOk) ...[
            TextField(
              controller: _bwCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Bodyweight (kg)'),
            ),
            const SizedBox(height: 12),
          ],
          if (!widget.initial.birthYearOk) ...[
            TextField(
              controller: _birthCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Birth year'),
            ),
            const SizedBox(height: 12),
          ],
          if (!widget.initial.sexOk) ...[
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'male', label: Text('Male')),
                ButtonSegment(value: 'female', label: Text('Female')),
              ],
              selected: _sex == null ? {} : {_sex!},
              onSelectionChanged: (s) => setState(() => _sex = s.first),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: ZveltTokens.onBrand),
                  )
                : const Text('Save & continue'),
          ),
        ],
      ),
    );
  }
}
