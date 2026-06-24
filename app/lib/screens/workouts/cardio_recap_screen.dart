import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../../services/activity_service.dart';
import '../../theme/zvelt_tokens.dart';

/// Summary after outdoor cardio — save, discard, or share.
class CardioRecapScreen extends StatelessWidget {
  const CardioRecapScreen({
    super.key,
    required this.mode,
    required this.elapsedSeconds,
    required this.meters,
    required this.onSave,
    required this.onDiscard,
    this.onShare,
  });

  final String mode;
  final int elapsedSeconds;
  final double meters;
  final Future<CardioCompleteResult?> Function() onSave;
  final VoidCallback onDiscard;
  final VoidCallback? onShare;

  String get _distanceLabel {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  String get _timeLabel {
    final m = elapsedSeconds ~/ 60;
    final s = elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get _paceLabel {
    if (meters < 50 || elapsedSeconds < 10) return '—';
    final minPerKm = (elapsedSeconds / 60) / (meters / 1000);
    final min = minPerKm.floor();
    final sec = ((minPerKm - min) * 60).round().clamp(0, 59);
    return "$min'${sec.toString().padLeft(2, '0')}\" /km";
  }

  @override
  Widget build(BuildContext context) {
    final title = mode == 'bike' ? 'Ride complete' : 'Run complete';
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(ZveltTokens.s6, ZveltTokens.s4, ZveltTokens.s6, ZveltTokens.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: onDiscard,
                    icon: Icon(AppIcons.cross_small, color: ZveltTokens.text2),
                  ),
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: ZveltTokens.fontPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: ZveltTokens.s12),
                ],
              ),
              const SizedBox(height: ZveltTokens.s6),
              _StatTile(label: 'Distance', value: _distanceLabel, large: true),
              const SizedBox(height: ZveltTokens.s3),
              Row(
                children: [
                  Expanded(child: _StatTile(label: 'Time', value: _timeLabel)),
                  const SizedBox(width: ZveltTokens.s3),
                  Expanded(child: _StatTile(label: 'Pace', value: _paceLabel)),
                ],
              ),
              const Spacer(),
              if (onShare != null) ...[
                OutlinedButton.icon(
                  onPressed: onShare,
                  icon: const Icon(AppIcons.share),
                  label: const Text('Share to feed'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ZveltTokens.text,
                    side: BorderSide(color: ZveltTokens.border),
                    padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s4),
                  ),
                ),
                const SizedBox(height: ZveltTokens.s3),
              ],
              FilledButton(
                onPressed: () async {
                  final result = await onSave();
                  if (context.mounted) Navigator.of(context).pop(result);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: ZveltTokens.brand,
                  padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s4),
                ),
                child: const Text('Save session', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: ZveltTokens.s2),
              TextButton(
                onPressed: onDiscard,
                child: Text('Discard', style: TextStyle(color: ZveltTokens.text2)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.large = false});

  final String label;
  final String value;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s5),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: ZveltTokens.text2, letterSpacing: 1.4)),
          const SizedBox(height: ZveltTokens.s2),
          Text(
            value,
            style: ZType.num_.copyWith(
              fontSize: large ? 36 : 24,
              color: ZveltTokens.text,
            ),
          ),
        ],
      ),
    );
  }
}
