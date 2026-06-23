import 'package:flutter/material.dart';
import 'package:omnitrain/core/services/image_storage_service.dart';

/// Web stub for [ProfileAvatarImage]. Mirrors the IO variant's
/// public surface so the conditional-import contract is
/// platform-uniform. On web, the parent screen already
/// short-circuits via `kIsWeb` and the [Image.file] path is never
/// reached; the stub unconditionally returns [fallback].
class ProfileAvatarImage extends StatelessWidget {
  /// The stored avatar reference. Unused on web.
  final String reference;

  /// Unused on web — kept for API parity with the IO variant.
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
  Widget build(BuildContext context) => fallback;
}
