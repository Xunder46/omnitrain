import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/profile_measurements.dart';
import '../../core/services/image_storage_service.dart';
import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';

const _uuid = Uuid();

class ProfileState extends ChangeNotifier {
  final WorkoutRepository _repository;

  /// Optional image-storage helper. When provided, the state
  /// self-heals stale avatar paths on load (D-4) and deletes the
  /// previous managed file when the avatar is replaced or removed
  /// (D-3, D-7). When null, these behaviours are no-ops — used
  /// only by tests that do not exercise image persistence.
  final ImageStorageService? _imageStorage;

  ProfileState(this._repository, {ImageStorageService? imageStorage})
    : _imageStorage = imageStorage;

  /// Non-null accessor for the image storage helper. Screens that
  /// host the avatar picker (`ProfileScreen`) read this to perform
  /// the file-system copy before calling [updateAvatarPath]. The
  /// production `main.dart` always injects a real service; tests
  /// that do not exercise the picker should not read this getter.
  ImageStorageService get imageStorage {
    final svc = _imageStorage;
    if (svc == null) {
      throw StateError(
        'ProfileState.imageStorage was read but no service was injected. '
        'main.dart must construct an ImageStorageService and pass it '
        'to ProfileState. See '
        'docs/plans/image-persistence-fix-plan.md (D-8).',
      );
    }
    return svc;
  }

  /// Nullable accessor for the image storage helper. Used by the
  /// rendering widgets (`ProfileAvatarImage`) which receive the
  /// service as an optional parameter and degrade gracefully when
  /// no service is injected (legacy / test path).
  ImageStorageService? get imageStorageOrNull => _imageStorage;

  UserProfile? _profile;
  bool _isLoading = false;
  String? _error;
  final Map<String, BodyMeasurementEntry?> _latestMeasurements = {};

  UserProfile? get profile => _profile;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, BodyMeasurementEntry?> get latestMeasurements =>
      Map.unmodifiable(_latestMeasurements);

  // ── Convenience accessors for the cleaned-up Profile screen ─────────────
  //
  // These are pure derivations of `_latestMeasurements` — no extra
  // load, no extra state. The chart path used to read
  // `latestMeasurements[type]` directly; the cleanup pass exposes
  // these named getters so callers don't have to know the storage
  // string for each measurement.

  /// Latest height in canonical centimeters, or `null` if the user
  /// has never logged one. Height is no longer a charted card — it
  /// lives in the identity area — but it still routes through the
  /// same `BodyMeasurementEntry` repository.
  double? get latestHeightCm => _latestMeasurements['height']?.value;

  /// Latest body weight in canonical kilograms.
  double? get latestBodyWeightKg => _latestMeasurements['bodyweight']?.value;

  /// Latest body fat percentage (canonical unit is `unit-pct`).
  double? get latestBodyFatPct => _latestMeasurements['body_fat_pct']?.value;

  /// Computed lean mass in canonical kilograms:
  ///
  ///     lean_mass_kg = body_weight_kg × (1 - body_fat_pct / 100)
  ///
  /// Returns `null` if either input is missing — the UI renders an
  /// em-dash in that case (the user hasn't logged one of the two
  /// required inputs yet). Lean mass is intentionally NOT a stored
  /// value: three independently-typed fields that are
  /// mathematically linked will inevitably contradict each other,
  /// so we derive this one from the other two.
  double? get computedLeanMassKg {
    final weight = latestBodyWeightKg;
    final bodyFat = latestBodyFatPct;
    if (weight == null || bodyFat == null) return null;
    return weight * (1 - bodyFat / 100);
  }

  Future<void> loadProfile() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _profile = await _repository.getProfile();
      if (_profile == null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        _profile = UserProfile(id: 'local-user', createdAtMs: now);
        await _repository.saveProfile(_profile!);
      }

      // Self-heal + re-link (D-4..D-6 + INV-4): resolve the stored
      // avatar path against the **current** managed directory. If
      // the file is reachable anywhere on disk under a known
      // candidate location, normalize the stored reference to the
      // basename (location-independent) and persist. If the file
      // is truly absent, clear the field and persist (true
      // self-heal). The reference is **never** cleared while the
      // file is still reachable — that is the launch-blocker bug
      // this rewrite addresses.
      await _resolveAndNormalizeAvatarPath();

      // Cleanup pass: load the charted column (`additional` — which no
      // longer contains height). Height is loaded separately by the
      // screen's initState so the identity area can read it.
      await loadLatestMeasurements(
        ProfileMeasurements.additional.map((definition) => definition.type),
        notify: false,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load-time resolve + normalize. See [loadProfile].
  ///
  /// Resolution contract (D-3): the service searches the current
  /// managed dir, the literal reference path (legacy absolute
  /// paths), and configured candidate directories (picker temp,
  /// app support). If a file matching the basename is reachable
  /// anywhere, the service re-links it into the current managed
  /// dir and returns the basename. If no candidate has the file,
  /// the service returns `null`.
  ///
  /// Persistence rules (D-4, D-6, INV-4):
  ///   * No service injected → no-op.
  ///   * No stored reference → no-op.
  ///   * Service returns the same value as stored → no write.
  ///   * Service returns a different basename → persist the
  ///     normalized reference (one-time migration write). The file
  ///     is re-linked by the service.
  ///   * Service returns `null` → persist `avatarPath: null`
  ///     (true self-heal; file is truly absent on disk).
  ///
  /// Silent — does not surface an error or snackbar.
  Future<void> _resolveAndNormalizeAvatarPath() async {
    final svc = _imageStorage;
    final stored = _profile?.avatarPath;
    if (svc == null || stored == null) return;

    final resolved = await svc.resolveOrRelink(stored);
    if (resolved == stored) return;

    final normalized = UserProfile(
      id: _profile!.id,
      displayName: _profile!.displayName,
      avatarPath: resolved,
      createdAtMs: _profile!.createdAtMs,
    );
    await _repository.saveProfile(normalized);
    _profile = normalized;
  }

  Future<void> loadLatestMeasurements(
    Iterable<String> measurementTypes, {
    bool notify = true,
  }) async {
    try {
      for (final measurementType in measurementTypes) {
        _latestMeasurements[measurementType] = await _repository
            .getLatestMeasurement(measurementType);
      }
    } catch (e) {
      _error = e.toString();
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> updateDisplayName(String name) async {
    final existingProfile = await _ensureProfile();
    final trimmed = name.trim();
    final updatedProfile = UserProfile(
      id: existingProfile.id,
      displayName: trimmed.isEmpty ? null : trimmed,
      avatarPath: existingProfile.avatarPath,
      createdAtMs: existingProfile.createdAtMs,
    );
    await _repository.saveProfile(updatedProfile);
    _profile = updatedProfile;
    notifyListeners();
  }

  Future<void> updateAvatarPath(String? path) async {
    final existingProfile = await _ensureProfile();
    // D-7: replace/remove cleanup. The state is the single owner
    // that knows what the previous avatar was; it asks the
    // service to delete the previous managed file iff the path
    // actually changed AND the file lives under the managed
    // directory. D-3 (isManaged) is the sole delete gate.
    final previousPath = existingProfile.avatarPath;
    if (previousPath != path) {
      final svc = _imageStorage;
      if (svc != null && previousPath != null) {
        await svc.deleteIfManaged(previousPath);
      }
    }
    final updatedProfile = UserProfile(
      id: existingProfile.id,
      displayName: existingProfile.displayName,
      avatarPath: path,
      createdAtMs: existingProfile.createdAtMs,
    );
    await _repository.saveProfile(updatedProfile);
    _profile = updatedProfile;
    notifyListeners();
  }

  Future<void> logMeasurement(
    String type,
    double value,
    String unitId, {
    int? recordedAtMs,
  }) async {
    final entry = BodyMeasurementEntry(
      id: _uuid.v4(),
      measurementType: type,
      value: value,
      unitId: unitId,
      recordedAtMs: recordedAtMs ?? DateTime.now().millisecondsSinceEpoch,
    );

    await _repository.saveMeasurementEntry(entry);
    _latestMeasurements[type] = await _repository.getLatestMeasurement(type);
    notifyListeners();
  }

  Future<List<BodyMeasurementEntry>> getMeasurementHistory(String type) {
    return _repository.getMeasurementHistory(type);
  }

  /// Persist the user's height. The chart-card path used to call
  /// [logMeasurement] for height; the cleanup pass routes the
  /// identity-area height editor through the same write path
  /// (`type='height'`, `unitId='unit-cm'`, canonical cm) so the
  /// repository contract doesn't change. The Settings height
  /// preview keeps working unchanged because it also reads
  /// `type='height'` entries.
  Future<void> updateHeight(double cmCanonical) async {
    await logMeasurement('height', cmCanonical, 'unit-cm');
  }

  Future<void> deleteMeasurementEntry(
    String entryId,
    String measurementType,
  ) async {
    await _repository.deleteMeasurementEntry(entryId);
    _latestMeasurements[measurementType] = await _repository
        .getLatestMeasurement(measurementType);
    notifyListeners();
  }

  Future<UserProfile> _ensureProfile() async {
    if (_profile != null) return _profile!;
    await loadProfile();
    final profile = _profile;
    if (profile == null) {
      throw StateError('Profile could not be loaded.');
    }
    return profile;
  }
}
