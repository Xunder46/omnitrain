import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/constants/profile_measurements.dart';
import '../../core/utils/unit_formatter.dart';
import '../../data/models/models.dart';
import '../../state/profile/profile_state.dart';
import '../../state/settings/settings_state.dart';
import '../../widgets/layout/omni_surface.dart';
import '../../widgets/layout/omni_back_header.dart';
import '../../widgets/inputs/numeric_field_with_done_bar.dart';
import 'widgets/measurement_history_chart_sheet.dart';
import 'widgets/profile_avatar_image_stub.dart'
    if (dart.library.io) 'widgets/profile_avatar_image_io.dart';

class ProfileScreen extends StatefulWidget {
  final ProfileState profileState;
  final SettingsState settingsState;

  const ProfileScreen({
    super.key,
    required this.profileState,
    required this.settingsState,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.profileState.loadProfile();
      await widget.profileState.loadLatestMeasurements(
        ProfileMeasurements.additional.map((definition) => definition.type),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: const OmniBackHeader(title: 'Profile'),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.profileState,
          builder: (context, _) {
            final profile = widget.profileState.profile;
            if (widget.profileState.isLoading && profile == null) {
              return const Center(child: CircularProgressIndicator());
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                _buildIdentitySection(theme, profile),
                const SizedBox(height: 24),
                _buildMeasurementSection(
                  theme,
                  title: 'MEASUREMENTS',
                  definitions: ProfileMeasurements.primary,
                ),
                const SizedBox(height: 14),
                _buildMeasurementSection(
                  theme,
                  definitions: ProfileMeasurements.additional,
                ),
                if (widget.profileState.error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    widget.profileState.error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildIdentitySection(ThemeData theme, UserProfile? profile) {
    return OmniSurface(
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            GestureDetector(
              onTap: _showAvatarOptions,
              child: Semantics(
                button: true,
                label: 'Edit avatar',
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.surface.withOpacity(0.4),
                    border: Border.all(
                      color: OmniTheme.surfaceBorderColor,
                      width: OmniTheme.surfaceBorderWidth,
                    ),
                  ),
                  child: ClipOval(
                    child: profile?.avatarPath != null
                        ? ProfileAvatarImage(
                            path: profile!.avatarPath!,
                            fallback: _buildAvatarFallback(theme),
                          )
                        : _buildAvatarFallback(theme),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _showDisplayNameDialog,
                borderRadius: BorderRadius.circular(
                  OmniTheme.buttonUtilityRadius,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Column(
                      children: [
                        Text(
                          profile?.displayName?.trim().isNotEmpty == true
                              ? profile!.displayName!
                              : 'Add your name',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color:
                                profile?.displayName?.trim().isNotEmpty == true
                                ? OmniTheme.textPrimary
                                : OmniTheme.textSecondary.withOpacity(0.7),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                        if (profile?.displayName?.trim().isNotEmpty !=
                            true) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Tap to edit',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: OmniTheme.textSecondary.withOpacity(0.7),
                              letterSpacing: 2.0,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarFallback(ThemeData theme) {
    return Center(
      child: Icon(Icons.person, size: 56, color: theme.colorScheme.primary),
    );
  }

  Widget _buildMeasurementSection(
    ThemeData theme, {
    String? title,
    required List<ProfileMeasurementDefinition> definitions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null && title.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              title,
              style: theme.textTheme.labelSmall?.copyWith(
                color: OmniTheme.textSecondary.withOpacity(0.7),
                letterSpacing: 2.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        for (var index = 0; index < definitions.length; index++) ...[
          _MeasurementRow(
            definition: definitions[index],
            latestEntry:
                widget.profileState.latestMeasurements[definitions[index].type],
            settingsState: widget.settingsState,
            onTap: () => _showMeasurementHistory(definitions[index]),
            onAddTap: () => _showMeasurementLogSheet(definitions[index]),
          ),
          if (index < definitions.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  Future<void> _showAvatarOptions() async {
    final profile = widget.profileState.profile;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: OmniSurface(
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SheetOption(
                    icon: Icons.photo_camera_outlined,
                    label: 'Take Photo',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _pickAvatar(ImageSource.camera);
                    },
                  ),
                  _SheetOption(
                    icon: Icons.photo_library_outlined,
                    label: 'Choose from Gallery',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _pickAvatar(ImageSource.gallery);
                    },
                  ),
                  _SheetOption(
                    icon: Icons.delete_outline,
                    label: 'Remove Photo',
                    enabled: profile?.avatarPath != null,
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await widget.profileState.updateAvatarPath(null);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final pickedImage = await _imagePicker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 1600,
      );
      if (pickedImage == null) return;
      // Browser picking can work on web, but avatarPath is a native-first
      // contract and cannot reliably replay a persisted local selection there.
      if (kIsWeb) {
        _showMessage(
          'Photo selection works on web, but avatar persistence is not supported there yet.',
        );
        return;
      }
      await widget.profileState.updateAvatarPath(pickedImage.path);
    } catch (e) {
      _showMessage('Failed to update avatar: $e');
    }
  }

  Future<void> _showDisplayNameDialog() async {
    final controller = TextEditingController(
      text: widget.profileState.profile?.displayName ?? '',
    );

    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit Name'),
          content: TextField(
            textCapitalization: TextCapitalization.words,
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Enter your display name',
            ),
          ),
          actions: [
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
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: ButtonStyle(
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      OmniTheme.buttonUtilityRadius,
                    ),
                  ),
                ),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (value == null) return;

    try {
      await widget.profileState.updateDisplayName(value);
    } catch (e) {
      _showMessage('Failed to update name: $e');
    }
  }

  Future<void> _showMeasurementLogSheet(
    ProfileMeasurementDefinition definition,
  ) async {
    final latestEntry = widget.profileState.latestMeasurements[definition.type];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _MeasurementLogSheet(
          profileState: widget.profileState,
          definition: definition,
          latestEntry: latestEntry,
          settingsState: widget.settingsState,
        );
      },
    );
  }

  Future<void> _showMeasurementHistory(
    ProfileMeasurementDefinition definition,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return MeasurementHistoryChartSheet(
          profileState: widget.profileState,
          definition: definition,
          settingsState: widget.settingsState,
          onLogNew: () => _showMeasurementLogSheet(definition),
        );
      },
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _MeasurementRow extends StatelessWidget {
  final ProfileMeasurementDefinition definition;
  final BodyMeasurementEntry? latestEntry;
  final SettingsState settingsState;
  final VoidCallback onTap;
  final VoidCallback onAddTap;

  const _MeasurementRow({
    required this.definition,
    required this.latestEntry,
    required this.settingsState,
    required this.onTap,
    required this.onAddTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String valueLabel;
    if (latestEntry != null) {
      if (latestEntry!.unitId == 'unit-kg') {
        valueLabel = UnitFormatter.formatWeight(
          latestEntry!.value,
          settingsState,
        );
      } else {
        final label = ProfileMeasurements.unitLabelFor(latestEntry!.unitId);
        valueLabel =
            '${ProfileMeasurements.formatValue(latestEntry!.value)} $label';
      }
    } else {
      valueLabel = '—';
    }

    return OmniSurface(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(OmniTheme.surfaceBorderRadius),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      definition.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: OmniTheme.textSecondary.withOpacity(0.9),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: Text(
                      valueLabel,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: latestEntry != null
                            ? OmniTheme.textPrimary
                            : OmniTheme.textSecondary.withOpacity(0.65),
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: OmniTheme.buttonIconSize,
                    height: OmniTheme.buttonIconSize,
                    child: OutlinedButton(
                      style: ButtonStyle(
                        side: WidgetStateProperty.all(
                          BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        foregroundColor: WidgetStateProperty.all(
                          Theme.of(context).colorScheme.primary,
                        ),
                        shape: WidgetStateProperty.all(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              OmniTheme.buttonIconRadius,
                            ),
                          ),
                        ),
                      ),
                      onPressed: onAddTap,
                      child: const Icon(Icons.add),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MeasurementLogSheet extends StatefulWidget {
  final ProfileState profileState;
  final ProfileMeasurementDefinition definition;
  final BodyMeasurementEntry? latestEntry;
  final SettingsState settingsState;

  const _MeasurementLogSheet({
    required this.profileState,
    required this.definition,
    required this.latestEntry,
    required this.settingsState,
  });

  @override
  State<_MeasurementLogSheet> createState() => _MeasurementLogSheetState();
}

class _MeasurementLogSheetState extends State<_MeasurementLogSheet> {
  late final TextEditingController _valueController;
  bool _isSaving = false;
  String? _valueError;

  @override
  void initState() {
    super.initState();
    _valueController = TextEditingController(
      text: widget.latestEntry != null
          ? widget.definition.unitId == 'unit-kg'
                ? UnitFormatter.formatWeightValue(
                    widget.latestEntry!.value,
                    widget.settingsState,
                  )
                : ProfileMeasurements.formatValue(widget.latestEntry!.value)
          : '',
    );
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, viewInsets.bottom + 12),
      child: OmniSurface(
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Log ${widget.definition.label}',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: OmniTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                NumericFieldWithDoneBar(
                  controller: _valueController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: widget.definition.unitId == 'unit-kg'
                        ? 'Value (${UnitFormatter.weightLabel(widget.settingsState)})'
                        : 'Value (${widget.definition.unitLabel})',
                    errorText: _valueError,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: OmniTheme.buttonPrimaryHeight,
                  child: FilledButton(
                    style: ButtonStyle(
                      shape: WidgetStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            OmniTheme.buttonBorderRadius,
                          ),
                        ),
                      ),
                    ),
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final value = double.tryParse(_valueController.text.trim());
    if (value == null) {
      setState(() {
        _valueError = 'Enter a valid number.';
      });
      return;
    }

    // Reject zero and negative values explicitly.
    if (value <= 0) {
      setState(() {
        _valueError = 'Enter a value greater than 0.';
      });
      return;
    }

    // Per-measurement validation range check.
    final weightUnit = widget.settingsState.preferredWeightUnit;
    final range = ProfileMeasurements.validationRangeFor(
      widget.definition.type,
      weightUnit,
    );
    final unitLabel = ProfileMeasurements.validationUnitLabel(
      widget.definition.type,
      weightUnit,
    );
    if (value < range.min || value > range.max) {
      final minLabel = range.min == range.min.truncateToDouble()
          ? range.min.toInt().toString()
          : range.min.toStringAsFixed(1);
      final maxLabel = range.max == range.max.truncateToDouble()
          ? range.max.toInt().toString()
          : range.max.toStringAsFixed(1);
      setState(() {
        _valueError =
            'Enter a value between $minLabel and $maxLabel $unitLabel.';
      });
      return;
    }

    // Silently truncate to one decimal place (no rounding).
    final truncated = (value * 10).truncate() / 10;

    setState(() {
      _isSaving = true;
      _valueError = null;
    });

    try {
      final canonicalValue = widget.definition.unitId == 'unit-kg'
          ? UnitFormatter.toCanonicalWeight(truncated, widget.settingsState)
          : truncated;
      await widget.profileState.logMeasurement(
        widget.definition.type,
        canonicalValue,
        widget.definition.unitId,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save entry: $e')));
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }
}

class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  const _SheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(icon, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: OmniTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
