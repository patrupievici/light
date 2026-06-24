import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_strings.dart';

/// Avatar option: id + icon for display.
class AvatarOption {
  const AvatarOption({required this.id, required this.icon});
  final String id;
  final IconData icon;
}

/// FIG 23 — Choose starting avatar. Single select from cards; CTA Next disabled until selection.
class AvatarSelectionScreen extends StatefulWidget {
  const AvatarSelectionScreen({
    super.key,
    required this.options,
    required this.onNext,
  });

  final List<AvatarOption> options;
  final void Function(String selectedId) onNext;

  @override
  State<AvatarSelectionScreen> createState() => _AvatarSelectionScreenState();
}

class _AvatarSelectionScreenState extends State<AvatarSelectionScreen> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text(
                AppStrings.avatarChooseTitle,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.avatarChooseHint,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: widget.options.length,
                  itemBuilder: (context, index) {
                    final opt = widget.options[index];
                    final selected = _selectedId == opt.id;
                    return Material(
                      color: selected ? AppTheme.accentBlue.withValues(alpha: 0.25) : AppTheme.bgElevated,
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                      child: InkWell(
                        onTap: () => setState(() => _selectedId = opt.id),
                        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                            border: Border.all(
                              color: selected ? AppTheme.accentBlue : AppTheme.border,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              opt.icon,
                              size: 48,
                              color: selected ? AppTheme.accentBlue : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _selectedId != null
                    ? () => widget.onNext(_selectedId!)
                    : null,
                child: const Text(AppStrings.avatarNext),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
