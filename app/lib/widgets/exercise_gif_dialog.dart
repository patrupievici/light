import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../services/exercise_db_service.dart';
import '../theme/zvelt_tokens.dart';
import 'zvelt_network_image.dart';

/// Modal dialog showing an ExerciseDB reference GIF + instructions for a
/// given exercise name.
///
/// Usage:
/// ```dart
/// ExerciseGifDialog.show(context, exerciseName: exercise.name);
/// ```
class ExerciseGifDialog extends StatefulWidget {
  const ExerciseGifDialog({
    super.key,
    required this.exerciseName,
    this.service,
  });

  final String exerciseName;
  final ExerciseDbService? service;

  static Future<void> show(
    BuildContext context, {
    required String exerciseName,
    ExerciseDbService? service,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => ExerciseGifDialog(
        exerciseName: exerciseName,
        service: service,
      ),
    );
  }

  @override
  State<ExerciseGifDialog> createState() => _ExerciseGifDialogState();
}

class _ExerciseGifDialogState extends State<ExerciseGifDialog> {
  late final ExerciseDbService _svc = widget.service ?? ExerciseDbService();
  late Future<List<ExerciseDbItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _svc.searchByName(widget.exerciseName);
  }

  void _retry() {
    setState(() {
      _future = _svc.searchByName(widget.exerciseName);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s5, vertical: ZveltTokens.s10),
      backgroundColor: ZveltTokens.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZveltTokens.rXl),
        side: BorderSide(color: ZveltTokens.border, width: 1),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: FutureBuilder<List<ExerciseDbItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return _DialogShell(
                title: widget.exerciseName,
                onClose: () => Navigator.of(context).pop(),
                child: const _LoadingBody(),
              );
            }
            if (snap.hasError) {
              return _DialogShell(
                title: widget.exerciseName,
                onClose: () => Navigator.of(context).pop(),
                child: _ErrorBody(error: snap.error!, onRetry: _retry),
              );
            }
            final list = snap.data ?? const [];
            if (list.isEmpty) {
              return _DialogShell(
                title: widget.exerciseName,
                onClose: () => Navigator.of(context).pop(),
                child: const _EmptyBody(),
              );
            }
            return _LoadedBody(
              item: list.first,
              onClose: () => Navigator.of(context).pop(),
            );
          },
        ),
      ),
    );
  }
}

// ─── Shell ──────────────────────────────────────────────────────────────────

class _DialogShell extends StatelessWidget {
  const _DialogShell({
    required this.title,
    required this.onClose,
    required this.child,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DialogHeader(title: title, onClose: onClose),
        Flexible(child: child),
      ],
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.title, required this.onClose});
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, ZveltTokens.s4, ZveltTokens.s3, ZveltTokens.s2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'REFERENCE',
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                    letterSpacing: 1.2,
                    color: ZveltTokens.text2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ZType.h4.copyWith(height: 1.2),
                ),
              ],
            ),
          ),
          _CloseIconButton(onTap: onClose),
        ],
      ),
    );
  }
}

class _CloseIconButton extends StatelessWidget {
  const _CloseIconButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: ZveltTokens.bg2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: ZveltTokens.border, width: 1),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Icon(
            AppIcons.cross_small,
            size: 20,
            color: ZveltTokens.text2,
          ),
        ),
      ),
    );
  }
}

// ─── States ─────────────────────────────────────────────────────────────────

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s5, vertical: ZveltTokens.s10),
      child: Column(
        children: [
          const SizedBox(
            height: 220,
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: ZveltTokens.brand,
                ),
              ),
            ),
          ),
          const SizedBox(height: ZveltTokens.s3),
          Text(
            'Loading reference…',
            style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
          ),
          const SizedBox(height: ZveltTokens.s6),
        ],
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, ZveltTokens.s3, ZveltTokens.s5, ZveltTokens.s6),
      child: Column(
        children: [
          Icon(AppIcons.search, size: 40, color: ZveltTokens.text2),
          const SizedBox(height: ZveltTokens.s3),
          Text(
            'No reference found',
            style: ZType.clean.copyWith(fontSize: 15),
          ),
          const SizedBox(height: ZveltTokens.s1),
          Text(
            'We could not find a matching exercise in the reference library. '
            'Try a simpler name.',
            textAlign: TextAlign.center,
            style: ZType.bodyS.copyWith(color: ZveltTokens.text2, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final msg = error is ExerciseDbException
        ? (error as ExerciseDbException).message
        : 'Could not load reference.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, ZveltTokens.s3, ZveltTokens.s5, ZveltTokens.s6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.cloud_disabled, size: 40, color: ZveltTokens.text2),
          const SizedBox(height: ZveltTokens.s3),
          Text(
            'Something went wrong',
            style: ZType.clean.copyWith(fontSize: 15),
          ),
          const SizedBox(height: ZveltTokens.s1),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: ZType.bodyS.copyWith(color: ZveltTokens.text2, height: 1.5),
          ),
          const SizedBox(height: ZveltTokens.s4),
          TextButton.icon(
            onPressed: onRetry,
            icon: Icon(AppIcons.refresh, size: 18, color: ZveltTokens.text),
            label: Text(
              'Try again',
              style: ZType.bodyS.copyWith(
                color: ZveltTokens.text,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Loaded ─────────────────────────────────────────────────────────────────

class _LoadedBody extends StatelessWidget {
  const _LoadedBody({required this.item, required this.onClose});
  final ExerciseDbItem item;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DialogHeader(
          title: item.name.trim().isEmpty ? 'Reference' : _capitalize(item.name),
          onClose: onClose,
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, ZveltTokens.s1, ZveltTokens.s5, ZveltTokens.s5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _GifBanner(url: item.gifUrl),
                const SizedBox(height: ZveltTokens.s4),
                _MetaChips(item: item),
                if (item.instructions.isNotEmpty) ...[
                  const SizedBox(height: ZveltTokens.s5),
                  const _SectionLabel('INSTRUCTIONS'),
                  const SizedBox(height: ZveltTokens.s2),
                  _InstructionsList(steps: item.instructions),
                ],
                if (item.secondaryMuscles.isNotEmpty) ...[
                  const SizedBox(height: ZveltTokens.s5),
                  const _SectionLabel('SECONDARY MUSCLES'),
                  const SizedBox(height: ZveltTokens.s2),
                  Wrap(
                    spacing: ZveltTokens.s2,
                    runSpacing: ZveltTokens.s2,
                    children: [
                      for (final m in item.secondaryMuscles)
                        _Chip(label: _capitalize(m)),
                    ],
                  ),
                ],
                const SizedBox(height: ZveltTokens.s4),
                Text(
                  'Source: ExerciseDB',
                  style: ZType.monoXS.copyWith(color: ZveltTokens.text3),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GifBanner extends StatelessWidget {
  const _GifBanner({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return _bannerBox(
        Center(
          child: Icon(AppIcons.picture,
              color: ZveltTokens.text2, size: 40),
        ),
      );
    }
    return _bannerBox(
      ZveltNetworkImage(
        url: url,
        fit: BoxFit.contain,
        cacheWidth: ZveltImageCacheWidth.feedFull,
        placeholder: (_) => const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: ZveltTokens.brand,
            ),
          ),
        ),
        errorWidget: (_) => Center(
          child: Icon(AppIcons.picture,
              color: ZveltTokens.text2, size: 40),
        ),
      ),
    );
  }

  Widget _bannerBox(Widget child) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        child: Container(
          decoration: BoxDecoration(
            color: ZveltTokens.bg2,
            border: Border.all(color: ZveltTokens.border, width: 1),
            borderRadius: BorderRadius.circular(ZveltTokens.rLg),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _MetaChips extends StatelessWidget {
  const _MetaChips({required this.item});
  final ExerciseDbItem item;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (item.target.isNotEmpty) {
      chips.add(_Chip(label: _capitalize(item.target), emphasis: true));
    }
    if (item.bodyPart.isNotEmpty) {
      chips.add(_Chip(label: _capitalize(item.bodyPart)));
    }
    if (item.equipment.isNotEmpty) {
      chips.add(_Chip(label: _capitalize(item.equipment)));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.emphasis = false});
  final String label;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: emphasis ? ZveltTokens.brandTint : ZveltTokens.bg2,
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        border: Border.all(
          color: emphasis
              ? ZveltTokens.brand.withValues(alpha: 0.4)
              : ZveltTokens.border,
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: ZveltTokens.fontPrimary,
          fontWeight: FontWeight.w500,
          fontSize: 11,
          letterSpacing: 0.2,
          color: emphasis ? ZveltTokens.brand : ZveltTokens.text,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: ZveltTokens.fontPrimary,
        fontWeight: FontWeight.w500,
        fontSize: 11,
        letterSpacing: 1.2,
        color: ZveltTokens.text2,
      ),
    );
  }
}

class _InstructionsList extends StatelessWidget {
  const _InstructionsList({required this.steps});
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : ZveltTokens.s3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${i + 1}.',
                    style: ZType.bodyS.copyWith(
                      color: ZveltTokens.text2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    steps[i],
                    style: ZType.bodyS.copyWith(
                      color: ZveltTokens.text,
                      height: 1.55,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String _capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}
