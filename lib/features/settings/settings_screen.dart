import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/utils/unit_formatter.dart';
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
                  _MeasurementsSection(
                    settingsState: settingsState,
                    theme: theme,
                  ),
                  const SizedBox(height: 24),
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
                          // Ghost-pad odd counts so the last row is never a
                          // lone tile. When count becomes even after the
                          // bake-off pruning pass this expression collapses
                          // to plain length with no visual change needed.
                          itemCount: AppTheme.values.length.isOdd
                              ? AppTheme.values.length + 1
                              : AppTheme.values.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: 2.8,
                              ),
                          itemBuilder: (context, index) {
                            // Ghost slot that balances an odd-count final row.
                            if (index >= AppTheme.values.length) {
                              return const SizedBox.shrink();
                            }
                            final appTheme = AppTheme.values[index];
                            final isSelected =
                                settingsState.appTheme == appTheme;

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
                                      ? theme.colorScheme.surface.withOpacity(
                                          0.88,
                                        )
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
                  const SizedBox(height: 24),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Version 1.0.0',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: OmniTheme.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MeasurementsSection extends StatelessWidget {
  final SettingsState settingsState;
  final ThemeData theme;

  const _MeasurementsSection({
    required this.settingsState,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return OmniSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(title: 'PREFERENCES'),
          _SettingsRow(
            label: 'Start of Week',
            subtitle: 'First day shown in the calendar',
            trailing: _SegmentedToggle(
              groupValue: settingsState.startOfWeek,
              options: const [
                _SegmentedOption(value: 'sunday', label: 'Sun'),
                _SegmentedOption(value: 'monday', label: 'Mon'),
              ],
              onChanged: settingsState.setStartOfWeek,
            ),
          ),
          _SurfaceDivider(theme: theme),
          _SettingsRow(
            label: 'Weight',
            subtitle: 'Used for exercises and volume',
            trailing: _SegmentedToggle(
              groupValue: UnitFormatter.normalizeWeightUnit(
                settingsState.preferredWeightUnit,
              ),
              options: [
                _SegmentedOption(
                  value: 'kg',
                  label: UnitFormatter.weightLabelForUnit('kg'),
                ),
                _SegmentedOption(
                  value: 'lbs',
                  label: UnitFormatter.weightLabelForUnit('lbs'),
                ),
              ],
              onChanged: (value) {
                settingsState.setPreferredWeightUnit(value);
              },
            ),
          ),
          _SurfaceDivider(theme: theme),
          _SettingsRow(
            label: 'Distance',
            subtitle: 'Used for cardio and timed exercises',
            trailing: _SegmentedToggle(
              groupValue: UnitFormatter.normalizeDistanceUnit(
                settingsState.preferredDistanceUnit,
              ),
              options: [
                _SegmentedOption(
                  value: 'km',
                  label: UnitFormatter.distanceLabelForUnit('km'),
                ),
                _SegmentedOption(
                  value: 'miles',
                  label: UnitFormatter.distanceLabelForUnit('miles'),
                ),
              ],
              onChanged: settingsState.setPreferredDistanceUnit,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PREVIEW',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: OmniTheme.textMuted,
                      fontSize: 10,
                      letterSpacing: 2.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _PreviewValue(
                          icon: Icons.fitness_center,
                          value: UnitFormatter.formatWeight(
                            100.0,
                            settingsState,
                          ),
                          theme: theme,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _PreviewValue(
                          icon: Icons.straighten,
                          value: UnitFormatter.formatDistance(
                            5.0,
                            settingsState,
                          ),
                          theme: theme,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Text(
        title,
        style: theme.textTheme.labelSmall?.copyWith(
          color: OmniTheme.textMuted,
          fontSize: 11,
          letterSpacing: 2.0,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  const _SettingsRow({
    required this.label,
    this.subtitle,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: OmniTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: OmniTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing,
          ],
        ),
      ),
    );

    if (onTap == null) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(OmniTheme.surfaceBorderRadius),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class _SegmentedOption {
  final String value;
  final String label;

  const _SegmentedOption({required this.value, required this.label});
}

class _SegmentedToggle extends StatelessWidget {
  final String groupValue;
  final List<_SegmentedOption> options;
  final ValueChanged<String> onChanged;

  const _SegmentedToggle({
    required this.groupValue,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((option) {
          final isActive = option.value == groupValue;

          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => onChanged(option.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeInOut,
                alignment: Alignment.center,
                constraints: const BoxConstraints(minWidth: 52, minHeight: 36),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  option.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 13,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w600,
                    color: isActive ? Colors.black : OmniTheme.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PreviewValue extends StatelessWidget {
  final IconData icon;
  final String value;
  final ThemeData theme;

  const _PreviewValue({
    required this.icon,
    required this.value,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: theme.colorScheme.primary.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: OmniTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _SurfaceDivider extends StatelessWidget {
  final ThemeData theme;

  const _SurfaceDivider({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
    );
  }
}
