import 'dart:typed_data';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/workout_result.dart';
import '../theme/zvelt_tokens.dart';
import 'activity_share_card.dart';

class ShareBottomSheet extends StatefulWidget {
  final WorkoutResult result;
  final VoidCallback? onPostToFeed;

  const ShareBottomSheet({
    super.key,
    required this.result,
    this.onPostToFeed,
  });

  static Future<void> show(
    BuildContext context, {
    required WorkoutResult result,
    VoidCallback? onPostToFeed,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ShareBottomSheet(result: result, onPostToFeed: onPostToFeed),
    );
  }

  @override
  State<ShareBottomSheet> createState() => _ShareBottomSheetState();
}

class _ShareBottomSheetState extends State<ShareBottomSheet> {
  final _storyController = ScreenshotController();
  final _postController = ScreenshotController();

  String _selectedFormat = 'story';
  bool _isCapturing = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
        boxShadow: ZveltTokens.shadowFloat,
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: ZveltTokens.s3),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: ZveltTokens.borderStrong,
              borderRadius: BorderRadius.circular(ZveltTokens.rPill),
            ),
          ),
          const SizedBox(height: ZveltTokens.s5),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Share Activity',
                  style: ZType.h4.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: ZveltTokens.s4),
                _FormatSelector(
                  selected: _selectedFormat,
                  onChanged: (f) => setState(() => _selectedFormat = f),
                ),
                const SizedBox(height: ZveltTokens.s5),
                // Preview
                Center(
                  child: SizedBox(
                    height: 220,
                    child: AspectRatio(
                      aspectRatio: _selectedFormat == 'story' ? 9 / 16 : 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                        child: Screenshot(
                          controller: _selectedFormat == 'story' ? _storyController : _postController,
                          child: ActivityShareCard(
                            result: widget.result,
                            format: _selectedFormat,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: ZveltTokens.s5),
                _ActionGrid(
                  loading: _isCapturing,
                  onShare: _onShare,
                  onSave: _onSave,
                  onPost: widget.onPostToFeed != null ? _onPost : null,
                  onCopy: _onCopy,
                ),
              ],
            ),
          ),
          const SizedBox(height: ZveltTokens.s6),
        ],
      ),
    );
  }

  ScreenshotController get _activeController =>
      _selectedFormat == 'story' ? _storyController : _postController;

  Future<Uint8List?> _capture() async {
    setState(() => _isCapturing = true);
    try {
      return await _activeController.capture(pixelRatio: 3.0);
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<File?> _saveToTemp(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/zvelt_activity_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> _onShare() async {
    final bytes = await _capture();
    if (bytes == null) return;
    final file = await _saveToTemp(bytes);
    if (file == null) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: '${widget.result.activityType.label} — ${widget.result.distanceLabel} in ${widget.result.durationLabel} via ZVELT',
      ),
    );
  }

  Future<void> _onSave() async {
    final bytes = await _capture();
    if (bytes == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/zvelt_${widget.result.id}.png');
    await file.writeAsBytes(bytes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Image saved to Documents'),
          backgroundColor: ZveltTokens.surface2,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _onPost() {
    Navigator.pop(context);
    widget.onPostToFeed?.call();
  }

  Future<void> _onCopy() async {
    final text =
        '${widget.result.activityType.label}: ${widget.result.distanceLabel} · ${widget.result.durationLabel} · ${widget.result.paceLabel}';
    await SharePlus.instance.share(ShareParams(text: text));
  }
}

class _FormatSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _FormatSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _FormatChip(
          label: 'Story (9:16)',
          value: 'story',
          selected: selected,
          onTap: onChanged,
        ),
        const SizedBox(width: ZveltTokens.s2),
        _FormatChip(
          label: 'Square (1:1)',
          value: 'post',
          selected: selected,
          onTap: onChanged,
        ),
      ],
    );
  }
}

class _FormatChip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onTap;

  const _FormatChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  bool get _isSelected => value == selected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s2),
        decoration: BoxDecoration(
          color: _isSelected ? ZveltTokens.brand.withValues(alpha: 0.15) : ZveltTokens.surface2,
          borderRadius: BorderRadius.circular(ZveltTokens.rPill),
          border: Border.all(
            color: _isSelected ? ZveltTokens.brand.withValues(alpha: 0.5) : ZveltTokens.border,
          ),
        ),
        child: Text(
          label,
          style: ZType.bodyS.copyWith(
            color: _isSelected ? ZveltTokens.brand : ZveltTokens.text2,
            fontWeight: _isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  final bool loading;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback? onPost;
  final VoidCallback onCopy;

  const _ActionGrid({
    required this.loading,
    required this.onShare,
    required this.onSave,
    required this.onPost,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ActionButton(
          icon: AppIcons.share,
          label: 'Share',
          onTap: loading ? null : onShare,
          accent: ZveltTokens.brand,
          loading: loading,
        ),
        const SizedBox(width: ZveltTokens.s2 + 2),
        _ActionButton(
          icon: AppIcons.download,
          label: 'Save',
          onTap: loading ? null : onSave,
        ),
        const SizedBox(width: ZveltTokens.s2 + 2),
        _ActionButton(
          icon: AppIcons.apps,
          label: 'Post',
          onTap: onPost == null || loading ? null : onPost,
          disabled: onPost == null,
        ),
        const SizedBox(width: ZveltTokens.s2 + 2),
        _ActionButton(
          icon: AppIcons.link,
          label: 'Copy',
          onTap: loading ? null : onCopy,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? accent;
  final bool loading;
  final bool disabled;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.accent,
    this.loading = false,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = disabled ? ZveltTokens.text2.withValues(alpha: 0.3) : (accent ?? ZveltTokens.text2);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: accent != null && !disabled
                    ? accent!.withValues(alpha: 0.12)
                    : ZveltTokens.surface2,
                borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                border: Border.all(
                  color: accent != null && !disabled
                      ? accent!.withValues(alpha: 0.3)
                      : ZveltTokens.border,
                ),
              ),
              child: loading
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ZveltTokens.brand,
                        ),
                      ),
                    )
                  : Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: ZveltTokens.s1 + 2),
            Text(
              label,
              style: ZType.bodyS.copyWith(
                fontSize: 11,
                color: disabled ? ZveltTokens.text2.withValues(alpha: 0.3) : ZveltTokens.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
