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
        '.github/agents/plans/image-persistence-fix-plan.md (D-8).',
      );
    }
    return svc;
  }

  UserProfile? _profile;
  bool _isLoading = false;
  String? _error;
  final Map<String, BodyMeasurementEntry?> _latestMeasurements = {};

  UserProfile? get profile => _profile;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, BodyMeasurementEntry?> get latestMeasurements =>
      Map.unmodifiable(_latestMeasurements);

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

      // Self-heal (D-4): a pre-existing record whose `avatarPath`
      // points at a file the OS has since deleted (e.g. a stale
      // `image_picker` cache path from before the persistence fix)
      // is converged to `null` on first load so the renderer shows
      // its fallback instead of a broken image, and the data layer
      // stops carrying an orphan reference.
      await _selfHealAvatarPath();

      await loadLatestMeasurements(
        ProfileMeasurements.primary.map((definition) => definition.type),
        notify: false,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load-time self-heal. See [loadProfile]. No-op when no
  /// service was injected, when the avatar is already null, and
  /// when the file is actually present. Silent — does not surface
  /// an error or snackbar.
  Future<void> _selfHealAvatarPath() async {
    final svc = _imageStorage;
    final path = _profile?.avatarPath;
    if (svc == null || path == null) return;
    if (svc.exists(path)) return;
    final healed = UserProfile(
      id: _profile!.id,
      displayName: _profile!.displayName,
      avatarPath: null,
      createdAtMs: _profile!.createdAtMs,
    );
    await _repository.saveProfile(healed);
    _profile = healed;
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
