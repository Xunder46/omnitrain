import 'dart:async';
import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/constants/health_constants.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/models/app_version_info.dart';
import '../../core/utils/unit_formatter.dart';
import '../../state/profile/profile_state.dart';
import '../../state/settings/settings_state.dart';
import '../../widgets/layout/omni_back_header.dart';
import '../../widgets/layout/omni_card_header.dart';
import '../../widgets/layout/omni_surface.dart';
import '../../core/utils/timer_alert_service.dart';
import '../../core/utils/rest_notification_service.dart';
import '../../widgets/dialogs/confirmation_dialog.dart';

/// Widget keys for the two platform-health toggles. Tests target a specific
/// control through these rather than "the Nth switch in the list", which
/// depends on which rows the lazy list happens to have built.
const Key healthWriteToggleKey = Key('health-write-toggle');
const Key healthReadToggleKey = Key('health-read-toggle');

class SettingsScreen extends StatefulWidget {
  final SettingsState settingsState;
  final TimerAlertService timerAlertService;
  final RestNotificationService restNotificationService;
  final ProfileState? profileState;
  final double? userHeightCm; // For testing - directly pass height value
  final AppVersionInfo appVersionInfo;

  SettingsScreen({
    super.key,
    required this.settingsState,
    required this.timerAlertService,
    required this.appVersionInfo,
    RestNotificationService? restNotificationService,
    this.profileState,
    this.userHeightCm,
  }) : restNotificationService =
           restNotificationService ?? RestNotificationService.noop();

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double? _userHeightCm;
  bool _isLoadingHeight = true;

  @override
  void initState() {
    super.initState();
    _loadHeight();
  }

  Future<void> _loadHeight() async {
    // If height is provided directly (for testing), use it
    if (widget.userHeightCm != null) {
      if (mounted) {
        setState(() {
          _userHeightCm = widget.userHeightCm;
          _isLoadingHeight = false;
        });
      }
      return;
    }

    final profileState = widget.profileState;
    if (profileState != null) {
      try {
        // Load height measurement directly from the repository to ensure
        // we always get the latest value, regardless of cached state.
        final heightEntry = await profileState.getMeasurementHistory('height');
        double? heightCm;
        if (heightEntry.isNotEmpty) {
          // Sort by date descending and take the most recent
          heightEntry.sort((a, b) => b.recordedAtMs.compareTo(a.recordedAtMs));
          heightCm = heightEntry.first.value;
        }
        if (mounted) {
          setState(() {
            _userHeightCm = heightCm;
            _isLoadingHeight = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _isLoadingHeight = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoadingHeight = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: const OmniBackHeader(title: 'Settings'),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.settingsState,
          builder: (context, child) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                const OmniCardHeader(title: 'PREFERENCES'),
                _MeasurementsSection(
                  settingsState: widget.settingsState,
                  theme: theme,
                  userHeightCm: _isLoadingHeight ? null : _userHeightCm,
                ),
                const SizedBox(height: 24),
                const OmniCardHeader(title: 'SOUNDS & ALERTS'),
                _SoundsAlertsSection(
                  settingsState: widget.settingsState,
                  timerAlertService: widget.timerAlertService,
                  restNotificationService: widget.restNotificationService,
                ),
                const SizedBox(height: 24),
                const OmniCardHeader(title: 'WORKOUT'),
                _WorkoutSection(settingsState: widget.settingsState),
                const SizedBox(height: 24),
                const OmniCardHeader(title: 'HEALTH'),
                _HealthSection(settingsState: widget.settingsState),
                const SizedBox(height: 24),
                const OmniCardHeader(title: 'APPEARANCE'),
                OmniSurface(
                  padding: const EdgeInsets.all(0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GridView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
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
                              widget.settingsState.appTheme == appTheme;

                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () =>
                                widget.settingsState.setAppTheme(appTheme),
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
                                      : theme.colorScheme.onSurface.withOpacity(
                                          0.25,
                                        ),
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
                                      : OmniTheme.colors.textSecondary,
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
                      widget.appVersionInfo.formatVersionLine(),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: OmniTheme.colors.textMuted,
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
    );
  }
}

// ── SOUNDS & ALERTS ───────────────────────────────────────────────────────

class _SoundsAlertsSection extends StatefulWidget {
  final SettingsState settingsState;
  final TimerAlertService timerAlertService;
  final RestNotificationService restNotificationService;

  const _SoundsAlertsSection({
    required this.settingsState,
    required this.timerAlertService,
    required this.restNotificationService,
  });

  @override
  State<_SoundsAlertsSection> createState() => _SoundsAlertsSectionState();
}

class _SoundsAlertsSectionState extends State<_SoundsAlertsSection> {
  bool _notificationsEnabled = false;

  @override
  void initState() {
    super.initState();
    _refreshNotificationStatus();
  }

  Future<void> _refreshNotificationStatus() async {
    if (kIsWeb) return;

    if (!widget.settingsState.notificationPermissionAsked) {
      if (!mounted) return;
      setState(() => _notificationsEnabled = false);
      return;
    }

    final enabled = await widget.restNotificationService.hasPermission();
    if (!mounted) return;
    setState(() => _notificationsEnabled = enabled);
  }

  Future<void> _handleNotificationRowTap(BuildContext context) async {
    if (kIsWeb) return;

    if (!widget.settingsState.notificationPermissionAsked) {
      final granted = await widget.restNotificationService.requestPermission();
      await widget.settingsState.setNotificationPermissionAsked();
      if (!mounted) return;
      setState(() => _notificationsEnabled = granted);
      return;
    }

    if (!_notificationsEnabled) {
      await AppSettings.openAppSettings();
      await _refreshNotificationStatus();
    }
  }

  Future<void> _handleIntervalSelected(BuildContext context, int value) async {
    await widget.settingsState.setRestPingInterval(value);
    if (!mounted) return;
    Navigator.pop(context);

    if (kIsWeb ||
        value <= 0 ||
        widget.settingsState.notificationPermissionAsked) {
      return;
    }

    final shouldRequest = await showDialog<bool>(
      context: this.context,
      barrierDismissible: true,
      builder: (ctx) => ConfirmationDialog.twoChoice(
        title: 'Enable Timer Notifications?',
        body: const Text(
          'Notifications keep rest pings and effort timer alerts working when '
          'your phone is locked. You can change this any time in Settings.',
        ),
        dismissLabel: 'Not now',
        confirmLabel: 'Continue',
        dismissKey: const Key('settings-timer-notifications-cancel'),
        confirmKey: const Key('settings-timer-notifications-confirm'),
        isDestructive: false,
      ),
    );

    if (shouldRequest == true) {
      final granted = await widget.restNotificationService.requestPermission();
      await widget.settingsState.setNotificationPermissionAsked();
      if (!mounted) return;
      setState(() => _notificationsEnabled = granted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final permissionAsked = widget.settingsState.notificationPermissionAsked;
    final notificationStatus = !permissionAsked
        ? 'Not yet asked'
        : (_notificationsEnabled
              ? 'Enabled'
              : 'Disabled - tap to open Settings');
    final statusColor = !permissionAsked
        ? OmniTheme.colors.textSecondary
        : (_notificationsEnabled
              ? theme.colorScheme.primary
              : theme.colorScheme.error);

    return OmniSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsRow(
            label: 'Effort Timer Sound',
            subtitle: 'Plays when a set or round timer expires',
            trailing: Text(
              SettingsState.soundDisplayNames[widget
                      .settingsState
                      .effortTimerSound] ??
                  widget.settingsState.effortTimerSound,
              style: theme.textTheme.bodySmall?.copyWith(
                color: OmniTheme.colors.textSecondary,
              ),
            ),
            onTap: () => _showSoundPicker(
              context,
              title: 'Effort Timer Sound',
              currentId: widget.settingsState.effortTimerSound,
              onSelected: widget.settingsState.setEffortTimerSound,
            ),
          ),
          _SurfaceDivider(theme: theme),
          _SettingsRow(
            label: 'Rest Ping',
            subtitle: 'Periodic reminder during rest',
            trailing: Text(
              _intervalLabel(widget.settingsState.restPingInterval),
              style: theme.textTheme.bodySmall?.copyWith(
                color: OmniTheme.colors.textSecondary,
              ),
            ),
            onTap: () => _showIntervalPicker(context),
          ),
          _SurfaceDivider(theme: theme),
          _SettingsRow(
            label: 'Rest Ping Sound',
            subtitle: 'Sound used for the rest interval ping',
            trailing: Text(
              SettingsState.soundDisplayNames[widget
                      .settingsState
                      .restPingSound] ??
                  widget.settingsState.restPingSound,
              style: theme.textTheme.bodySmall?.copyWith(
                color: OmniTheme.colors.textSecondary,
              ),
            ),
            onTap: () => _showSoundPicker(
              context,
              title: 'Rest Ping Sound',
              currentId: widget.settingsState.restPingSound,
              onSelected: widget.settingsState.setRestPingSound,
            ),
          ),
          if (!kIsWeb) ...[
            _SurfaceDivider(theme: theme),
            _SettingsRow(
              label: 'Notification Permission',
              subtitle:
                  'Required for rest and effort timer alerts while phone is locked or app is backgrounded',
              trailing: Text(
                notificationStatus,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => _handleNotificationRowTap(context),
            ),
          ],
        ],
      ),
    );
  }

  String _intervalLabel(int seconds) {
    for (final opt in SettingsState.restPingIntervalOptions) {
      if (opt.value == seconds) return opt.label;
    }
    return 'Off';
  }

  Future<void> _showSoundPicker(
    BuildContext context, {
    required String title,
    required String currentId,
    required void Function(String) onSelected,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _SoundPickerSheet(
        title: title,
        currentId: currentId,
        timerAlertService: widget.timerAlertService,
        onSelected: onSelected,
      ),
    );
  }

  Future<void> _showIntervalPicker(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _IntervalPickerSheet(
        currentValue: widget.settingsState.restPingInterval,
        onSelected: (value) => _handleIntervalSelected(ctx, value),
      ),
    );
  }
}

class _SoundPickerSheet extends StatefulWidget {
  final String title;
  final String currentId;
  final TimerAlertService timerAlertService;
  final void Function(String) onSelected;

  const _SoundPickerSheet({
    required this.title,
    required this.currentId,
    required this.timerAlertService,
    required this.onSelected,
  });

  @override
  State<_SoundPickerSheet> createState() => _SoundPickerSheetState();
}

class _SoundPickerSheetState extends State<_SoundPickerSheet> {
  late String _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.currentId;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            for (final soundId in SettingsState.validSoundIds)
              _SoundOptionTile(
                soundId: soundId,
                displayName:
                    SettingsState.soundDisplayNames[soundId] ?? soundId,
                isSelected: soundId == _selectedId,
                onTap: () {
                  setState(() => _selectedId = soundId);
                  unawaited(widget.timerAlertService.playPreview(soundId));
                  widget.onSelected(soundId);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SoundOptionTile extends StatelessWidget {
  final String soundId;
  final String displayName;
  final bool isSelected;
  final VoidCallback onTap;

  const _SoundOptionTile({
    required this.soundId,
    required this.displayName,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(
        displayName,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: isSelected
              ? theme.colorScheme.primary
              : OmniTheme.colors.textDominant,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check, color: theme.colorScheme.primary, size: 20)
          : null,
      onTap: onTap,
    );
  }
}

class _IntervalPickerSheet extends StatelessWidget {
  final int currentValue;
  final void Function(int) onSelected;

  const _IntervalPickerSheet({
    required this.currentValue,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Rest Ping Interval',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            for (final opt in SettingsState.restPingIntervalOptions)
              ListTile(
                title: Text(
                  opt.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: opt.value == currentValue
                        ? theme.colorScheme.primary
                        : OmniTheme.colors.textDominant,
                    fontWeight: opt.value == currentValue
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
                trailing: opt.value == currentValue
                    ? Icon(
                        Icons.check,
                        color: theme.colorScheme.primary,
                        size: 20,
                      )
                    : null,
                onTap: () => onSelected(opt.value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _MeasurementsSection extends StatelessWidget {
  final SettingsState settingsState;
  final ThemeData theme;
  final double? userHeightCm;

  const _MeasurementsSection({
    required this.settingsState,
    required this.theme,
    this.userHeightCm,
  });

  @override
  Widget build(BuildContext context) {
    return OmniSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          _SurfaceDivider(theme: theme),
          _SettingsRow(
            label: 'Height',
            subtitle: 'Used on the profile and in the height log sheet',
            trailing: _SegmentedToggle(
              groupValue: UnitFormatter.normalizeHeightUnit(
                settingsState.preferredHeightUnit,
              ),
              options: [
                _SegmentedOption(
                  value: 'cm',
                  label: UnitFormatter.heightLabelForUnit('cm'),
                ),
                _SegmentedOption(
                  value: 'ftin',
                  label: UnitFormatter.heightLabelForUnit('ftin'),
                ),
              ],
              onChanged: settingsState.setPreferredHeightUnit,
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
                      color: OmniTheme.colors.textMuted,
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
                      const SizedBox(width: 6),
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
                      const SizedBox(width: 6),
                      Expanded(
                        child: _PreviewValue(
                          icon: Icons.height,
                          value: userHeightCm != null
                              ? UnitFormatter.formatHeight(
                                  userHeightCm!,
                                  settingsState,
                                )
                              : '—',
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

class _WorkoutSection extends StatelessWidget {
  final SettingsState settingsState;

  const _WorkoutSection({required this.settingsState});

  @override
  Widget build(BuildContext context) {
    return OmniSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsRow(
            label: 'Feeling Survey',
            subtitle: 'Ask how the workout felt after finishing',
            trailing: Switch(
              value: settingsState.showFeelingSurvey,
              onChanged: settingsState.setShowFeelingSurvey,
            ),
          ),
        ],
      ),
    );
  }
}

// ── HEALTH ────────────────────────────────────────────────────────────────

/// Phone health-store integration: two independent, off-by-default
/// toggles. A denied OS permission is shown as the off switch plus a
/// plain-language notice that points at the system settings, so the app
/// stays fully usable without the integration (S-005).
class _HealthSection extends StatelessWidget {
  final SettingsState settingsState;

  const _HealthSection({required this.settingsState});

  @override
  Widget build(BuildContext context) {
    final writeState = settingsState.healthWriteWorkouts;
    final readState = settingsState.healthReadBodyWeight;

    return OmniSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsRow(
            label: 'Write workouts',
            subtitle:
                'Adds finished workouts to Apple Health / Health Connect so '
                'your other apps and wearables can see them. Nothing is '
                'written until you turn this on.',
            trailing: Switch(
              key: healthWriteToggleKey,
              value: writeState == HealthToggleState.on,
              onChanged: settingsState.setHealthWriteWorkoutsEnabled,
            ),
          ),
          if (writeState == HealthToggleState.permissionDenied)
            const _HealthDeniedNotice(),
          _SurfaceDivider(theme: Theme.of(context)),
          _SettingsRow(
            label: 'Read body weight',
            subtitle:
                'Shows body weight recorded by other apps and wearables in '
                'your measurement history. Only weight is read.',
            trailing: Switch(
              key: healthReadToggleKey,
              value: readState == HealthToggleState.on,
              onChanged: settingsState.setHealthReadBodyWeightEnabled,
            ),
          ),
          if (readState == HealthToggleState.permissionDenied)
            const _HealthDeniedNotice(),
        ],
      ),
    );
  }
}

class _HealthDeniedNotice extends StatelessWidget {
  const _HealthDeniedNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Permission was denied. Allow access in your phone settings '
              'to turn this on.',
              style: theme.textTheme.labelMedium?.copyWith(
                color: OmniTheme.colors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            style: ButtonStyle(
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    OmniTheme.buttonUtilityRadius,
                  ),
                ),
              ),
            ),
            onPressed: AppSettings.openAppSettings,
            child: const Text('Open settings'),
          ),
        ],
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
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: OmniTheme.colors.textDominant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: OmniTheme.colors.textMuted,
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
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w600,
                    color: isActive
                        ? Colors.black
                        : OmniTheme.colors.textSecondary,
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 13,
          color: theme.colorScheme.primary.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: theme.textTheme.bodySmall?.copyWith(
              color: OmniTheme.colors.textDominant,
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
