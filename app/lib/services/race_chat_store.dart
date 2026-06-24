import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Mesaj local pentru hub-ul de trash talk (per cursă / cameră).
class RaceChatMessage {
  const RaceChatMessage({
    this.isSystem = false,
    this.isMe = false,
    this.who,
    this.hue = 0,
    this.time,
    required this.text,
  });

  final bool isSystem;
  final bool isMe;
  final String? who;
  final int hue;
  final String? time;
  final String text;

  Map<String, dynamic> toJson() => {
        'isSystem': isSystem,
        'isMe': isMe,
        if (who != null) 'who': who,
        'hue': hue,
        if (time != null) 'time': time,
        'text': text,
      };

  static RaceChatMessage? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final text = (m['text'] as String?)?.trim();
    if (text == null || text.isEmpty) return null;
    return RaceChatMessage(
      isSystem: m['isSystem'] == true,
      isMe: m['isMe'] == true,
      who: (m['who'] as String?)?.trim(),
      hue: (m['hue'] as num?)?.toInt() ?? 0,
      time: (m['time'] as String?)?.trim(),
      text: text,
    );
  }
}

class RaceChatStore {
  static const _prefix = 'zvelt_race_chat_v1';

  static List<RaceChatMessage> seedFor(String raceId, String raceTitle) {
    if (raceId == 'global') {
      return [
        const RaceChatMessage(isSystem: true, text: 'Alex_Fit joined the race'),
        const RaceChatMessage(
          who: 'Marco.K',
          hue: 20,
          time: '09:42 AM',
          text:
              'Cineva chiar crede că mă poate întrece la pull-ups săptămâna asta? 😏 Am făcut deja 40 azi dimineată.',
        ),
        const RaceChatMessage(
          isMe: true,
          time: '09:45 AM',
          text: '40? Ăla e doar încălzirea mea, Marco. Verifică leaderboard-ul în 10 minute. 🚀',
        ),
        const RaceChatMessage(
          who: 'Elena_S',
          hue: 280,
          time: '09:48 AM',
          text: '🍿 Abia aștept să văd cine "plânge" duminică la final. Spor la treabă băieți!',
        ),
        const RaceChatMessage(isSystem: true, text: '🔥 The heat is on!'),
      ];
    }
    return [
      RaceChatMessage(isSystem: true, text: 'Welcome to $raceTitle'),
      const RaceChatMessage(isSystem: true, text: 'Trash talk starts now — keep it fun.'),
    ];
  }

  Future<List<RaceChatMessage>> load(String raceId, {required String raceTitle}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix/$raceId');
    if (raw == null || raw.isEmpty) {
      return seedFor(raceId, raceTitle);
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final parsed = list.map(RaceChatMessage.fromJson).whereType<RaceChatMessage>().toList();
      if (parsed.isEmpty) return seedFor(raceId, raceTitle);
      return parsed;
    } catch (_) {
      return seedFor(raceId, raceTitle);
    }
  }

  Future<void> save(String raceId, List<RaceChatMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_prefix/$raceId',
      jsonEncode(messages.map((m) => m.toJson()).toList()),
    );
  }

  Future<void> append(String raceId, String raceTitle, RaceChatMessage message) async {
    final list = await load(raceId, raceTitle: raceTitle);
    list.add(message);
    await save(raceId, list);
  }
}
