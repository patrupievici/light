/// Provocare socială — client sincronizat cu `GET/POST /v1/challenges`.
enum SocialChallengeKind {
  pullUps,
  deadlift,
  squat,
  benchPress,
  custom,
}

extension SocialChallengeKindX on SocialChallengeKind {
  String get defaultTitle {
    switch (this) {
      case SocialChallengeKind.pullUps:
        return 'Pull-up challenge';
      case SocialChallengeKind.deadlift:
        return 'Deadlift challenge';
      case SocialChallengeKind.squat:
        return 'Squat challenge';
      case SocialChallengeKind.benchPress:
        return 'Bench press challenge';
      case SocialChallengeKind.custom:
        return 'Custom challenge';
    }
  }
}

SocialChallengeKind? parseSocialChallengeKind(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  for (final e in SocialChallengeKind.values) {
    if (e.name == raw) return e;
  }
  return null;
}

class SocialChallenge {
  SocialChallenge({
    required this.id,
    required this.kind,
    required this.customTitle,
    required this.visibility,
    this.targetHint,
    required this.durationDays,
    required this.createdAt,
    required this.endsAt,
    this.serverTitle,
    this.creatorDisplayName,
    this.isMine = true,
    this.participantsCount = 0,
    this.joined = false,
  });

  final String id;
  final SocialChallengeKind kind;
  /// Folosit când [kind] == [SocialChallengeKind.custom] sau trimis la API.
  final String customTitle;
  /// `friends` sau `public`.
  final String visibility;
  final String? targetHint;
  final int durationDays;
  final DateTime createdAt;
  final DateTime endsAt;
  /// Titlu rezolvat pe server (opțional).
  final String? serverTitle;
  final String? creatorDisplayName;
  final bool isMine;
  /// Real participant count from the server (was hardcoded "+2K" before).
  final int participantsCount;
  /// True when the viewer is in the participant set — drives Join/Leave label.
  final bool joined;

  SocialChallenge copyWith({int? participantsCount, bool? joined}) => SocialChallenge(
        id: id,
        kind: kind,
        customTitle: customTitle,
        visibility: visibility,
        targetHint: targetHint,
        durationDays: durationDays,
        createdAt: createdAt,
        endsAt: endsAt,
        serverTitle: serverTitle,
        creatorDisplayName: creatorDisplayName,
        isMine: isMine,
        participantsCount: participantsCount ?? this.participantsCount,
        joined: joined ?? this.joined,
      );

  String get title {
    final s = serverTitle?.trim();
    if (s != null && s.isNotEmpty) return s;
    if (kind == SocialChallengeKind.custom && customTitle.trim().isNotEmpty) return customTitle.trim();
    return kind.defaultTitle;
  }

  bool get isExpired => DateTime.now().isAfter(endsAt);

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'customTitle': customTitle,
        'visibility': visibility,
        if (targetHint != null && targetHint!.isNotEmpty) 'targetHint': targetHint,
        'durationDays': durationDays,
        'createdAt': createdAt.toIso8601String(),
        'endsAt': endsAt.toIso8601String(),
        if (serverTitle != null && serverTitle!.isNotEmpty) 'title': serverTitle,
        if (creatorDisplayName != null && creatorDisplayName!.isNotEmpty) 'creatorDisplayName': creatorDisplayName,
        'isMine': isMine,
        'participantsCount': participantsCount,
        'joined': joined,
      };

  static SocialChallenge? fromJson(dynamic o) {
    if (o is! Map) return null;
    final m = Map<String, dynamic>.from(o);
    final id = (m['id'] as String?)?.trim();
    final kind = parseSocialChallengeKind(m['kind'] as String?);
    if (id == null || id.isEmpty || kind == null) return null;
    final vis = (m['visibility'] as String?)?.trim().toLowerCase();
    if (vis != 'friends' && vis != 'public') return null;
    final visibility = vis!;
    final createdRaw = m['createdAt'] as String?;
    final created = createdRaw != null ? DateTime.tryParse(createdRaw) : null;
    if (created == null) return null;
    final days = (m['durationDays'] as num?)?.toInt() ?? 7;
    final endsRaw = m['endsAt'] as String?;
    final endsParsed = endsRaw != null ? DateTime.tryParse(endsRaw) : null;
    final endsAt = endsParsed ?? created.add(Duration(days: days.clamp(1, 365)));
    final serverTitle = (m['title'] as String?)?.trim();
    final creatorDisplayName = (m['creatorDisplayName'] as String?)?.trim();
    final isMine = m['isMine'] != false;

    return SocialChallenge(
      id: id,
      kind: kind,
      customTitle: (m['customTitle'] as String?)?.trim() ?? '',
      visibility: visibility,
      targetHint: (m['targetHint'] as String?)?.trim(),
      durationDays: days.clamp(1, 365),
      createdAt: created,
      endsAt: endsAt,
      serverTitle: (serverTitle == null || serverTitle.isEmpty) ? null : serverTitle,
      creatorDisplayName: (creatorDisplayName == null || creatorDisplayName.isEmpty) ? null : creatorDisplayName,
      isMine: isMine,
      participantsCount: (m['participantsCount'] as num?)?.toInt() ?? 0,
      joined: m['joined'] as bool? ?? false,
    );
  }
}
