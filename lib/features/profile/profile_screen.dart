import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/omni_theme.dart';
import '../../core/constants/profile_measurements.dart';
import '../../core/navigation/omni_navigator.dart';
import '../../core/utils/unit_formatter.dart';
import '../../data/models/models.dart';
import '../../state/profile/profile_state.dart';
import '../../state/settings/settings_state.dart';
import '../../widgets/layout/omni_surface.dart';
import '../../widgets/layout/omni_back_header.dart';
import '../../widgets/layout/omni_card_header.dart';
import '../../widgets/inputs/numeric_field_with_done_bar.dart';
import 'widgets/avatar_crop_sheet.dart';
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
      // Height left the charted column (it now lives in the identity
      // area) so the charted-column load only pulls `additional`.
      // Height still needs to be loaded into the latest-measurements
      // cache so the identity area can read it without an extra
      // round-trip — load it explicitly here.
      await widget.profileState.loadLatestMeasurements(<String>{
        ...ProfileMeasurements.additional.map((d) => d.type),
        'height',
      });
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
          // The card value column is unit-aware (cm vs feet/inches
          // for height; kg vs lbs for bodyweight), so the screen
          // rebuilds on either a profile data change or a settings
          // change to keep the display path live.
          listenable: Listenable.merge([
            widget.profileState,
            widget.settingsState,
          ]),
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
                // Single charted column. The cleanup pass dropped the
                // primary/additional split: height moved into the
                // identity area, bodyweight moved to the top of the
                // composition-first ordering, and lean mass renders
                // a read-only computed row alongside the manual ones.
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
    // Compact horizontal header — avatar on the left, name + height
    // stacked on the right, vertically centered against the avatar.
    // No [OmniSurface] chrome around the block: the gradient shows
    // through behind it, recovering vertical space for the charted
    // measurement cards below. The avatar stays at its current
    // 200 × 200 size (floor: 180) — gaining space by shrinking the
    // avatar is explicitly out of scope.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _showAvatarOptions,
          child: Semantics(
            button: true,
            label: 'Edit avatar',
            child: Container(
              key: const Key('profile_identity_avatar'),
              width: 200,
              height: 200,
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
                        reference: profile!.avatarPath!,
                        imageStorage: widget.profileState.imageStorageOrNull,
                        fallback: _buildAvatarFallback(theme),
                      )
                    : _buildAvatarFallback(theme),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildIdentityNameRow(theme, profile),
              const SizedBox(height: 2),
              _buildIdentityHeightRow(theme),
            ],
          ),
        ),
      ],
    );
  }

  /// Name tap target in the identity area. The whole row opens the
  /// existing name editor dialog (unchanged behavior). Iteration 2:
  /// dropped `ConstrainedBox(minHeight: 48)` + vertical padding so the
  /// InkWell wraps the text tightly, and bumped typography from
  /// `headlineSmall` to `headlineMedium` so the right column holds its
  /// own against the avatar visually.
  Widget _buildIdentityNameRow(ThemeData theme, UserProfile? profile) {
    final hasName = profile?.displayName?.trim().isNotEmpty == true;
    final nameText = hasName ? profile!.displayName!.trim() : 'Add your name';
    final words = nameText.split(' ');
    final textColor = hasName
        ? OmniTheme.colors.textDominant
        : OmniTheme.colors.textSecondary.withOpacity(0.7);

    // Use a fixed base font size
    const baseFontSize = 24.0;
    const maxCharsPerLine = 6.0;

    // Calculate font size based on the longest word so all words are consistent
    final longestWordLength = words
        .map((w) => w.length)
        .reduce((a, b) => a > b ? a : b);
    final fontSize = longestWordLength <= maxCharsPerLine
        ? baseFontSize
        : (baseFontSize * maxCharsPerLine / longestWordLength).clamp(
            14.0,
            baseFontSize,
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showDisplayNameDialog,
        borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: words.map((word) {
              return Text(
                word,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: textColor,
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  /// Compact, tappable height line rendered as a secondary subtitle
  /// under the name in the identity area. Height is effectively a
  /// constant — charting it over time is a flat line — so it lives
  /// in the identity area as an editable value, left-aligned with
  /// the name. The whole line is one tap target (key
  /// `profile_identity_height_value`); tapping opens [_HeightDialog],
  /// which writes through the existing
  /// `BodyMeasurementEntry(type='height')` repository path so the
  /// Settings height preview keeps working without migration.
  ///
  /// No leading icon: the prior [Icons.height] arrow cue read as a
  /// resize/sort control. The line is already tappable; an icon
  /// added nothing.
  ///
  /// Iteration 2: dropped `ConstrainedBox(minHeight: 36)` + vertical
  /// padding so the InkWell wraps the text tightly, matching the
  /// name row's tight layout. Together with the 2 dp gap in the
  /// parent column, name + height read as a single stacked pair.
  Widget _buildIdentityHeightRow(ThemeData theme) {
    final heightCm = widget.profileState.latestHeightCm;
    final hasHeight = heightCm != null;
    final display = hasHeight
        ? UnitFormatter.formatHeight(heightCm, widget.settingsState)
        : 'Add height';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('profile_identity_height_value'),
        onTap: _showHeightDialog,
        borderRadius: BorderRadius.circular(OmniTheme.buttonUtilityRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            display,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: hasHeight
                  ? OmniTheme.colors.textSecondary
                  : OmniTheme.colors.textSecondary.withOpacity(0.7),
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
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
    //
    // Cleanup-pass carve-out: `lean_mass` renders a read-only
    // computed row (label + value, no chart sparkline, no `+`).
    // The card chrome (header + surface) is unchanged; only the
    // card body's contents differ. Every other row keeps its
    // original chart + value + add-button row geometry.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < definitions.length; index++) ...[
          OmniCardHeader(title: definitions[index].label.toUpperCase()),
          if (definitions[index].type == 'lean_mass')
            _buildLeanMassCard(theme)
          else
            OmniSurface(
              // Bodyweight is the only manual-log measurement whose
              // card body has a dedicated Key in this pass — the
              // cleanup re-keyed the formerly-height card (height
              // left the column) so widget tests can scope their
              // assertions to a stable identifier. Lean Mass has
              // its own dedicated card (see `_buildLeanMassCard`).
              key: definitions[index].type == 'bodyweight'
                  ? const Key('profile_bodyweight_card')
                  : null,
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
                        widget
                            .profileState
                            .latestMeasurements[definitions[index].type],
                        widget.settingsState,
                      ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color:
                            widget
                                    .profileState
                                    .latestMeasurements[definitions[index]
                                    .type] !=
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

  /// Lean Mass card — read-only computed value, no manual log
  /// button, no sparkline. Three independently-typed fields that
  /// are mathematically linked (body weight, body fat %, lean mass)
  /// will inevitably contradict each other, so the cleanup pass
  /// derives lean mass from the other two and removes the manual
  /// entry path entirely. The card chrome (header + surface + row
  /// height) matches its peers so the column stays visually
  /// uniform — only the card body's contents differ.
  Widget _buildLeanMassCard(ThemeData theme) {
    final computedKg = widget.profileState.computedLeanMassKg;
    final hasValue = computedKg != null;
    final display = hasValue
        ? UnitFormatter.formatWeight(computedKg, widget.settingsState)
        : '—';
    return OmniSurface(
      key: const Key('profile_lean_mass_card'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Computed',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: OmniTheme.colors.textMuted,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                // Derivation formula. No `maxLines` / `overflow`
                // constraint — the formula wraps onto additional
                // lines as needed so the full expression displays
                // (a half-shown formula like "Body weight × (1 …"
                // reads as broken).
                Text(
                  'Body weight × \n(1 − body fat)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: OmniTheme.colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            key: const Key('measurement_value'),
            width: 90,
            child: Text(
              display,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                color: hasValue
                    ? OmniTheme.colors.textDominant
                    : OmniTheme.colors.textSecondary.withOpacity(0.65),
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Spacer sized to match the manual-log card's right-edge
          // + button so the value column lines up across rows.
          const SizedBox(width: OmniTheme.buttonIconSize + 12),
        ],
      ),
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
    if (latestEntry.measurementType == 'height') {
      // Height is the only measurement with a unit-aware compound
      // display path; the rest use the bare "<value> <unit>" form.
      return UnitFormatter.formatHeight(latestEntry.value, settingsState);
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
          foregroundColor: WidgetStateProperty.all(theme.colorScheme.primary),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(OmniTheme.buttonIconRadius),
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
      await handlePickedImage(pickedImage);
    } catch (e) {
      _showMessage('Failed to update avatar: $e');
    }
  }

  /// Read a picked `XFile`'s bytes, route them through the avatar
  /// crop step, and on confirm persist the cropped PNG bytes
  /// through the existing [ProfileState.updateAvatarPath] path.
  ///
  /// Split out of [_pickAvatar] for two reasons:
  ///   * It mirrors [FoodForm.handlePickedImage] so tests can
  ///     bypass the `image_picker` platform channel by invoking
  ///     this entry point directly with a real `XFile`.
  ///   * It centralises the read → crop → persist pipeline so
  ///     both camera and gallery picks share one implementation.
  ///     The picker only differs in [ImageSource] — the bytes
  ///     flow the same way from there.
  ///
  /// **Cancel**: if the user dismisses the crop sheet, no file is
  /// written under the managed directory and
  /// `state.profile.avatarPath` is untouched. The picker temp
  /// file lives outside the managed dir and is left to the OS to
  /// purge (it is never copied in).
  @visibleForTesting
  Future<void> handlePickedImage(XFile picked) async {
    final bytes = await picked.readAsBytes();
    await handlePickedBytes(bytes);
  }

  /// Push the [AvatarCropSheet] for already-read bytes. On
  /// confirm, the cropped PNG bytes are persisted through the
  /// existing [ProfileState.updateAvatarPath] path.
  ///
  /// Split from [handlePickedImage] so tests can:
  ///   1. Read the picked bytes themselves via
  ///      `tester.runAsync(() => picked.readAsBytes())`.
  ///   2. Call this method with the resulting [Uint8List].
  /// This avoids awaiting the read inside the test's `runAsync`
  /// block (the read is real I/O; the navigator push is async
  /// over the test zone's pump cycle).
  @visibleForTesting
  Future<void> handlePickedBytes(Uint8List bytes) async {
    final cropped = await _showCropSheet(bytes);
    if (cropped == null) return; // user cancelled
    await handleCroppedBytes(cropped);
  }

  /// Persist already-cropped bytes through the existing
  /// [ProfileState.updateAvatarPath] path. Split out of
  /// [handlePickedImage] / [handlePickedBytes] so tests can
  /// bypass both the picker and the crop sheet (e.g. for
  /// service-level wiring assertions — see
  /// `test/avatar_crop_test.dart`).
  @visibleForTesting
  Future<void> handleCroppedBytes(Uint8List bytes) async {
    final persistedPath = await widget.profileState.imageStorage
        .persistImageBytes(bytes);
    await widget.profileState.updateAvatarPath(persistedPath);
  }

  /// Push the [AvatarCropSheet] as a full-screen dialog. Returns
  /// the captured PNG bytes on confirm, or `null` on cancel.
  ///
  /// Routed through `OmniNavigator.push(..., fullscreenDialog:
  /// true)` rather than a raw `MaterialPageRoute` so the route
  /// fully occludes the underlying ProfileScreen during the
  /// transition (avoids the bleed-through that happens when
  /// every Scaffold is transparent and `opaque == false`). This
  /// is the same pattern every other modal screen in the app
  /// uses — see `docs/navigation_and_screens.md`
  /// and `lib/core/navigation/omni_route.dart`.
  Future<Uint8List?> _showCropSheet(Uint8List bytes) {
    return OmniNavigator.push<Uint8List>(
      context,
      (_) => AvatarCropSheet(imageBytes: bytes),
      fullscreenDialog: true,
    );
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

  /// Identity-area height editor. Mirrors the cm/ftin input shape
  /// of the existing height log sheet so the same canonical cm
  /// storage path is used — but as a compact dialog (no full
  /// bottom sheet, no chart sparkline, no `Log` header chrome)
  /// because height is no longer a charted measurement.
  Future<void> _showHeightDialog() async {
    final latestCm = widget.profileState.latestHeightCm;
    final saved = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return _HeightDialog(
          settingsState: widget.settingsState,
          initialCm: latestCm,
        );
      },
    );
    if (saved == null) return;
    try {
      await widget.profileState.updateHeight(saved);
    } catch (e) {
      _showMessage('Failed to update height: $e');
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
  // Height in ftin mode presents two separate inputs; the existing
  // single field above is unused on that path but stays wired up
  // for the cm/other-measurement path so the rest of the sheet
  // logic is unchanged.
  late final TextEditingController _feetController;
  late final TextEditingController _inchesController;
  bool _isSaving = false;
  String? _valueError;

  bool get _isHeightFtinMode =>
      widget.definition.type == 'height' &&
      UnitFormatter.normalizeHeightUnit(
            widget.settingsState.preferredHeightUnit,
          ) ==
          'ftin';

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
    String feetText = '';
    String inchesText = '';
    if (widget.latestEntry != null && _isHeightFtinMode) {
      final compound = UnitFormatter.cmToFeetInches(widget.latestEntry!.value);
      feetText = compound.feet.toString();
      inchesText = compound.inches.toString();
    }
    _feetController = TextEditingController(text: feetText);
    _inchesController = TextEditingController(text: inchesText);
  }

  @override
  void dispose() {
    _valueController.dispose();
    _feetController.dispose();
    _inchesController.dispose();
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
                if (_isHeightFtinMode)
                  _buildFeetInchesInputs()
                else
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

  // Side-by-side feet and inches inputs. The inches field is bound
  // to whole integers 0-11 by the save path's validation.
  Widget _buildFeetInchesInputs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: NumericFieldWithDoneBar(
                controller: _feetController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Feet'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: NumericFieldWithDoneBar(
                controller: _inchesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Inches'),
              ),
            ),
          ],
        ),
        if (_valueError != null) ...[
          const SizedBox(height: 8),
          Text(
            _valueError!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _save() async {
    if (_isHeightFtinMode) {
      await _saveHeightFtin();
      return;
    }
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
    final heightUnit = widget.settingsState.preferredHeightUnit;
    final range = ProfileMeasurements.validationRangeFor(
      widget.definition.type,
      weightUnit,
      heightUnit: heightUnit,
    );
    final unitLabel = ProfileMeasurements.validationUnitLabel(
      widget.definition.type,
      weightUnit,
      heightUnit: heightUnit,
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

  // Height in ftin mode: read feet and inches separately, validate
  // both fields and the combined total-inches value, then store the
  // canonical cm value with `unitId='unit-cm'`. The compound input
  // ensures the same physical range as the cm path is preserved.
  Future<void> _saveHeightFtin() async {
    final feetText = _feetController.text.trim();
    final inchesText = _inchesController.text.trim();
    final feet = int.tryParse(feetText);
    final inches = int.tryParse(inchesText);

    if (feet == null || inches == null) {
      setState(() {
        _valueError = 'Enter a valid feet and inches value.';
      });
      return;
    }
    if (feet < 0 || inches < 0) {
      setState(() {
        _valueError = 'Enter a value greater than 0.';
      });
      return;
    }
    if (inches > 11) {
      setState(() {
        _valueError = 'Enter a value between 0 and 11 inches.';
      });
      return;
    }

    final totalInches = feet * 12 + inches;
    final weightUnit = widget.settingsState.preferredWeightUnit;
    final heightUnit = widget.settingsState.preferredHeightUnit;
    final range = ProfileMeasurements.validationRangeFor(
      'height',
      weightUnit,
      heightUnit: heightUnit,
    );
    final unitLabel = ProfileMeasurements.validationUnitLabel(
      'height',
      weightUnit,
      heightUnit: heightUnit,
    );
    if (totalInches < range.min || totalInches > range.max) {
      final minLabel = UnitFormatter.formatFeetInches(
        range.min.toInt() ~/ 12,
        range.min.toInt() % 12,
      );
      final maxLabel = UnitFormatter.formatFeetInches(
        range.max.toInt() ~/ 12,
        range.max.toInt() % 12,
      );
      setState(() {
        _valueError =
            'Enter a value between $minLabel and $maxLabel $unitLabel.';
      });
      return;
    }

    final canonicalCm = UnitFormatter.toCanonicalHeightFeetInches(feet, inches);

    setState(() {
      _isSaving = true;
      _valueError = null;
    });

    try {
      await widget.profileState.logMeasurement(
        'height',
        canonicalCm,
        'unit-cm',
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

/// Identity-area height editor. Mirrors the cm/ftin input shape
/// of the height log sheet (see [_MeasurementLogSheet]) so the
/// same canonical cm storage path is used — but as a compact
/// dialog instead of a full bottom sheet because height is no
/// longer a charted measurement. Returns the canonical-cm value
/// via `Navigator.pop` on Save; returns null on Cancel or on a
/// validation failure (the dialog stays open with an inline
/// error in that case).
class _HeightDialog extends StatefulWidget {
  final SettingsState settingsState;
  final double? initialCm;

  const _HeightDialog({required this.settingsState, this.initialCm});

  @override
  State<_HeightDialog> createState() => _HeightDialogState();
}

class _HeightDialogState extends State<_HeightDialog> {
  late final TextEditingController _valueController;
  late final TextEditingController _feetController;
  late final TextEditingController _inchesController;
  String? _valueError;

  bool get _isFtinMode =>
      UnitFormatter.normalizeHeightUnit(
        widget.settingsState.preferredHeightUnit,
      ) ==
      'ftin';

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCm;
    if (initial != null && _isFtinMode) {
      final compound = UnitFormatter.cmToFeetInches(initial);
      _feetController = TextEditingController(text: '${compound.feet}');
      _inchesController = TextEditingController(text: '${compound.inches}');
      _valueController = TextEditingController();
    } else {
      _valueController = TextEditingController(
        text: initial != null ? ProfileMeasurements.formatValue(initial) : '',
      );
      _feetController = TextEditingController();
      _inchesController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    _feetController.dispose();
    _inchesController.dispose();
    super.dispose();
  }

  void _save() {
    final weightUnit = widget.settingsState.preferredWeightUnit;
    final heightUnit = widget.settingsState.preferredHeightUnit;
    if (_isFtinMode) {
      final feet = int.tryParse(_feetController.text.trim());
      final inches = int.tryParse(_inchesController.text.trim());
      if (feet == null || inches == null) {
        setState(() {
          _valueError = 'Enter a valid feet and inches value.';
        });
        return;
      }
      if (feet < 0 || inches < 0) {
        setState(() {
          _valueError = 'Enter a value greater than 0.';
        });
        return;
      }
      if (inches > 11) {
        setState(() {
          _valueError = 'Enter a value between 0 and 11 inches.';
        });
        return;
      }
      final totalInches = feet * 12 + inches;
      final range = ProfileMeasurements.validationRangeFor(
        'height',
        weightUnit,
        heightUnit: heightUnit,
      );
      if (totalInches < range.min || totalInches > range.max) {
        setState(() {
          _valueError = 'Enter a height within the allowed range.';
        });
        return;
      }
      Navigator.of(
        context,
      ).pop(UnitFormatter.toCanonicalHeightFeetInches(feet, inches));
      return;
    }
    final value = double.tryParse(_valueController.text.trim());
    if (value == null) {
      setState(() {
        _valueError = 'Enter a valid number.';
      });
      return;
    }
    if (value <= 0) {
      setState(() {
        _valueError = 'Enter a value greater than 0.';
      });
      return;
    }
    final range = ProfileMeasurements.validationRangeFor(
      'height',
      weightUnit,
      heightUnit: heightUnit,
    );
    if (value < range.min || value > range.max) {
      setState(() {
        _valueError = 'Enter a height within the allowed range.';
      });
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = _isFtinMode ? 'Feet' : 'Value (cm)';
    return AlertDialog(
      title: const Text('Edit Height'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isFtinMode)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _feetController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Feet'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _inchesController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Inches'),
                  ),
                ),
              ],
            )
          else
            TextField(
              key: const Key('height_dialog_value_field'),
              controller: _valueController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofocus: true,
              decoration: InputDecoration(
                labelText: label,
                errorText: _valueError,
              ),
            ),
          if (_isFtinMode && _valueError != null) ...[
            const SizedBox(height: 8),
            Text(
              _valueError!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
            ),
          ],
        ],
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
          onPressed: () => Navigator.of(context).pop(),
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
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
