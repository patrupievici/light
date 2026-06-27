import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/zvelt_tokens.dart';

/// Anti-cheat note prompt. When the server rejects a set whose weight is a >2×
/// jump vs the user's recent personal max (`WEIGHT_JUMP_REQUIRES_NOTE`), the
/// logging surfaces call this to collect a short justification and retry the
/// same set with `note:` attached.
///
/// Returns the trimmed note, or `null` if the user dismissed/cancelled (in which
/// case the caller must NOT log the set).
Future<String?> showWeightJumpNoteSheet(
  BuildContext context, {
  required String message,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WeightJumpNoteSheet(message: message),
  ).then((v) => (v != null && v.trim().isNotEmpty) ? v.trim() : null);
}

class _WeightJumpNoteSheet extends StatefulWidget {
  const _WeightJumpNoteSheet({this.message});

  final String? message;

  @override
  State<_WeightJumpNoteSheet> createState() => _WeightJumpNoteSheetState();
}

class _WeightJumpNoteSheetState extends State<_WeightJumpNoteSheet> {
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final message = widget.message ??
        'A weight far above your recent record needs a short note explaining it.';
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: ZveltTokens.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
          boxShadow: ZveltTokens.shadowFloat,
        ),
        padding: const EdgeInsets.fromLTRB(
            ZveltTokens.s5, ZveltTokens.s3, ZveltTokens.s5, ZveltTokens.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ZveltTokens.borderStrong,
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                ),
              ),
            ),
            const SizedBox(height: ZveltTokens.s5),
            Row(
              children: [
                const Icon(AppIcons.shield_check, color: ZveltTokens.warn, size: 22),
                const SizedBox(width: ZveltTokens.s3),
                Expanded(
                  child: Text('Confirm weight jump',
                      style: ZType.h4.copyWith(color: ZveltTokens.text)),
                ),
              ],
            ),
            const SizedBox(height: ZveltTokens.s3),
            Text(message,
                style: ZType.bodyM.copyWith(color: ZveltTokens.text3)),
            const SizedBox(height: ZveltTokens.s4),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.done,
              style: ZType.bodyM.copyWith(color: ZveltTokens.text),
              decoration: InputDecoration(
                labelText: 'Note',
                hintText: 'E.g. new personal record, switched to a 20kg bar…',
                hintStyle: ZType.bodyM.copyWith(color: ZveltTokens.text4),
                filled: true,
                fillColor: ZveltTokens.surface2,
                counterText: '',
                contentPadding: const EdgeInsets.all(ZveltTokens.s4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                  borderSide: BorderSide(color: ZveltTokens.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                  borderSide: BorderSide(color: ZveltTokens.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                  borderSide: const BorderSide(color: ZveltTokens.brand, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: ZveltTokens.s4),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                      ),
                    ),
                    child: Text('Cancel',
                        style: ZType.bodyM.copyWith(color: ZveltTokens.text2)),
                  ),
                ),
                const SizedBox(width: ZveltTokens.s3),
                Expanded(
                  child: FilledButton(
                    onPressed: _hasText
                        ? () => Navigator.of(context).pop(_controller.text.trim())
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: ZveltTokens.brand,
                      foregroundColor: ZveltTokens.onBrand,
                      disabledBackgroundColor: ZveltTokens.surface2,
                      padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                      ),
                    ),
                    child: const Text('Save set'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
