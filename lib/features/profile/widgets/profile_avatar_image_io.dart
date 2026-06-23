import 'dart:io';

import 'package:flutter/material.dart';
import 'package:omnitrain/core/services/image_storage_service.dart';

/// Native-only renderer for the profile avatar. Uses [Image.file]
/// with an [errorBuilder] that falls back to a placeholder when
/// the file is missing or unreadable. The [reference] is the
/// stored value from `UserProfile.avatarPath` — under the
/// post-relocation-fix contract this is a **basename** (D-1 in
/// `.github/agents/plans/image-persistence-relocation-fix-plan.md`),
/// not an absolute path. The widget resolves the basename to an
/// absolute path via [imageStorage] (when provided) before handing
/// it to [Image.file]. When [imageStorage] is `null` (legacy or
/// test path) the reference is used as-is.
class ProfileAvatarImage extends StatelessWidget {
  /// The stored avatar reference (basename after the relocation
  /// fix, or a legacy absolute path during the migration window).
  final String reference;

  /// Image-storage service used to resolve [reference] to an
  /// absolute path. Required in production so the basename
  /// resolves correctly under the current managed directory;
  /// optional in tests that pass an already-resolved absolute
  /// path.
  final ImageStorageService? imageStorage;

  final BoxFit fit;
  final Widget fallback;

  const ProfileAvatarImage({
    super.key,
    required this.reference,
    required this.fallback,
    this.imageStorage,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final absPath = imageStorage?.resolvePathSync(reference) ?? reference;
    return Image.file(
      File(absPath),
      fit: fit,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}
