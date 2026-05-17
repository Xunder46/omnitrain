import 'package:flutter/material.dart';
import '../../core/constants/omni_theme.dart';
import '../../core/utils/modality_color_utils.dart';
import '../../state/period/period_state.dart';
import '../../core/constants/modality.dart';
import '../../data/models/models.dart';
import '../../widgets/layout/omni_bottom_cta.dart';

class CreatePeriodScreen extends StatefulWidget {
  final PeriodState periodState;

  /// If non-null, this screen is in edit mode and will update the existing period.
  final TrainingPeriod? existingPeriod;

  const CreatePeriodScreen({
    super.key,
    required this.periodState,
    this.existingPeriod,
  });

  @override
  State<CreatePeriodScreen> createState() => _CreatePeriodScreenState();
}

class _CreatePeriodScreenState extends State<CreatePeriodScreen> {
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  final Set<String> _focusModalities = {};
  String? _selectedColor;

  bool _isSaving = false;
  String? _nameError;
  String? _dateError;
  String? _overlapError;

  static const _allModalities = [
    Modality.cardioEndurance,
    Modality.resistanceLifting,
    Modality.sports,
    Modality.isometricStretching,
  ];

  static const _colorPalette = [
    '#4CAF50', // Green
    '#FF5722', // Orange-red
    '#2196F3', // Blue
    '#9C27B0', // Purple
    '#FF9800', // Orange
    '#00BCD4', // Cyan
    '#E91E63', // Pink
    '#FFC107', // Amber
    '#795548', // Brown
    '#607D8B', // Blue-grey
  ];

  @override
  void initState() {
    super.initState();
    final existing = widget.existingPeriod;
    if (existing != null) {
      _nameCtrl.text = existing.name;
      _startDate = DateTime.fromMillisecondsSinceEpoch(existing.startDateMs);
      _endDate = DateTime.fromMillisecondsSinceEpoch(existing.endDateMs);
      _focusModalities.addAll(existing.focusModalities);
      _notesCtrl.text = existing.notes ?? '';
      _selectedColor = existing.colorHex;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          widget.existingPeriod == null ? 'Create Period' : 'Edit Period',
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      bottomNavigationBar: OmniBottomCTA(
        label: 'Save',
        onPressed: _isSaving ? null : _submit,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 128),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Name ─────────────────────────────────────────────
              TextField(
                textCapitalization: TextCapitalization.words,
                controller: _nameCtrl,
                maxLength: 50,
                decoration: InputDecoration(
                  labelText: 'Period Name *',
                  border: const OutlineInputBorder(),
                  errorText: _nameError,
                  counterText: '',
                ),
                onChanged: (_) {
                  if (_nameError != null) {
                    setState(() => _nameError = null);
                  }
                },
              ),
              const SizedBox(height: 16),

              // ── Date range ───────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: 'Start Date',
                      value: _startDate,
                      onTap: () => _pickDate(isStart: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateField(
                      label: 'End Date',
                      value: _endDate,
                      onTap: () => _pickDate(isStart: false),
                    ),
                  ),
                ],
              ),
              if (_dateError != null) ...[
                const SizedBox(height: 4),
                Text(
                  _dateError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
              if (_overlapError != null) ...[
                const SizedBox(height: 4),
                Text(
                  _overlapError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // ── Focus modalities ─────────────────────────────────
              const Text(
                'Focus Modalities (optional)',
                style: TextStyle(
                  color: OmniTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _allModalities.map((m) {
                  final selected = _focusModalities.contains(m);
                  final color = ModalityColorUtils.colorForModality(m);
                  return FilterChip(
                    label: Text(ModalityColorUtils.labelForModality(m)),
                    selected: selected,
                    selectedColor: color.withOpacity(0.25),
                    checkmarkColor: color,
                    labelStyle: TextStyle(
                      color: selected ? color : OmniTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _focusModalities.add(m);
                        } else {
                          _focusModalities.remove(m);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // ── Color ─────────────────────────────────────────────
              const Text(
                'Calendar Color',
                style: TextStyle(
                  color: OmniTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _colorPalette.map((colorHex) {
                  final color = Color(
                    int.parse(colorHex.substring(1), radix: 16) + 0xFF000000,
                  );
                  final isSelected = _selectedColor == colorHex;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = colorHex),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: OmniTheme.textPrimary, width: 3)
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // ── Notes ─────────────────────────────────────────────
              TextField(
                textCapitalization: TextCapitalization.sentences,
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? (_startDate ?? DateTime.now()));

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );

    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        // Clear end date if it's now before start.
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = null;
        }
      } else {
        _endDate = picked;
      }
      _dateError = null;
      _overlapError = null;
    });
  }

  Future<void> _submit() async {
    setState(() {
      _nameError = null;
      _dateError = null;
      _overlapError = null;
      _isSaving = true;
    });

    final startMs = _startDate != null
        ? DateTime(
            _startDate!.year,
            _startDate!.month,
            _startDate!.day,
          ).millisecondsSinceEpoch
        : null;
    final endMs = _endDate != null
        ? DateTime(
            _endDate!.year,
            _endDate!.month,
            _endDate!.day,
            23,
            59,
            59,
            999,
          ).millisecondsSinceEpoch
        : null;

    final validation = await widget.periodState.validate(
      _nameCtrl.text,
      startMs,
      endMs,
      excludeId: widget.existingPeriod?.id,
    );

    if (!validation.isValid) {
      setState(() {
        _nameError = validation.nameError;
        _dateError = validation.dateError;
        _overlapError = validation.overlapError;
        _isSaving = false;
      });
      return;
    }

    bool success;
    if (widget.existingPeriod == null) {
      // Create mode
      success = await widget.periodState.createPeriod(
        name: _nameCtrl.text,
        startMs: startMs!,
        endMs: endMs!,
        focusModalities: _focusModalities.toList(),
        notes: _notesCtrl.text,
        colorHex: _selectedColor,
      );
    } else {
      // Edit mode
      success = await widget.periodState.updatePeriod(
        id: widget.existingPeriod!.id,
        ownerUserId: widget.existingPeriod!.ownerUserId,
        createdAtMs: widget.existingPeriod!.createdAtMs,
        name: _nameCtrl.text,
        startMs: startMs!,
        endMs: endMs!,
        focusModalities: _focusModalities.toList(),
        notes: _notesCtrl.text,
        colorHex: _selectedColor,
      );
    }

    setState(() => _isSaving = false);

    if (success && mounted) {
      Navigator.of(context).pop(true);
    }
  }
}

// ─── Helper widget ────────────────────────────────────────────────────────────

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = value != null
        ? '${value!.day.toString().padLeft(2, '0')}/'
              '${value!.month.toString().padLeft(2, '0')}/'
              '${value!.year}'
        : 'Select';

    return GestureDetector(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today, size: 16),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: value != null
                ? OmniTheme.textPrimary
                : OmniTheme.textSecondary.withOpacity(0.5),
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
