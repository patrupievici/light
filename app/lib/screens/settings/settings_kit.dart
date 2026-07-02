// Settings design kit — shared, reusable building blocks for the redesigned
// Settings hub and every sub-screen. Mirrors the "Zvelt Settings — Spec.html"
// design system: light surface, colored icon tiles, rounded cards, mono
// eyebrows, a single orange signal. All widgets here are PUBLIC so the root
// screen and the per-section sub-screens can share one consistent language.
//
// Tile colour legend (from the spec):
//   orange → account/brand · blue → recovery/data · violet → sleep/AI
//   amber  → resources      · green → strength/OK  · red → alerts
//   gray   → neutral/legal
import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../../services/settings_store.dart';
import '../../theme/zvelt_tokens.dart';

/// Semantic tile colours used across Settings rows.
class SettingsTint {
  const SettingsTint._();
  static const Color orange = ZveltTokens.brandDeep;
  static const Color blue = ZveltTokens.recovery;
  static const Color violet = ZveltTokens.sleep;
  static const Color amber = ZveltTokens.warn;
  static const Color green = ZveltTokens.strength;
  static const Color red = ZveltTokens.cardio;
  static Color gray = ZveltTokens.text2;
}

/// Soft background behind a colored icon (12–14% of the icon colour).
Color settingsTintBg(Color c) => c.withValues(alpha: 0.13);

// ─────────────────────────────────────────────────────────────────────────────
// Shell — full-screen modal scaffold with a circular back/close button.
// ─────────────────────────────────────────────────────────────────────────────

/// Full-screen settings scaffold. [onClose] overrides the default back/pop;
/// pass [closeIcon] = AppIcons.cross_small for destinations that "close fully".
class SettingsModalShell extends StatelessWidget {
  const SettingsModalShell({
    super.key,
    required this.title,
    required this.children,
    this.eyebrow,
    this.onClose,
    this.closeIcon = AppIcons.arrow_small_left,
    this.footer,
    this.padBottom = ZveltTokens.s10,
  });

  final String title;
  final String? eyebrow;
  final List<Widget> children;
  final VoidCallback? onClose;
  final IconData closeIcon;

  /// Pinned footer below the scrollable list (e.g. a primary action).
  final Widget? footer;
  final double padBottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        backgroundColor: ZveltTokens.bg,
        centerTitle: true,
        titleSpacing: 0,
        leadingWidth: 64,
        surfaceTintColor: Colors.transparent,
        leading: Center(
          child: Semantics(
            button: true,
            label: 'Back',
            child: GestureDetector(
              onTap: onClose ?? () => Navigator.of(context).maybePop(),
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ZveltTokens.surface,
                  shape: BoxShape.circle,
                  boxShadow: ZveltTokens.shadowCard,
                ),
                child: Icon(closeIcon, color: ZveltTokens.text, size: 20),
              ),
            ),
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontFamily: ZveltTokens.fontPrimary,
            fontWeight: FontWeight.w700,
            color: ZveltTokens.text,
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                ZveltTokens.screenPaddingH,
                eyebrow == null ? ZveltTokens.s2 : ZveltTokens.s1,
                ZveltTokens.screenPaddingH,
                padBottom,
              ),
              children: [
                if (eyebrow != null) ...[
                  SettingsEyebrow(eyebrow!),
                  const SizedBox(height: ZveltTokens.s3),
                ],
                ...children,
              ],
            ),
          ),
          if (footer != null)
            Container(
              padding: EdgeInsets.fromLTRB(
                ZveltTokens.screenPaddingH,
                ZveltTokens.s3,
                ZveltTokens.screenPaddingH,
                ZveltTokens.s4 + MediaQuery.paddingOf(context).bottom,
              ),
              decoration: BoxDecoration(
                color: ZveltTokens.bg,
                border: Border(top: BorderSide(color: ZveltTokens.border)),
              ),
              child: footer,
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section + card.
// ─────────────────────────────────────────────────────────────────────────────

/// Big bold group title ("Account", "General", "Privacy", …).
class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle(this.label,
      {super.key, this.top = ZveltTokens.s6});
  final String label;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          ZveltTokens.s1, top, ZveltTokens.s1, ZveltTokens.s3),
      child: Text(label, style: ZType.h2.copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

/// A quiet mono eyebrow ("STEP 1 · PROFILE", "INTEGRATIONS", …).
class SettingsEyebrow extends StatelessWidget {
  const SettingsEyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: ZType.eyebrow.copyWith(color: color ?? ZveltTokens.text3),
    );
  }
}

/// White rounded card. Children are separated by hairline dividers
/// automatically (inset to align past the icon tiles).
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children, this.divided = true});
  final List<Widget> children;
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final kids = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      kids.add(children[i]);
      if (divided && i != children.length - 1) {
        kids.add(const SettingsHairline());
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: kids),
    );
  }
}

class SettingsHairline extends StatelessWidget {
  const SettingsHairline({super.key, this.inset = ZveltTokens.s4});
  final double inset;
  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        thickness: 1,
        color: ZveltTokens.border,
        indent: inset,
        endIndent: ZveltTokens.s4,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Rows.
// ─────────────────────────────────────────────────────────────────────────────

/// A colored 38×38 rounded icon tile.
class SettingsIconTile extends StatelessWidget {
  const SettingsIconTile(
      {super.key, required this.icon, required this.tint, this.size = 38});
  final IconData icon;
  final Color tint;
  final double size;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: settingsTintBg(tint),
        borderRadius: BorderRadius.circular(ZveltTokens.rSm),
      ),
      child: Icon(icon, color: tint, size: size * 0.5),
    );
  }
}

/// The standard tappable settings row: icon tile · title · subtitle · trailing.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.tint,
    required this.title,
    this.subtitle,
    this.onTap,
    this.badge,
    this.trailingText,
    this.chevron = true,
    this.titleColor,
    this.tag,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Small solid pill on the right of the title (e.g. unread count "6").
  final String? badge;

  /// A small mono tag after the title (e.g. "SHEET", "SNACKBAR").
  final String? tag;

  /// Right-aligned value text shown instead of a chevron destination hint.
  final String? trailingText;
  final bool chevron;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final semantic = subtitle == null ? title : '$title, $subtitle';
    return Semantics(
      button: onTap != null,
      label: semantic,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZveltTokens.s4,
            vertical: ZveltTokens.s3 + 2,
          ),
          child: Row(
            children: [
              SettingsIconTile(icon: icon, tint: tint),
              const SizedBox(width: ZveltTokens.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: ZType.bodyL.copyWith(
                              color: titleColor ?? ZveltTokens.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: ZveltTokens.s2),
                          _Badge(badge!),
                        ],
                        if (tag != null) ...[
                          const SizedBox(width: ZveltTokens.s2),
                          _Tag(tag!),
                        ],
                      ],
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          subtitle!,
                          style: ZType.bodyS.copyWith(color: ZveltTokens.text3),
                        ),
                      ),
                  ],
                ),
              ),
              if (trailingText != null) ...[
                const SizedBox(width: ZveltTokens.s2),
                Text(trailingText!,
                    style: ZType.monoS.copyWith(color: ZveltTokens.text3)),
              ],
              if (chevron)
                Padding(
                  padding: const EdgeInsets.only(left: ZveltTokens.s1),
                  child: Icon(AppIcons.angle_small_right,
                      color: ZveltTokens.text4, size: 22),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row whose trailing element is a Switch.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.icon,
    required this.tint,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final accent = AppPreferencesNotifier.accentColor;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ZveltTokens.s4,
          vertical: ZveltTokens.s3,
        ),
        child: Row(
          children: [
            SettingsIconTile(icon: icon, tint: tint),
            const SizedBox(width: ZveltTokens.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: ZType.bodyL.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(subtitle!,
                          style:
                              ZType.bodyS.copyWith(color: ZveltTokens.text3)),
                    ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeThumbColor: ZveltTokens.onBrand,
              activeTrackColor: accent,
              inactiveThumbColor: ZveltTokens.surface,
              inactiveTrackColor: ZveltTokens.surface3,
            ),
          ],
        ),
      ),
    );
  }
}

/// A radio-style row (single-select); shows a brand check when selected.
class SettingsRadioRow extends StatelessWidget {
  const SettingsRadioRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
    this.leading,
  });
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final accent = AppPreferencesNotifier.accentColor;
    return Semantics(
      selected: selected,
      button: true,
      label: subtitle == null ? title : '$title, $subtitle',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZveltTokens.s4,
            vertical: ZveltTokens.s3 + 2,
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: ZveltTokens.s4)
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style:
                            ZType.bodyL.copyWith(fontWeight: FontWeight.w600)),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(subtitle!,
                            style:
                                ZType.bodyS.copyWith(color: ZveltTokens.text3)),
                      ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? accent : Colors.transparent,
                  border: Border.all(
                    color: selected ? accent : ZveltTokens.borderStrong,
                    width: 2,
                  ),
                ),
                child: selected
                    ? const Icon(AppIcons.check,
                        color: ZveltTokens.onBrand, size: 15)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An equal-width segmented control (Male/Female/Other, Metric/Imperial, …).
class SettingsSegmented<T> extends StatelessWidget {
  const SettingsSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });
  final List<({T value, String label})> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = AppPreferencesNotifier.accentColor;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ZveltTokens.bg2,
        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
      ),
      child: Row(
        children: [
          for (final o in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(o.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: o.value == value
                        ? accent.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                    border: Border.all(
                      color: o.value == value ? accent : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    o.label,
                    style: ZType.bodyM.copyWith(
                      color: o.value == value ? accent : ZveltTokens.text2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A labelled stepper: −  value unit  +  (used for bodyweight, days, 1RM…).
class SettingsStepperRow extends StatelessWidget {
  const SettingsStepperRow({
    super.key,
    required this.label,
    this.subtitle,
    required this.valueLabel,
    required this.onDec,
    required this.onInc,
  });
  final String label;
  final String? subtitle;
  final String valueLabel;
  final VoidCallback? onDec;
  final VoidCallback? onInc;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: ZType.bodyL.copyWith(fontWeight: FontWeight.w600)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(subtitle!,
                        style: ZType.bodyS.copyWith(color: ZveltTokens.text3)),
                  ),
              ],
            ),
          ),
          _StepBtn(icon: AppIcons.minus, onTap: onDec),
          Container(
            constraints: const BoxConstraints(minWidth: 78),
            alignment: Alignment.center,
            child: Text(valueLabel, style: ZType.num_.copyWith(fontSize: 17)),
          ),
          _StepBtn(icon: AppIcons.plus, onTap: onInc),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? ZveltTokens.bg2 : ZveltTokens.bg,
          borderRadius: BorderRadius.circular(ZveltTokens.rSm),
          border: Border.all(color: ZveltTokens.border),
        ),
        child: Icon(icon,
            size: 20, color: on ? ZveltTokens.text : ZveltTokens.text4),
      ),
    );
  }
}

/// Footer-style full-width pill action button (white card look).
class SettingsActionButton extends StatelessWidget {
  const SettingsActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.icon,
  });
  final String label;
  final VoidCallback? onTap;
  final bool destructive;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? ZveltTokens.error : ZveltTokens.text;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        onTap: onTap,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ZveltTokens.surface,
            borderRadius: BorderRadius.circular(ZveltTokens.rLg),
            boxShadow: ZveltTokens.shadowCard,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: ZveltTokens.s2),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: ZType.bodyL.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Brand-tint informational card used at the bottom of several sub-screens.
class SettingsNoteCard extends StatelessWidget {
  const SettingsNoteCard(this.text,
      {super.key, this.icon = AppIcons.info, this.tint});
  final String text;
  final IconData icon;
  final Color? tint;
  @override
  Widget build(BuildContext context) {
    final c = tint ?? ZveltTokens.brand;
    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s4),
      decoration: BoxDecoration(
        color: settingsTintBg(c),
        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
        border: Border(left: BorderSide(color: c, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: ZveltTokens.s3),
          Expanded(
            child: Text(text,
                style: ZType.bodyS
                    .copyWith(color: ZveltTokens.text2, height: 1.45)),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: ZveltTokens.brand,
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
      ),
      child: Text(text,
          style: ZType.monoXS.copyWith(
              color: ZveltTokens.onBrand, fontWeight: FontWeight.w600)),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: ZveltTokens.bg2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ZveltTokens.border),
      ),
      child: Text(text.toUpperCase(),
          style: ZType.eyebrow.copyWith(color: ZveltTokens.text2)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feedback helpers — snackbar, confirm sheet, bottom-sheet container.
// ─────────────────────────────────────────────────────────────────────────────

/// Floating snackbar matching the V2 design (success/error).
void settingsSnack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: error ? ZveltTokens.error : ZveltTokens.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZveltTokens.rSm)),
    ),
  );
}

/// Rounded-top sheet container (surface, rXl top corners). Wrap sheet content.
class SettingsSheet extends StatelessWidget {
  const SettingsSheet(
      {super.key, required this.title, this.eyebrow, required this.child});
  final String title;
  final String? eyebrow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: ZveltTokens.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
        ),
        padding: const EdgeInsets.fromLTRB(
            ZveltTokens.s5, ZveltTokens.s4, ZveltTokens.s5, ZveltTokens.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: ZveltTokens.s4),
                decoration: BoxDecoration(
                  color: ZveltTokens.surface3,
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                ),
              ),
            ),
            if (eyebrow != null) ...[
              SettingsEyebrow(eyebrow!),
              const SizedBox(height: ZveltTokens.s1),
            ],
            Text(title, style: ZType.h3.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: ZveltTokens.s4),
            child,
          ],
        ),
      ),
    );
  }
}

/// Present [sheet] as a modal bottom sheet using the app-wide pattern.
Future<T?> showSettingsSheet<T>(BuildContext context, Widget sheet) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => sheet,
  );
}

/// A destructive/neutral confirmation bottom sheet. Resolves true on confirm.
Future<bool> settingsConfirm(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showSettingsSheet<bool>(
    context,
    SettingsSheet(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(body,
              style:
                  ZType.bodyM.copyWith(color: ZveltTokens.text2, height: 1.5)),
          const SizedBox(height: ZveltTokens.s5),
          _SheetButton(
            label: confirmLabel,
            filled: true,
            color: destructive ? ZveltTokens.error : ZveltTokens.brand,
            onTap: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: ZveltTokens.s2),
          _SheetButton(
            label: 'Cancel',
            filled: false,
            color: ZveltTokens.text2,
            onTap: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

class _SheetButton extends StatelessWidget {
  const _SheetButton(
      {required this.label,
      required this.filled,
      required this.color,
      required this.onTap});
  final String label;
  final bool filled;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? color : ZveltTokens.surface2,
            borderRadius: BorderRadius.circular(ZveltTokens.rMd),
            border: filled ? null : Border.all(color: ZveltTokens.border),
          ),
          child: Text(
            label,
            style: ZType.bodyL.copyWith(
              color: filled ? ZveltTokens.onBrand : color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
