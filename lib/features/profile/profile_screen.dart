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
import '../../widgets/layout/omni_card_header.dart';
import '../../widgets/inputs/numeric_field_with_done_bar.dart';
import 'widgets/measurement_history_chart_sheet.dart';
import 'widgets/measurement_sparkline.dart';
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
                      color: OmniTheme.colors.surfaceBorder,
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
                                ? OmniTheme.colors.textDominant
                                : OmniTheme.colors.textSecondary.withOpacity(0.7),
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
                              color: OmniTheme.colors.textSecondary.withOpacity(0.7),
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
    required List<ProfileMeasurementDefinition> definitions,
  }) {
    // Per the unified card-and-header plan (Phase 4): each measurement
    // owns its own [OmniCardHeader] (title = measurement label) above
    // an [OmniSurface]. Per the user-driven refinement (A16): only
    // the section eyebrows (`MEASUREMENTS` / `ADDITIONAL`) were
    // extracted — the card body's column structure stays intact. The
    // card body is a 3-section row: `[chart rectangle | current value
    // | + button]`. Tapping the chart opens the existing history
    // sheet; tapping the `+` button opens the existing log sheet.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < definitions.length; index++) ...[
          OmniCardHeader(title: definitions[index].label.toUpperCase()),
          OmniSurface(
            padding: const EdgeInsets.fromLTRB(5, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: MeasurementSparkline(
                    definition: definitions[index],
                    profileState: widget.profileState,
                    settingsState: widget.settingsState,
                    onTap: () => _showMeasurementHistory(definitions[index]),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  key: const Key('measurement_value'),
                  width: 90,
                  child: Text(
                    _formatMeasurementValue(
                      widget.profileState
                          .latestMeasurements[definitions[index].type],
                      widget.settingsState,
                    ),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: widget.profileState.latestMeasurements[
                                  definitions[index].type] !=
                              null
                          ? OmniTheme.colors.textDominant
                          : OmniTheme.colors.textSecondary.withOpacity(0.65),
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                _buildMeasurementAddButton(
                  theme: theme,
                  onPressed: () =>
                      _showMeasurementLogSheet(definitions[index]),
                ),
              ],
            ),
          ),
          if (index < definitions.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  /// Format the measurement's current value for display in the card
  /// body's middle section. Extracted from the pre-Phase-4
  /// `_MeasurementRow` so the chart-rectangle column and the value
  /// column share the formatting logic.
  String _formatMeasurementValue(
    BodyMeasurementEntry? latestEntry,
    SettingsState settingsState,
  ) {
    if (latestEntry == null) return '—';
    if (latestEntry.unitId == 'unit-kg') {
      return UnitFormatter.formatWeight(latestEntry.value, settingsState);
    }
    final label = ProfileMeasurements.unitLabelFor(latestEntry.unitId);
    return '${ProfileMeasurements.formatValue(latestEntry.value)} $label';
  }

  /// 60 × 60 dp outlined icon button used as the "+" affordance in
  /// the card body of each measurement row (Phase 4 review
  /// refinement: lives in the card body alongside the chart and value
  /// columns; per A16, the [OmniCardHeader] is title-only).
  Widget _buildMeasurementAddButton({
    required ThemeData theme,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: OmniTheme.buttonIconSize,
      height: OmniTheme.buttonIconSize,
      child: OutlinedButton(
        style: ButtonStyle(
          side: WidgetStateProperty.all(
            BorderSide(color: theme.colorScheme.primary),
          ),
          foregroundColor: WidgetStateProperty.all(
            theme.colorScheme.primary,
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                OmniTheme.buttonIconRadius,
              ),
            ),
          ),
        ),
        onPressed: onPressed,
        child: const Icon(Icons.add),
      ),
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
      // Web has no persistent file API; mirror the food-form
      // message (D-5: web persistence is intentionally out of
      // scope for this iteration).
      if (kIsWeb) {
        _showMessage(
          'Photo selection works on web, but avatar persistence is not supported there yet.',
        );
        return;
      }
      // D-1..D-9: copy the picked file into the managed directory
      // before saving to the data layer. The picked file lives in
      // a temporary cache the OS may purge, so we replace it with
      // a stable app-owned path. On failure, no state mutation
      // happens (D-6: partial files are cleaned up by the service).
      final persistedPath = await widget.profileState.imageStorage
          .persistPickedImage(pickedImage);
      await widget.profileState.updateAvatarPath(persistedPath);
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
                    color: OmniTheme.colors.textDominant,
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
                        color: OmniTheme.colors.textDominant,
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
