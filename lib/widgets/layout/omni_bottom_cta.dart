import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';

class OmniBottomCTA extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isDestructive;

  const OmniBottomCTA({
    super.key,
    required this.label,
    required this.onPressed,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final backgroundColor = isDestructive
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    final foregroundColor = isDestructive
        ? theme.colorScheme.onError
        : theme.colorScheme.onPrimary;
    final showLeadingAddIcon = label.trimLeft().startsWith('+');
    final buttonText = label.replaceFirst(RegExp(r'^\s*\+\s*'), '').trim();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            surface.withOpacity(0.0),
            surface.withOpacity(0.92),
            surface,
          ],
          stops: const [0.0, 0.35, 1.0],
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SizedBox(
          width: double.infinity,
          height: OmniTheme.buttonPrimaryHeight,
          child: FilledButton(
            onPressed: onPressed,
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return theme.colorScheme.onSurface.withOpacity(0.12);
                }
                return backgroundColor;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return theme.colorScheme.onSurface.withOpacity(0.38);
                }
                return foregroundColor;
              }),
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    OmniTheme.buttonBorderRadius,
                  ),
                ),
              ),
            ),
            child: showLeadingAddIcon
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add, size: 20),
                      const SizedBox(width: 8),
                      Text(buttonText),
                    ],
                  )
                : Text(label),
          ),
        ),
      ),
    );
  }
}
