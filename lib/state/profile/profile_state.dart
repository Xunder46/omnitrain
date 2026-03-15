import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/profile_measurements.dart';
import '../../data/models/models.dart';
import '../../data/repositories/workout_repository.dart';

const _uuid = Uuid();

class ProfileState extends ChangeNotifier {
  final WorkoutRepository _repository;

  ProfileState(this._repository);

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
