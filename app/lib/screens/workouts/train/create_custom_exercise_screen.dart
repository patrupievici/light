import 'package:flutter/material.dart';

import '../../../services/workout_service.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/zvelt_tokens.dart';

/// "New exercise" — a single-column form for creating a user's custom exercise.
///
/// Returns the created [ExerciseDto] to the caller via `Navigator.pop(context,
/// exercise)` on success (the caller shows the confirmation snackbar). Pops with
/// `null` if the user backs out.
///
/// **Backend dependency:** the POST `/v1/exercises/custom` contract is ASSUMED
/// from CLAUDE.md's API conventions and has not been verified against a live
/// server — field names / status codes may need adjusting once the endpoint
/// ships.
///
/// Neutrals come from the theme-aware [ZveltTokens] getters, so any decoration
/// or style that reads them can't be `const` (only the brand / status colors are
/// compile-time constants).
class CreateCustomExerciseScreen extends StatefulWidget {
  const CreateCustomExerciseScreen({super.key});

  @override
  State<CreateCustomExerciseScreen> createState() =>
      _CreateCustomExerciseScreenState();
}

class _CreateCustomExerciseScreenState
    extends State<CreateCustomExerciseScreen> {
  static const List<String> _muscles = [
    'Chest',
    'Back',
    'Legs',
    'Shoulders',
    'Arms',
    'Core',
  ];
  static const List<String> _equipment = [
    'Barbell',
    'Dumbbell',
    'Machine',
    'Cable',
    'Bodyweight',
    'Other',
  ];

  final TextEditingController _nameController = TextEditingController();
  String? _selectedMuscle;
  String? _selectedEquipment;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Re-evaluate the Create button's enabled state as the name is typed.
    _nameController.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    super.dispose();
  }

  void _onNameChanged() => setState(() {});

  bool get _canSubmit =>
      !_saving && _nameController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _saving = true);
    try {
      final exercise = await WorkoutService().createCustomExercise(
        name: _nameController.text.trim(),
        primaryMuscle: _selectedMuscle,
        equipment: _selectedEquipment,
      );
      if (!mounted) return;
      Navigator.pop(context, exercise);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ZveltTokens.error,
          content: Text(
            e.toString(),
            style: ZType.bodyM.copyWith(color: ZveltTokens.onBrand),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        backgroundColor: ZveltTokens.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(AppIcons.angle_small_left, color: ZveltTokens.text),
          onPressed: () => Navigator.maybePop(context),
          tooltip: 'Back',
        ),
        title: Text(
          'New exercise',
          style: ZType.h3.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Name ──────────────────────────────────────────────────
              const _FieldLabel('Exercise name'),
              const SizedBox(height: 8),
              _NameInput(controller: _nameController),
              const SizedBox(height: 24),

              // ── Primary muscle ────────────────────────────────────────
              const _FieldLabel('Primary muscle'),
              const SizedBox(height: 10),
              _ChipWrap(
                options: _muscles,
                selected: _selectedMuscle,
                onSelected: (v) => setState(
                  () => _selectedMuscle = _selectedMuscle == v ? null : v,
                ),
              ),
              const SizedBox(height: 24),

              // ── Equipment ─────────────────────────────────────────────
              const _FieldLabel('Equipment'),
              const SizedBox(height: 10),
              _ChipWrap(
                options: _equipment,
                selected: _selectedEquipment,
                onSelected: (v) => setState(
                  () => _selectedEquipment =
                      _selectedEquipment == v ? null : v,
                ),
              ),
              const SizedBox(height: 32),

              // ── Create CTA ────────────────────────────────────────────
              _CreateButton(
                enabled: _canSubmit,
                saving: _saving,
                onTap: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: ZType.bodyM.copyWith(
        color: ZveltTokens.text,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _NameInput extends StatelessWidget {
  const _NameInput({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
        boxShadow: ZveltTokens.shadowCard,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TextField(
        controller: controller,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        style: ZType.bodyL.copyWith(color: ZveltTokens.text),
        cursorColor: ZveltTokens.brand,
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          hintText: 'e.g. Cable lateral raise',
          hintStyle: ZType.bodyL.copyWith(color: ZveltTokens.text3),
        ),
      ),
    );
  }
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          _SelectChip(
            label: option,
            selected: option == selected,
            onTap: () => onSelected(option),
          ),
      ],
    );
  }
}

class _SelectChip extends StatelessWidget {
  const _SelectChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? ZveltTokens.brand : ZveltTokens.bg2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: ZType.bodyM.copyWith(
            color: selected ? ZveltTokens.onBrand : ZveltTokens.text2,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _CreateButton extends StatelessWidget {
  const _CreateButton({
    required this.enabled,
    required this.saving,
    required this.onTap,
  });

  final bool enabled;
  final bool saving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ZveltTokens.brand,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(ZveltTokens.onBrand),
                  ),
                )
              : Text(
                  'Create',
                  style: ZType.bodyL.copyWith(
                    color: ZveltTokens.onBrand,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
        ),
      ),
    );
  }
}
