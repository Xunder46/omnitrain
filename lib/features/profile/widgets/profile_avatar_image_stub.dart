import 'package:flutter/material.dart';

class ProfileAvatarImage extends StatelessWidget {
  final String path;
  final BoxFit fit;
  final Widget fallback;

  const ProfileAvatarImage({
    super.key,
    required this.path,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return fallback;
  }
}
