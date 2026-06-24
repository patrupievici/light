import 'dart:typed_data';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/zvelt_tokens.dart';
import '../../services/social_feed_service.dart';
import '../../widgets/zvelt_secondary_button.dart';

/// Postare în feed: după workout ([workoutId] setat) sau direct din Social ([workoutId] null — ai nevoie de mesaj sau poză).
class PostWorkoutScreen extends StatefulWidget {
  const PostWorkoutScreen({super.key, this.workoutId, this.initialCaption});
  final String? workoutId;
  final String? initialCaption;

  @override
  State<PostWorkoutScreen> createState() => _PostWorkoutScreenState();
}

class _PostWorkoutScreenState extends State<PostWorkoutScreen> {
  final _caption = TextEditingController();
  final _feed = SocialFeedService();
  final _picker = ImagePicker();

  Uint8List? _photoBytes;
  String _visibility = 'friends';
  bool _hideWeights = false;
  bool _hideReps = false;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    final cap = widget.initialCaption?.trim();
    if (cap != null && cap.isNotEmpty) {
      _caption.text = cap;
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final x = await _picker.pickImage(
      source: source,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 75,
    );
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    setState(() => _photoBytes = bytes);
  }

  Future<void> _submit() async {
    final cap = _caption.text.trim();
    if (widget.workoutId == null &&
        cap.isEmpty &&
        (_photoBytes == null || _photoBytes!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a caption or a photo to post.'),
          backgroundColor: ZveltTokens.error,
        ),
      );
      return;
    }

    setState(() => _posting = true);
    try {
      await _feed.createPost(
        workoutId: widget.workoutId,
        caption: _caption.text,
        visibility: _visibility,
        hideWeights: _hideWeights,
        hideReps: _hideReps,
        photoBytes: _photoBytes,
      );
      if (!mounted) return;
      // Pop first, then set state (avoid timing issues)
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _posting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: ZveltTokens.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        title: Text(widget.workoutId != null ? 'Post workout' : 'New post'),
        actions: [
          if (widget.workoutId != null)
            TextButton(
              onPressed: _posting ? null : () => Navigator.of(context).pop(false),
              child: Text('Skip', style: TextStyle(color: ZveltTokens.text2)),
            )
          else
            TextButton(
              onPressed: _posting ? null : () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: ZveltTokens.text2)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(ZveltTokens.s4),
            decoration: BoxDecoration(
              color: ZveltTokens.surface,
              borderRadius: BorderRadius.circular(ZveltTokens.rLg),
              boxShadow: ZveltTokens.shadowCard,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(AppIcons.picture, color: ZveltTokens.brand, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Photo',
                      style: TextStyle(
                        color: ZveltTokens.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose from gallery or take a picture. You can post without a photo.',
                  style: TextStyle(color: ZveltTokens.text2, fontSize: 13, height: 1.35),
                ),
                const SizedBox(height: 16),
                if (_photoBytes != null) ...[
                  Stack(
                    alignment: Alignment.topRight,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _photoBytes!,
                          height: 220,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Material(
                        color: ZveltTokens.surface,
                        shape: const CircleBorder(),
                        child: IconButton(
                          onPressed: () => setState(() => _photoBytes = null),
                          icon: Icon(AppIcons.cross_small, color: ZveltTokens.text),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ZveltSecondaryButton(
                    label: 'Change photo',
                    icon: AppIcons.picture,
                    onTap: () => _pick(ImageSource.gallery),
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _pick(ImageSource.gallery),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        backgroundColor: ZveltTokens.brandGlow,
                        foregroundColor: ZveltTokens.brand,
                      ),
                      icon: const Icon(AppIcons.picture, size: 24),
                      label: const Text('Choose from gallery', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ZveltSecondaryButton(
                      label: 'Take photo',
                      icon: AppIcons.camera,
                      onTap: () => _pick(ImageSource.camera),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _caption,
            maxLines: 3,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: 'Caption',
              hintText: widget.workoutId != null ? 'How did it go?' : 'Say something…',
            ),
          ),
          const SizedBox(height: 8),
          Text('Who can see this', style: TextStyle(color: ZveltTokens.text2, fontSize: 12)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'private', label: Text('Private'), icon: Icon(AppIcons.lock, size: 18)),
              ButtonSegment(value: 'friends', label: Text('Friends'), icon: Icon(AppIcons.users, size: 18)),
              ButtonSegment(value: 'public', label: Text('Public'), icon: Icon(AppIcons.globe, size: 18)),
            ],
            selected: {_visibility},
            onSelectionChanged: (s) => setState(() => _visibility = s.first),
          ),
          if (widget.workoutId != null) ...[
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _hideWeights,
              onChanged: (v) => setState(() => _hideWeights = v ?? false),
              title: const Text('Hide weights in feed', style: TextStyle(fontSize: 13)),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: _hideReps,
              onChanged: (v) => setState(() => _hideReps = v ?? false),
              title: const Text('Hide reps in feed', style: TextStyle(fontSize: 13)),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _posting ? null : _submit,
            style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
            child: _posting
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: ZveltTokens.brand),
                  )
                : const Text('Post to feed'),
          ),
        ],
      ),
    );
  }
}
