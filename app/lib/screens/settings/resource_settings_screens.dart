import 'dart:math';
import 'package:zvelt_app/theme/app_icons.dart';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/settings_store.dart';
import '../../theme/zvelt_tokens.dart';
import 'settings_kit.dart';

class WhatsNewScreen extends StatelessWidget {
  const WhatsNewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const releases = [
      (
        version: '2.4',
        latest: true,
        changes: [
          'A completely rebuilt Settings experience',
          'Health Connect recent-history import',
          'Samsung Health and Galaxy Watch support',
          'Cloud wearable connection foundation',
        ],
      ),
      (
        version: '2.3',
        latest: false,
        changes: [
          'Faster home loading',
          'Offline workout sync',
          'Smarter recovery insights'
        ],
      ),
      (
        version: '2.2',
        latest: false,
        changes: [
          'Progress photos',
          'Race chat improvements',
          'Expanded nutrition planning'
        ],
      ),
    ];
    return SettingsModalShell(
      title: "What's new",
      eyebrow: 'RESOURCES',
      children: [
        for (final release in releases) ...[
          SettingsCard(
            divided: false,
            children: [
              Padding(
                padding: const EdgeInsets.all(ZveltTokens.s4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Zvelt v${release.version}', style: ZType.h4),
                        if (release.latest) ...[
                          const SizedBox(width: ZveltTokens.s2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: ZveltTokens.brand,
                                borderRadius: BorderRadius.circular(99)),
                            child: const Text('LATEST',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: ZveltTokens.s3),
                    for (final change in release.changes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 7),
                              child: Icon(AppIcons.circle,
                                  color: ZveltTokens.brand, size: 6),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(change,
                                    style: ZType.bodyM
                                        .copyWith(color: ZveltTokens.text2))),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: ZveltTokens.cardGap),
        ],
      ],
    );
  }
}

class GettingStartedScreen extends StatefulWidget {
  const GettingStartedScreen({super.key});

  @override
  State<GettingStartedScreen> createState() => _GettingStartedScreenState();
}

class _GettingStartedScreenState extends State<GettingStartedScreen> {
  static const _steps = [
    (
      key: SettingsKeys.gsProfile,
      title: 'Complete your profile',
      sub: 'Add a name, username and photo'
    ),
    (
      key: SettingsKeys.gsData,
      title: 'Add physical data',
      sub: 'Weight, height, age and sex'
    ),
    (
      key: SettingsKeys.gsDevice,
      title: 'Connect a health source',
      sub: 'Health Connect, Apple Health or a wearable'
    ),
    (
      key: SettingsKeys.gsWorkout,
      title: 'Log your first workout',
      sub: 'Build the baseline for your recommendations'
    ),
    (
      key: SettingsKeys.gsFriends,
      title: 'Find your people',
      sub: 'Follow friends and start a challenge'
    ),
  ];

  final Map<String, bool> _done = {for (final item in _steps) item.key: false};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      for (final item in _steps) {
        _done[item.key] = prefs.getBool(item.key) ?? false;
      }
    });
  }

  Future<void> _toggle(String key) async {
    final next = !(_done[key] ?? false);
    setState(() => _done[key] = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, next);
  }

  @override
  Widget build(BuildContext context) {
    final count = _done.values.where((value) => value).length;
    return SettingsModalShell(
      title: 'Getting started',
      eyebrow: 'RESOURCES',
      children: [
        SettingsCard(
          divided: false,
          children: [
            Padding(
              padding: const EdgeInsets.all(ZveltTokens.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Setup progress',
                          style: ZType.bodyL
                              .copyWith(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text('$count / ${_steps.length}',
                          style: ZType.num_.copyWith(color: ZveltTokens.brand)),
                    ],
                  ),
                  const SizedBox(height: ZveltTokens.s3),
                  LinearProgressIndicator(
                    value: count / _steps.length,
                    minHeight: 8,
                    color: ZveltTokens.brand,
                    backgroundColor: ZveltTokens.surface3,
                    borderRadius: const BorderRadius.all(Radius.circular(99)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: ZveltTokens.cardGap),
        SettingsCard(
          children: [
            for (final step in _steps)
              ListTile(
                minTileHeight: 68,
                onTap: () => _toggle(step.key),
                leading: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _done[step.key]!
                        ? ZveltTokens.success
                        : ZveltTokens.bg2,
                  ),
                  child: _done[step.key]!
                      ? const Icon(AppIcons.check,
                          color: Colors.white, size: 18)
                      : null,
                ),
                title: Text(
                  step.title,
                  style: ZType.bodyM.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration:
                        _done[step.key]! ? TextDecoration.lineThrough : null,
                    color:
                        _done[step.key]! ? ZveltTokens.text3 : ZveltTokens.text,
                  ),
                ),
                subtitle: Text(step.sub,
                    style: ZType.bodyS.copyWith(color: ZveltTokens.text3)),
              ),
          ],
        ),
      ],
    );
  }
}

class KnowledgeBaseScreen extends StatefulWidget {
  const KnowledgeBaseScreen({super.key});

  @override
  State<KnowledgeBaseScreen> createState() => _KnowledgeBaseScreenState();
}

class _KnowledgeBaseScreenState extends State<KnowledgeBaseScreen> {
  static const _articles = [
    (
      category: 'Progress',
      q: 'How are strength ranks calculated?',
      a: 'Zvelt uses your best estimated one-rep max relative to bodyweight, compares it with the relevant cohort and explains which lifts contribute to the result.'
    ),
    (
      category: 'Devices',
      q: 'Which watches and wearables work?',
      a: 'Health Connect or Apple Health provide the on-device baseline. Garmin, Fitbit, Oura and other supported providers connect through the cloud wearable layer.'
    ),
    (
      category: 'Data',
      q: 'How much health history is imported?',
      a: 'The first on-device connection requests a recent seven-day window. Cloud providers can backfill deeper history according to each provider limit.'
    ),
    (
      category: 'Coaching',
      q: 'Why did the AI choose this workout?',
      a: 'Recommendations use your stated goal, recent training, equipment, schedule and recovery signals. Each suggested exercise includes a reason.'
    ),
    (
      category: 'Social',
      q: 'Who can see my activity?',
      a: 'Profile visibility and per-post privacy control sharing. Friends-only is the default and discovery is opt-in.'
    ),
    (
      category: 'General',
      q: 'Can I use Zvelt without internet?',
      a: 'Workout logging remains available offline. Pending changes sync automatically when the device reconnects.'
    ),
  ];

  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final visible = _articles
        .where((item) =>
            q.isEmpty ||
            '${item.category} ${item.q} ${item.a}'.toLowerCase().contains(q))
        .toList();
    return SettingsModalShell(
      title: 'Knowledge base',
      eyebrow: 'RESOURCES',
      children: [
        TextField(
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: 'Search guides and FAQ',
            prefixIcon: const Icon(AppIcons.search),
            filled: true,
            fillColor: ZveltTokens.surface,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ZveltTokens.rLg),
                borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: ZveltTokens.cardGap),
        if (visible.isEmpty)
          const SettingsNoteCard(
              'No guide matches that search. Try a shorter phrase.')
        else
          SettingsCard(
            children: [
              for (final item in visible)
                ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(
                      horizontal: ZveltTokens.s4, vertical: 4),
                  childrenPadding: const EdgeInsets.fromLTRB(
                      ZveltTokens.s4, 0, ZveltTokens.s4, ZveltTokens.s4),
                  title: Text(item.q,
                      style: ZType.bodyM.copyWith(fontWeight: FontWeight.w600)),
                  subtitle: Text(item.category.toUpperCase(),
                      style: ZType.eyebrow.copyWith(color: ZveltTokens.brand)),
                  children: [
                    Align(
                        alignment: Alignment.centerLeft,
                        child: Text(item.a,
                            style:
                                ZType.bodyM.copyWith(color: ZveltTokens.text2)))
                  ],
                ),
            ],
          ),
        const SizedBox(height: ZveltTokens.s5),
        SettingsActionButton(
          label: 'Chat with us',
          icon: AppIcons.comment_alt,
          onTap: () => _mail(context,
              address: 'support@zvelt.app', subject: 'Zvelt support'),
        ),
      ],
    );
  }
}

enum FeedbackKind { feature, bug }

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key, required this.kind});

  final FeedbackKind kind;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _details = TextEditingController();
  String? _category;
  bool _attachLogs = true;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  List<String> get _categories => widget.kind == FeedbackKind.bug
      ? ['Crash', 'Visual glitch', 'Sync issue', 'Wrong data', 'Other']
      : ['Workouts', 'Social', 'Nutrition', 'Coaching', 'Other'];

  Future<void> _submit() async {
    if (_details.text.trim().length < 8) {
      settingsSnack(context, 'Add a few details first.', error: true);
      return;
    }
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    final ref = '#ZV-${1000 + Random.secure().nextInt(9000)}';
    final kind =
        widget.kind == FeedbackKind.bug ? 'Bug report' : 'Feature request';
    final body =
        '$kind $ref\nCategory: ${_category ?? 'Other'}\nApp: ${info.version} (${info.buildNumber})\nAttach diagnostics: $_attachLogs\n\n${_details.text.trim()}';
    await _mail(
      context,
      address: widget.kind == FeedbackKind.bug
          ? 'bugs@zvelt.app'
          : 'feedback@zvelt.app',
      subject: '$kind $ref',
      body: body,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBug = widget.kind == FeedbackKind.bug;
    return SettingsModalShell(
      title: isBug ? 'Report a bug' : 'Request a feature',
      eyebrow: 'RESOURCES',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in _categories)
              ChoiceChip(
                label: Text(category),
                selected: _category == category,
                onSelected: (_) => setState(() => _category = category),
                selectedColor: ZveltTokens.brandTint,
                side: BorderSide(color: ZveltTokens.border),
              ),
          ],
        ),
        const SizedBox(height: ZveltTokens.s4),
        TextField(
          controller: _details,
          minLines: 7,
          maxLines: 12,
          decoration: InputDecoration(
            hintText: isBug
                ? 'What happened? Include steps to reproduce.'
                : 'What would make Zvelt better for you?',
            filled: true,
            fillColor: ZveltTokens.surface,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                borderSide: BorderSide.none),
          ),
        ),
        if (isBug) ...[
          const SizedBox(height: ZveltTokens.cardGap),
          SettingsCard(
            children: [
              SettingsSwitchRow(
                icon: AppIcons.document,
                tint: SettingsTint.blue,
                title: 'Attach diagnostic context',
                subtitle: 'App version and device-safe technical details',
                value: _attachLogs,
                onChanged: (value) => setState(() => _attachLogs = value),
              ),
            ],
          ),
        ],
        const SizedBox(height: ZveltTokens.s5),
        SettingsActionButton(
          label: isBug ? 'Submit bug report' : 'Submit request',
          icon: AppIcons.paper_plane,
          onTap: _submit,
        ),
      ],
    );
  }
}

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.privacy});

  final bool privacy;

  @override
  Widget build(BuildContext context) {
    final sections = privacy ? _privacySections : _termsSections;
    return SettingsModalShell(
      title: privacy ? 'Privacy Policy' : 'Terms of Service',
      eyebrow: 'LEGAL',
      children: [
        SettingsNoteCard(privacy
            ? 'Privacy contact: privacy@zvelt.app'
            : 'Updated 1 May 2026'),
        const SizedBox(height: ZveltTokens.cardGap),
        for (final section in sections) ...[
          SettingsCard(
            divided: false,
            children: [
              Padding(
                padding: const EdgeInsets.all(ZveltTokens.s4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(section.title, style: ZType.h4),
                    const SizedBox(height: ZveltTokens.s2),
                    Text(section.body,
                        style: ZType.bodyM.copyWith(color: ZveltTokens.text2)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: ZveltTokens.cardGap),
        ],
        SettingsActionButton(
          label: 'Open current web version',
          icon: AppIcons.arrow_up_right_from_square,
          onTap: () => _open(
              context,
              privacy
                  ? 'https://zvelt.app/privacy'
                  : 'https://zvelt.app/terms'),
        ),
      ],
    );
  }
}

typedef _LegalSection = ({String title, String body});

const List<_LegalSection> _termsSections = [
  (
    title: 'Acceptance',
    body:
        'By using Zvelt you agree to these terms and the policies referenced here. Stop using the service if you do not agree.'
  ),
  (
    title: 'Your account',
    body:
        'Keep your sign-in credentials secure and provide accurate information. You are responsible for activity performed through your account.'
  ),
  (
    title: 'Health disclaimer',
    body:
        'Zvelt supports fitness decisions but does not provide medical diagnosis or treatment. Seek qualified medical advice when needed.'
  ),
  (
    title: 'Acceptable use',
    body:
        'Do not misuse the service, harass others, falsify competitive data, bypass security controls or infringe third-party rights.'
  ),
  (
    title: 'Subscriptions',
    body:
        'Paid plans renew through the relevant app store until cancelled. Store rules govern billing, refunds and subscription management.'
  ),
  (
    title: 'Changes',
    body:
        'We may update these terms as the product evolves. Material changes will be communicated before they take effect where required.'
  ),
];

const List<_LegalSection> _privacySections = [
  (
    title: 'What we collect',
    body:
        'Account, profile, workout, nutrition, social and health data you choose to provide or connect, plus limited security and diagnostic data.'
  ),
  (
    title: 'How we use it',
    body:
        'To operate Zvelt, personalise training, calculate progress, synchronise devices, prevent abuse and improve reliability.'
  ),
  (
    title: 'What we never do',
    body:
        'We do not sell personal health data or use private health records for third-party advertising.'
  ),
  (
    title: 'Sharing',
    body:
        'Data is shared only with processors needed to run the service, providers you connect, people you explicitly share with, or authorities when legally required.'
  ),
  (
    title: 'Your rights',
    body:
        'You can access, correct, export and delete your data. You can withdraw optional health, discovery and diagnostic permissions at any time.'
  ),
  (
    title: 'Contact',
    body:
        'For privacy requests contact privacy@zvelt.app. Requests are handled according to applicable data-protection law.'
  ),
];

Future<void> _mail(
  BuildContext context, {
  required String address,
  required String subject,
  String body = '',
}) async {
  final uri = Uri(
      scheme: 'mailto',
      path: address,
      queryParameters: {'subject': subject, if (body.isNotEmpty) 'body': body});
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  } else if (context.mounted) {
    settingsSnack(context, 'No email app is available on this device.',
        error: true);
  }
}

Future<void> _open(BuildContext context, String value) async {
  final uri = Uri.parse(value);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else if (context.mounted) {
    settingsSnack(context, 'Could not open this link.', error: true);
  }
}
