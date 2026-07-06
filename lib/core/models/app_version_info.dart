/// Process-local snapshot of the installed build's `pubspec.yaml` version
/// metadata (X.Y.Z) and the Flutter build number (N).
///
/// Sourced at app startup via `package_info_plus` and injected into every
/// site that needs to display the value (currently the Settings footer
/// only). Keeping this as a pure Dart value object — no Flutter, no
/// `dart:io`, no plugin access — means widgets and tests can construct
/// one with literal values without bootstrapping a platform channel.
///
/// The shape intentionally mirrors `pubspec.yaml`:
///   * `version` corresponds to `pubspec.yaml`'s `version:` X.Y.Z token
///     (the part before `+`).
///   * `build` corresponds to the build number after `+`, surfaced by
///     `PackageInfo.buildNumber`.
class AppVersionInfo {
  final String version;
  final String build;

  const AppVersionInfo({required this.version, required this.build});

  /// Convenient formatter for the Settings footer. Mirrors the canonical
  /// "Version X.Y.Z (N)" presentation so test assertions and screen
  /// renderers share the same string shape.
  String formatVersionLine() => 'Version $version ($build)';

  @override
  String toString() => formatVersionLine();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppVersionInfo &&
          version == other.version &&
          build == other.build;

  @override
  int get hashCode => Object.hash(version, build);
}
