import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../../state/settings/settings_state.dart';
import '../../widgets/layout/omni_gradient_background.dart';
import '../../widgets/layout/omni_surface.dart';

class SettingsScreen extends StatelessWidget {
  final SettingsState settingsState;

  const SettingsScreen({super.key, required this.settingsState});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Settings'),
      ),
      body: OmniGradientBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: settingsState,
            builder: (context, child) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  OmniSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'APPEARANCE',
                          style: theme.textTheme.labelSmall?.copyWith(
                            letterSpacing: 2,
                            color: OmniTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: AppTheme.values.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: 2.8,
                              ),
                          itemBuilder: (context, index) {
                            final appTheme = AppTheme.values[index];
                            final isSelected = settingsState.appTheme == appTheme;

                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => settingsState.setAppTheme(appTheme),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeInOut,
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? theme.colorScheme.surface.withOpacity(0.88)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(
                                    OmniTheme.buttonUtilityRadius,
                                  ),
                                  border: Border.all(
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface
                                            .withOpacity(0.25),
                                  ),
                                ),
                                child: Text(
                                  OmniTheme.displayNameForTheme(appTheme),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: isSelected
                                        ? theme.colorScheme.onSurface
                                        : OmniTheme.textSecondary,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
