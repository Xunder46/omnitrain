/// The user data of one store, ready to be written to or read from a backup
/// file. The three maps carry stored values as they are (JSON-safe), keyed by
/// the box name and then by the stored key.
class BackupSnapshot {
  const BackupSnapshot({
    required this.collections,
    required this.lists,
    required this.meta,
    required this.dataVersion,
    required this.catalogVersion,
  });

  /// Map-valued boxes: box name -> key -> the stored map.
  final Map<String, Map<String, Object?>> collections;

  /// List-valued boxes: box name -> key -> the stored list.
  final Map<String, Map<String, List<Object?>>> lists;

  /// The exported meta keys; values are bool, int or String only.
  final Map<String, Object?> meta;

  final int dataVersion;
  final int catalogVersion;
}
