import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../theme/locale_notifier.dart';
import '../../theme/zvelt_tokens.dart';
import 'settings_kit.dart';

typedef _Lang = ({String code, String title, String subtitle});

const List<_Lang> _languages = [
  (code: 'en', title: 'English', subtitle: 'English'),
  (code: 'ro', title: 'Rom\u00e2n\u0103', subtitle: 'Romanian'),
  (code: 'es', title: 'Espa\u00f1ol', subtitle: 'Spanish'),
  (code: 'fr', title: 'Fran\u00e7ais', subtitle: 'French'),
  (code: 'de', title: 'Deutsch', subtitle: 'German'),
  (code: 'it', title: 'Italiano', subtitle: 'Italian'),
  (code: 'pt', title: 'Portugu\u00eas', subtitle: 'Portuguese'),
  (code: 'sv', title: 'Svenska', subtitle: 'Swedish'),
];

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  /// Currently selected UI-language code. Seeded from the live notifier
  /// preference (falls back to 'en') so the radio reflects the active choice;
  /// LocaleNotifier owns persistence.
  String _selected = LocaleNotifier.preference.value ?? 'en';

  Future<void> _select(String code) async {
    if (code == _selected) return;
    setState(() => _selected = code);
    // Drives MaterialApp.locale (and persists) so the app re-renders in the new
    // locale. Codes without a full translation resolve to English; the choice is
    // still saved and shown as selected here.
    await LocaleNotifier.set(code);
    if (mounted) {
      settingsSnack(context, AppLocalizations.of(context).languagePreferenceSaved);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pilot screen for the gen-l10n pipeline: chrome strings come from
    // AppLocalizations. The language endonyms below (English, Română, …) are
    // proper names and intentionally stay hard-coded.
    final l10n = AppLocalizations.of(context);
    return SettingsModalShell(
      title: l10n.languageScreenTitle,
      eyebrow: l10n.languageScreenEyebrow,
      children: [
        SettingsCard(
          children: [
            for (final lang in _languages)
              SettingsRadioRow(
                title: lang.title,
                subtitle: lang.subtitle,
                selected: _selected == lang.code,
                onTap: () => _select(lang.code),
              ),
          ],
        ),
        const SizedBox(height: ZveltTokens.s4),
        SettingsNoteCard(l10n.languageScreenNote),
      ],
    );
  }
}
