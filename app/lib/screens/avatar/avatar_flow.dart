import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'avatar_intro_screen.dart';
import 'avatar_selection_screen.dart';
import 'avatar_confirm_screen.dart';

const String kAvatarFlowCompletedKey = 'avatar_flow_completed';
const String kSelectedAvatarIdKey = 'selected_avatar_id';

/// Default avatar options (icons). Replace with image assets later if needed.
List<AvatarOption> get defaultAvatarOptions => const [
  AvatarOption(id: 'avatar_1', icon: Icons.person),
  AvatarOption(id: 'avatar_2', icon: Icons.directions_run),
  AvatarOption(id: 'avatar_3', icon: Icons.fitness_center),
  AvatarOption(id: 'avatar_4', icon: Icons.self_improvement),
  AvatarOption(id: 'avatar_5', icon: Icons.sports_martial_arts),
  AvatarOption(id: 'avatar_6', icon: Icons.bolt),
  AvatarOption(id: 'avatar_7', icon: Icons.star),
  AvatarOption(id: 'avatar_8', icon: Icons.emoji_events),
  AvatarOption(id: 'avatar_9', icon: Icons.person_outline),
];

/// Flow FIG 20–24: Intro → Selection → Confirm. Saves completion + selected avatar id.
class AvatarFlow extends StatefulWidget {
  const AvatarFlow({super.key, required this.onComplete, this.completionKey});

  final VoidCallback onComplete;
  /// Cheie SharedPreferences per user; dacă lipsește, se folosește cea globală.
  final String? completionKey;

  @override
  State<AvatarFlow> createState() => _AvatarFlowState();
}

class _AvatarFlowState extends State<AvatarFlow> {
  int _step = 0;
  String? _selectedAvatarId;
  late final List<AvatarOption> _options;

  @override
  void initState() {
    super.initState();
    _options = defaultAvatarOptions;
  }

  Future<void> _finish() async {
    if (_selectedAvatarId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(widget.completionKey ?? kAvatarFlowCompletedKey, true);
    await prefs.setString(kSelectedAvatarIdKey, _selectedAvatarId!);
    if (!mounted) return;
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    if (_step == 0) {
      return AvatarIntroScreen(
        onContinue: () => setState(() => _step = 1),
      );
    }
    if (_step == 1) {
      return AvatarSelectionScreen(
        options: _options,
        onNext: (id) {
          setState(() {
            _selectedAvatarId = id;
            _step = 2;
          });
        },
      );
    }
    final option = _options.firstWhere((o) => o.id == _selectedAvatarId);
    return AvatarConfirmScreen(
      avatarOption: option,
      onContinue: _finish,
    );
  }
}
