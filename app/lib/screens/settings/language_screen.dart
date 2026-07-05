import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../theme/locale_notifier.dart';
import '../../theme/zvelt_tokens.dart';
import 'settings_kit.dart';

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  /// English is the only shipped translation, so it is the only selectable
  /// option — listing untranslated languages would be a placebo control.
  /// LocaleNotifier owns persistence and is already wired for future locales.
  Future<void> _selectEnglish() async {
    if ((LocaleNotifier.preference.value ?? 'en') == 'en') return;
    // A legacy preference for a not-yet-translated locale may still be stored;
    // tapping English normalises it.
    await LocaleNotifier.set('en');
    if (mounted) {
      settingsSnack(context, AppLocalizations.of(context).languagePreferenceSaved);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pilot screen for the gen-l10n pipeline: chrome strings come from
    // AppLocalizations. The language endonym below is a proper name and
    // intentionally stays hard-coded.
    final l10n = AppLocalizations.of(context);
    return SettingsModalShell(
      title: l10n.languageScreenTitle,
      eyebrow: l10n.languageScreenEyebrow,
      children: [
        SettingsCard(
          children: [
            SettingsRadioRow(
              title: 'English',
              // English is the active display language in every case today
              // (unsupported stored codes resolve to English), so it is
              // always shown as selected.
              selected: true,
              onTap: _selectEnglish,
            ),
          ],
        ),
        const SizedBox(height: ZveltTokens.s4),
        const SettingsNoteCard('More languages coming soon.'),
      ],
    );
  }
}
