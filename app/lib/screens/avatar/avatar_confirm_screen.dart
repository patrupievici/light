import 'package:flutter/material.dart';
import '../../theme/zvelt_tokens.dart';
import '../../l10n/app_strings.dart';
import 'avatar_selection_screen.dart';

/// FIG 24 — Confirm chosen avatar. Show selection + positive feedback; CTA Continue.
class AvatarConfirmScreen extends StatelessWidget {
  const AvatarConfirmScreen({
    super.key,
    required this.avatarOption,
    required this.onContinue,
  });

  final AvatarOption avatarOption;
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
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: ZveltTokens.brand.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(ZveltTokens.rLg * 2),
                    border: Border.all(color: ZveltTokens.brand, width: 2),
                  ),
                  child: Icon(avatarOption.icon, size: 80, color: ZveltTokens.brand),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                AppStrings.avatarConfirmTitle,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: ZveltTokens.text,
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                AppStrings.avatarConfirmMessage,
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
