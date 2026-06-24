import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../../data/challenge_exercise_catalog.dart';
import '../../models/social_challenge.dart';
import '../../services/social_challenge_service.dart';
import '../../theme/zvelt_tokens.dart';
import 'challenge_kind_picker_screen.dart';

/// Bottom sheet: creează o provocare (vizibilitate prieteni / public).
class CreateChallengeSheet extends StatefulWidget {
  const CreateChallengeSheet({super.key});

  /// Tag comun pentru [Hero] între declanșator și [ChallengeKindPickerPage].
  static const String challengeKindHeroTag = 'zvelt_create_challenge_kind';

  @override
  State<CreateChallengeSheet> createState() => _CreateChallengeSheetState();
}

class _CreateChallengeSheetState extends State<CreateChallengeSheet> {
  final _service = SocialChallengeService();
  final _customCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();

  ChallengeCatalogEntry _catalog = defaultChallengeCatalogEntry;
  String _visibility = 'friends';
  int _durationDays = 14;
  bool _saving = false;

  static const _durations = [7, 14, 30, 90];

  @override
  void dispose() {
    _customCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final publishedCustom = _catalog.customTitleForPublish(_customCtrl.text);
    if (_catalog.requiresManualTitle && publishedCustom.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a title for your custom challenge.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final challenge = SocialChallenge(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        kind: _catalog.apiKind,
        customTitle: publishedCustom,
        visibility: _visibility,
        targetHint: _targetCtrl.text.trim().isEmpty ? null : _targetCtrl.text.trim(),
        durationDays: _durationDays,
        createdAt: now,
        endsAt: now.add(Duration(days: _durationDays)),
      );
      await _service.publish(challenge);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
      setState(() => _saving = false);
    }
  }

  Future<void> _openKindPicker() async {
    // Fără rootNavigator: Hero trebuie să rămână pe același Navigator cu modalul bottom sheet.
    final picked = await Navigator.of(context).push<ChallengeCatalogEntry?>(
      ChallengeKindPickerPage.route(
        heroTag: CreateChallengeSheet.challengeKindHeroTag,
        selected: _catalog,
      ),
    );
    if (picked != null && mounted) setState(() => _catalog = picked);
  }

  @override
  Widget build(BuildContext context) {
    final padBottom = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, padBottom + 16),
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(ZveltTokens.s5),
            decoration: BoxDecoration(
              color: ZveltTokens.surface,
              borderRadius: BorderRadius.circular(ZveltTokens.rLg),
              boxShadow: ZveltTokens.shadowCard,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(AppIcons.trophy, color: ZveltTokens.brand, size: 26),
                    const SizedBox(width: 10),
                    Text(
                      'Create challenge',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: ZveltTokens.text,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Friends see friends-only challenges; public is visible to everyone active on the app. Offline creates are saved on device and retry when you refresh.',
                  style: TextStyle(color: ZveltTokens.text2, fontSize: 12, height: 1.35),
                ),
                const SizedBox(height: ZveltTokens.s5),
                Text(
                  'Who can see it?',
                  style: TextStyle(
                    color: ZveltTokens.text2,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'friends', label: Text('Friends'), icon: Icon(AppIcons.users, size: 18)),
                    ButtonSegment(value: 'public', label: Text('Public'), icon: Icon(AppIcons.globe, size: 18)),
                  ],
                  selected: {_visibility},
                  onSelectionChanged: (s) => setState(() => _visibility = s.first),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) return ZveltTokens.onBrand;
                      return ZveltTokens.text;
                    }),
                  ),
                ),
                const SizedBox(height: ZveltTokens.s5),
                Text(
                  'Challenge type',
                  style: TextStyle(
                    color: ZveltTokens.text2,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Hero(
                  tag: CreateChallengeSheet.challengeKindHeroTag,
                  transitionOnUserGestures: true,
                  child: Material(
                    color: ZveltTokens.surface,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                      side: BorderSide(color: ZveltTokens.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _saving ? null : _openKindPicker,
                      borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s4),
                        child: Row(
                          children: [
                            const Icon(AppIcons.gym, color: ZveltTokens.brand, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Tap to choose',
                                    style: TextStyle(
                                      color: ZveltTokens.text2,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _catalog.displayName,
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: ZveltTokens.text,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(AppIcons.angle_small_down, color: ZveltTokens.text2),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (_catalog.requiresManualTitle) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _customCtrl,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Challenge title',
                      hintText: 'e.g. 10k steps daily',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _targetCtrl,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: 'Goal (optional)',
                    hintText: 'e.g. 20 reps · 140 kg · 5 km',
                  ),
                ),
                const SizedBox(height: ZveltTokens.s4),
                Text(
                  'Duration',
                  style: TextStyle(
                    color: ZveltTokens.text2,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _durations.map((d) {
                    final sel = _durationDays == d;
                    return ChoiceChip(
                      label: Text('$d days'),
                      selected: sel,
                      onSelected: (_) => setState(() => _durationDays = d),
                    );
                  }).toList(),
                ),
                const SizedBox(height: ZveltTokens.s6),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: ZveltTokens.onBrand),
                        )
                      : const Text('Publish challenge'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
