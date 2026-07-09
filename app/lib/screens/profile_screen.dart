import 'dart:convert';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart' show v1Base;
import '../services/auth_service.dart';
import '../services/http_client.dart';
import '../theme/zvelt_tokens.dart';
import '../widgets/z/z_card.dart';
import '../widgets/z/z_loading.dart';
import '../widgets/zvelt_error_state.dart';

/// Physical Data screen — edit bodyweight, height, sex, birth year.
/// All fields are persisted to the backend via PATCH /v1/me/profile.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = AuthService();

  static const double _weightMin = 30;
  static const double _weightMax = 250;
  static const double _heightMin = 100;
  static const double _heightMax = 250;

  double _weightKg = 75;
  double _heightCm = 175;
  String _sex = 'male';
  int? _birthYear;
  String _unitSystem = 'metric';
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    // On ANY load failure we show an error+Retry state instead of the editor.
    // Rendering the hardcoded defaults (75 kg / 175 cm / male) as if they
    // were the user's saved values let a single tap on Save overwrite the
    // real bodyweight — the input to every strength ranking.
    try {
      final token = await _auth.getAccessToken();
      if (token == null) {
        // Early return here used to skip the `_loading = false` below —
        // infinite spinner with no way out.
        if (mounted) {
          setState(() {
            _loadError = 'Please sign in again to edit your physical data.';
            _loading = false;
          });
        }
        return;
      }
      final res = await http.get(Uri.parse('$v1Base/me'),
          headers: {'Authorization': 'Bearer $token'}).withTimeout();
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final profile = data['profile'] as Map<String, dynamic>?;
        if (profile != null) {
          setState(() {
            _unitSystem = profile['unitSystem'] as String? ?? 'metric';
            final bw = profile['bodyweightKg'] ?? profile['bodweightKg'];
            if (bw != null) {
              final v =
                  bw is num ? bw.toDouble() : double.tryParse(bw.toString());
              if (v != null) _weightKg = v.clamp(_weightMin, _weightMax);
            }
            final h = profile['heightCm'];
            if (h != null) {
              final v = h is num ? h.toDouble() : double.tryParse(h.toString());
              if (v != null) _heightCm = v.clamp(_heightMin, _heightMax);
            }
            _sex = profile['sex'] as String? ?? 'male';
            _birthYear = profile['birthYear'] as int?;
          });
        }
      } else if (mounted && res.statusCode != 200) {
        setState(
            () => _loadError = 'Could not load your data (${res.statusCode}).');
      }
    } catch (e) {
      debugPrint('Physical data load error: $e');
      if (mounted) {
        _loadError = 'Could not load your data. Check your connection.';
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final token = await _auth.getAccessToken();
      if (token == null) throw Exception('Not signed in');
      final body = <String, dynamic>{
        'bodyweightKg': _weightKg,
        'heightCm': _heightCm,
        'sex': _sex,
        if (_birthYear != null) 'birthYear': _birthYear,
      };
      final res = await http
          .patch(
            Uri.parse('$v1Base/me/profile'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .withTimeout();
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Physical data saved'),
            backgroundColor: ZveltTokens.success,
          ),
        );
        Navigator.of(context).pop();
      } else {
        final data = jsonDecode(res.body) as Map<String, dynamic>?;
        throw Exception(data?['message'] ?? 'Save failed (${res.statusCode})');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: ZveltTokens.error,
          ),
        );
        setState(() => _saving = false);
      }
    }
  }

  String get _weightDisplay {
    if (_unitSystem == 'imperial') {
      return '${(_weightKg * 2.20462).round()} lbs';
    }
    return '${_weightKg.round()} kg';
  }

  String get _heightDisplay {
    if (_unitSystem == 'imperial') {
      final totalInches = (_heightCm / 2.54).round();
      final feet = totalInches ~/ 12;
      final inches = totalInches % 12;
      return "$feet' $inches\"";
    }
    return '${_heightCm.round()} cm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(title: const Text('Physical data')),
      body: _loading
          ? const ZPageSkeleton(showHeader: false, itemCount: 4)
          : _loadError != null
              ? ZveltErrorState(
                  tier: ZveltErrorTier.network,
                  title: 'Could not load physical data',
                  message: _loadError,
                  onRetry: _load,
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(ZveltTokens.s4,
                      ZveltTokens.s2, ZveltTokens.s4, ZveltTokens.s10),
                  children: [
                    _SliderCard(
                      label: 'Body weight',
                      value: _weightDisplay,
                      icon: AppIcons.balance_scale_left,
                      sliderValue: _weightKg,
                      min: _weightMin,
                      max: _weightMax,
                      divisions: (_weightMax - _weightMin).round(),
                      onChanged: (v) => setState(() => _weightKg = v),
                    ),
                    const SizedBox(height: ZveltTokens.s3),
                    _SliderCard(
                      label: 'Height',
                      value: _heightDisplay,
                      icon: AppIcons.ruler_horizontal,
                      sliderValue: _heightCm,
                      min: _heightMin,
                      max: _heightMax,
                      divisions: (_heightMax - _heightMin).round(),
                      onChanged: (v) => setState(() => _heightCm = v),
                    ),
                    const SizedBox(height: ZveltTokens.s3),
                    _SegmentCard(
                      label: 'Biological sex',
                      icon: AppIcons.user,
                      options: const [
                        _Opt('male', 'Male'),
                        _Opt('female', 'Female'),
                        _Opt('other', 'Other'),
                      ],
                      selected: _sex,
                      onChanged: (v) => setState(() => _sex = v),
                    ),
                    const SizedBox(height: ZveltTokens.s3),
                    _BirthYearCard(
                      birthYear: _birthYear,
                      onChanged: (v) => setState(() => _birthYear = v),
                    ),
                    const SizedBox(height: ZveltTokens.s8),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: ZveltTokens.onBrand, strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                    const SizedBox(height: ZveltTokens.s3),
                    Text(
                      'Body weight is required for strength rankings. Height and sex improve accuracy.',
                      style: ZType.bodyS.copyWith(
                        color: ZveltTokens.text2,
                        fontSize: 12,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SliderCard extends StatelessWidget {
  const _SliderCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.sliderValue,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String value;
  final IconData icon;
  final double sliderValue;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return ZCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(ZveltTokens.s2),
                decoration: BoxDecoration(
                  color: ZveltTokens.brandTint,
                  borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                ),
                child: Icon(icon, color: ZveltTokens.brand, size: 14),
              ),
              const SizedBox(width: 10),
              Text(label,
                  style: ZType.bodyM
                      .copyWith(color: ZveltTokens.text2, fontSize: 13)),
              const Spacer(),
              Text(
                value,
                style: ZType.stat.copyWith(
                  color: ZveltTokens.text,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: ZveltTokens.brand,
              inactiveTrackColor: ZveltTokens.surface2,
              thumbColor: ZveltTokens.brand,
              overlayColor: ZveltTokens.brand.withValues(alpha: 0.12),
              valueIndicatorColor: ZveltTokens.text,
            ),
            child: Slider(
              value: sliderValue,
              min: min,
              max: max,
              divisions: divisions,
              label: value,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Opt {
  const _Opt(this.value, this.label);
  final String value;
  final String label;
}

class _SegmentCard extends StatelessWidget {
  const _SegmentCard({
    required this.label,
    required this.icon,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final List<_Opt> options;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ZCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(ZveltTokens.s2),
                decoration: BoxDecoration(
                  color: ZveltTokens.brandTint,
                  borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                ),
                child: Icon(icon, color: ZveltTokens.brand, size: 14),
              ),
              const SizedBox(width: 10),
              Text(label,
                  style: ZType.bodyM
                      .copyWith(color: ZveltTokens.text2, fontSize: 13)),
            ],
          ),
          const SizedBox(height: ZveltTokens.s3),
          Row(
            children: [
              for (int i = 0; i < options.length; i++) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(options[i].value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: options[i].value == selected
                            ? ZveltTokens.brand
                            : ZveltTokens.surface2,
                        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        options[i].label,
                        style: ZType.bodyS.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          color: options[i].value == selected
                              ? ZveltTokens.onBrand
                              : ZveltTokens.text2,
                        ),
                      ),
                    ),
                  ),
                ),
                if (i < options.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _BirthYearCard extends StatelessWidget {
  const _BirthYearCard({required this.birthYear, required this.onChanged});
  final int? birthYear;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return ZCard(
      onTap: () => _pick(context),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(ZveltTokens.s2),
            decoration: BoxDecoration(
              color: ZveltTokens.brandTint,
              borderRadius: BorderRadius.circular(ZveltTokens.rSm),
            ),
            child: const Icon(AppIcons.cake_birthday,
                color: ZveltTokens.brand, size: 14),
          ),
          const SizedBox(width: 10),
          Text('Birth year',
              style:
                  ZType.bodyM.copyWith(color: ZveltTokens.text2, fontSize: 13)),
          const Spacer(),
          Text(
            birthYear != null ? '$birthYear' : 'Optional',
            style: ZType.num_.copyWith(
              color: birthYear != null ? ZveltTokens.text : ZveltTokens.text3,
              fontSize: 15,
              fontWeight: birthYear != null ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Icon(AppIcons.angle_small_right, color: ZveltTokens.text3, size: 18),
        ],
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now().year;
    final years = List.generate(now - 1919, (i) => now - 14 - i);
    final initIndex =
        birthYear != null ? years.indexOf(birthYear!) : years.indexOf(now - 25);
    final ctrl = FixedExtentScrollController(
        initialItem: initIndex.clamp(0, years.length - 1));
    int? picked = birthYear;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: ZveltTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
      ),
      builder: (ctx) => SizedBox(
        height: 300,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ZveltTokens.border,
                borderRadius: BorderRadius.circular(ZveltTokens.rPill),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
              child: Row(
                children: [
                  Text(
                    'Birth year',
                    style: ZType.h3
                        .copyWith(color: ZveltTokens.text, fontSize: 15),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      onChanged(null);
                      Navigator.pop(ctx);
                    },
                    child: Text('Clear',
                        style: TextStyle(
                            color: ZveltTokens.text2,
                            fontWeight: FontWeight.w600)),
                  ),
                  TextButton(
                    onPressed: () {
                      onChanged(picked);
                      Navigator.pop(ctx);
                    },
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        color: ZveltTokens.brand,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListWheelScrollView.useDelegate(
                controller: ctrl,
                itemExtent: 48,
                perspective: 0.003,
                onSelectedItemChanged: (i) => picked = years[i],
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: years.length,
                  builder: (ctx, i) => Center(
                    child: Text(
                      '${years[i]}',
                      style: ZType.stat.copyWith(fontSize: 20),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
  }
}
