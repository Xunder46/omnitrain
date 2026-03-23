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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
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
                        Row(
                          children: AppTheme.values.map((appTheme) {
                            final isSelected =
                                settingsState.appTheme == appTheme;
                            final themeColors = OmniTheme.colorsForTheme(
                              appTheme,
                            );

                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () =>
                                      settingsState.setAppTheme(appTheme),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    curve: Curves.easeInOut,
                                    constraints: const BoxConstraints(
                                      minHeight: 52,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? theme.colorScheme.surface
                                                .withOpacity(0.85)
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
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: themeColors.primary,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            OmniTheme.displayNameForTheme(
                                              appTheme,
                                            ),
                                            textAlign: TextAlign.center,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: isSelected
                                                      ? theme
                                                            .colorScheme
                                                            .onSurface
                                                      : OmniTheme.textSecondary,
                                                  fontWeight: isSelected
                                                      ? FontWeight.w600
                                                      : FontWeight.w500,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
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
