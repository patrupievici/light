import 'package:flutter/material.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';
import '../../l10n/app_strings.dart';

/// FIG 20–22 — Intro: avatar as identity + progress. CTA: Continue.
class AvatarIntroScreen extends StatelessWidget {
  const AvatarIntroScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 1),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: ZveltTokens.brand.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(ZveltTokens.rLg * 2),
                  ),
                  child: const Icon(AppIcons.user, size: 72, color: ZveltTokens.brand),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                AppStrings.avatarIntroTitle,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: ZveltTokens.text,
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                AppStrings.avatarIntroMessage,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: ZveltTokens.text2,
                      height: 1.5,
                    ),
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 2),
              FilledButton(
                onPressed: onContinue,
                child: const Text(AppStrings.continueCta),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
