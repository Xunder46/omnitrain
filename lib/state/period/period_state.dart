import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';

const _uuid = Uuid();

/// Validation result for the Create/Edit Period form.
class PeriodValidationResult {
  final bool isValid;
  final String? nameError;
  final String? dateError;
  final String? overlapError;

  const PeriodValidationResult({
    required this.isValid,
    this.nameError,
    this.dateError,
    this.overlapError,
  });
}

/// State holder for period list and create/edit operations.
///
/// Provides the full list of [TrainingPeriod] objects, overlap validation,
/// and CRUD methods that immediately refresh the list.
class PeriodState extends ChangeNotifier {
  final WorkoutRepository _repository;

  PeriodState(this._repository);

  // ─── Data ─────────────────────────────────────────────────────────────────

  List<TrainingPeriod> _periods = [];
  List<TrainingPeriod> get periods => List.unmodifiable(_periods);

  // ─── Loading ──────────────────────────────────────────────────────────────

  bool _isLoading = false;
  String? _error;

  bool get isLoading => _isLoading;
  String? get error => _error;

  // ─── Initialization ───────────────────────────────────────────────────────

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _periods = await _repository.getPeriods();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─── Validation ───────────────────────────────────────────────────────────

  /// Validates form fields and checks repository for overlap.
  /// Pass [excludeId] when editing an existing period.
  Future<PeriodValidationResult> validate(
    String name,
    int? startMs,
    int? endMs, {
    String? excludeId,
  }) async {
    String? nameError;
    String? dateError;
    String? overlapError;

    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      nameError = 'Name is required.';
    } else if (trimmed.length > 50) {
      nameError = 'Name must be 50 characters or fewer.';
    }

    if (startMs == null || endMs == null) {
      dateError = 'Both start and end dates are required.';
    } else if (endMs < startMs) {
      dateError = 'End date must be on or after the start date.';
    } else {
      final hasOverlap = await _repository.hasPeriodOverlap(
        startMs,
        endMs,
        excludeId: excludeId,
      );
      if (hasOverlap) {
        overlapError =
            'This date range overlaps with an existing period. Periods may not overlap.';
      }
    }

    return PeriodValidationResult(
      isValid: nameError == null && dateError == null && overlapError == null,
      nameError: nameError,
      dateError: dateError,
      overlapError: overlapError,
    );
  }

  // ─── CRUD ─────────────────────────────────────────────────────────────────

  Future<bool> createPeriod({
    required String name,
    required int startMs,
    required int endMs,
    List<String> focusModalities = const [],
    String? notes,
    String? colorHex,
  }) async {
    final result = await validate(name, startMs, endMs);
    if (!result.isValid) return false;

    final now = DateTime.now().millisecondsSinceEpoch;
    final period = TrainingPeriod(
      id: _uuid.v4(),
      name: name.trim(),
      startDateMs: startMs,
      endDateMs: endMs,
      focusModalities: focusModalities,
      notes: notes?.trim().isNotEmpty == true ? notes!.trim() : null,
      colorHex: colorHex,
      createdAtMs: now,
      updatedAtMs: now,
    );

    await _repository.createPeriod(period);
    await load();
    return true;
  }

  Future<bool> updatePeriod({
    required String id,
    String? ownerUserId,
    required int createdAtMs,
    required String name,
    required int startMs,
    required int endMs,
    List<String> focusModalities = const [],
    String? notes,
    String? colorHex,
  }) async {
    final result = await validate(name, startMs, endMs, excludeId: id);
    if (!result.isValid) return false;

    final now = DateTime.now().millisecondsSinceEpoch;
    final period = TrainingPeriod(
      id: id,
      ownerUserId: ownerUserId,
      name: name.trim(),
      startDateMs: startMs,
      endDateMs: endMs,
      focusModalities: focusModalities,
      notes: notes?.trim().isNotEmpty == true ? notes!.trim() : null,
      colorHex: colorHex,
      createdAtMs: createdAtMs,
      updatedAtMs: now,
    );

    await _repository.updatePeriod(period);
    await load();
    return true;
  }

  Future<void> deletePeriod(String id) async {
    await _repository.deletePeriod(id);
    await load();
  }
}
