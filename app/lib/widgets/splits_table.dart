import 'package:flutter/material.dart';
import '../models/workout_result.dart';
import '../theme/zvelt_tokens.dart';

class SplitsTable extends StatelessWidget {
  final List<SplitData> splits;

  const SplitsTable({super.key, required this.splits});

  /// Build a table straight from the backend `splits` payload returned by
  /// `POST /v1/activities` and `GET /v1/activities/:id`. The server computes the
  /// per-km splits from the (anti-cheat) route, so the client only has to map
  /// the JSON — see [parseSplits]. Returns an empty (collapsed) table when the
  /// payload is missing or holds no usable splits.
  factory SplitsTable.fromJson(dynamic splitsJson, {Key? key}) =>
      SplitsTable(key: key, splits: parseSplits(splitsJson));

  /// Convert the backend `splits` array into [SplitData] rows.
  ///
  /// Each backend split is `{ index, distanceM, timeS, paceSecsPerKm,
  /// elevGainM, partial }`. Numbers can arrive as `int` or `double` (and the
  /// app has been bitten by Prisma Decimals serialising as strings), so every
  /// field is coerced defensively via [_toDouble]. The 1-based `index` maps to
  /// the table's `km` column; malformed entries are skipped rather than crashing
  /// the summary screen.
  static List<SplitData> parseSplits(dynamic splitsJson) {
    if (splitsJson is! List) return const <SplitData>[];
    final out = <SplitData>[];
    for (final raw in splitsJson) {
      if (raw is! Map) continue;
      final timeS = _toDouble(raw['timeS']);
      out.add(SplitData(
        km: _toDouble(raw['index']).round(),
        time: Duration(milliseconds: (timeS * 1000).round()),
        paceSecsPerKm: _toDouble(raw['paceSecsPerKm']),
        elevGainM: _toDouble(raw['elevGainM']),
      ));
    }
    return out;
  }

  /// Coerce an `int` / `double` / numeric `String` / null JSON value into a
  /// double. Anything unparseable becomes 0 so a single bad field can't take
  /// down the whole table.
  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    if (splits.isEmpty) return const SizedBox.shrink();

    final fastestIdx = _fastestSplitIndex();

    return Container(
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s4, ZveltTokens.s4, 0),
            child: _header(),
          ),
          const SizedBox(height: ZveltTokens.s2),
          ...List.generate(splits.length, (i) => _row(i, i == fastestIdx)),
          const SizedBox(height: ZveltTokens.s1),
        ],
      ),
    );
  }

  int _fastestSplitIndex() {
    if (splits.isEmpty) return -1;
    var bestIdx = 0;
    for (var i = 1; i < splits.length; i++) {
      if (splits[i].paceSecsPerKm < splits[bestIdx].paceSecsPerKm) bestIdx = i;
    }
    return bestIdx;
  }

  Widget _header() {
    return Row(
      children: [
        _headerCell('KM', flex: 1, align: TextAlign.left),
        _headerCell('TIME', flex: 2, align: TextAlign.center),
        _headerCell('PACE', flex: 2, align: TextAlign.center),
        _headerCell('ELEV', flex: 2, align: TextAlign.right),
      ],
    );
  }

  Widget _headerCell(String text, {required int flex, required TextAlign align}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          color: ZveltTokens.text2,
          fontSize: 11,
          letterSpacing: 0.8,
          fontFamily: ZveltTokens.fontPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _row(int index, bool isFastest) {
    final split = splits[index];
    final bg = isFastest
        ? ZveltTokens.brand.withValues(alpha: 0.08)
        : (index.isOdd ? ZveltTokens.surface2.withValues(alpha: 0.4) : Colors.transparent);

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: Row(
              children: [
                Text(
                  '${split.km}',
                  style: TextStyle(
                    color: isFastest ? ZveltTokens.brand : ZveltTokens.text,
                    fontSize: 13,
                    fontWeight: isFastest ? FontWeight.w700 : FontWeight.w500,
                    fontFamily: ZveltTokens.fontMono,
                  ),
                ),
                if (isFastest) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: ZveltTokens.brand.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'BEST',
                      style: TextStyle(
                        color: ZveltTokens.brand,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFamily: ZveltTokens.fontPrimary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatDuration(split.time),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ZveltTokens.text,
                fontSize: 13,
                fontFamily: ZveltTokens.fontMono,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatPace(split.paceSecsPerKm),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isFastest ? ZveltTokens.brand : ZveltTokens.text,
                fontSize: 13,
                fontFamily: ZveltTokens.fontMono,
                fontWeight: isFastest ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              split.elevGainM > 0
                  ? '+${split.elevGainM.toStringAsFixed(0)} m'
                  : '${split.elevGainM.toStringAsFixed(0)} m',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: split.elevGainM > 0 ? ZveltTokens.warn : ZveltTokens.text2,
                fontSize: 13,
                fontFamily: ZveltTokens.fontMono,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _formatPace(double secsPerKm) {
    if (secsPerKm <= 0) return '--:--';
    final m = (secsPerKm ~/ 60);
    final s = (secsPerKm % 60).toInt();
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
