import 'package:flutter/material.dart';
import '../../data/models/models.dart';
import '../../core/constants/capability.dart';

/// Dialog for choosing a tracking metric for an exercise in Free Training mode
/// Only shows metrics the exercise supports
class MetricChooserDialog extends StatelessWidget {
  final Exercise exercise;

  const MetricChooserDialog({super.key, required this.exercise});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final capabilities = exercise.capabilities;

    if (capabilities.isEmpty) {
      return AlertDialog(
        title: const Text('No Capabilities'),
        content: const Text('This exercise has no defined tracking capabilities.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    }

    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How to track?',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              exercise.name,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Choose tracking method:',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 16),
            
            // List of metric options
            ...capabilities.map((capability) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _MetricOption(
                  capability: capability,
                  onTap: () => Navigator.of(context).pop(capability),
                ),
              );
            }),
            
            const SizedBox(height: 16),
            
            // Cancel button
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricOption extends StatelessWidget {
  final String capability;
  final VoidCallback onTap;

  const _MetricOption({
    required this.capability,
    required this.onTap,
  });

  IconData _getIcon() {
    switch (capability) {
      case 'time':
        return Icons.timer;
      case 'hold':
        return Icons.pause_circle_outline;
      case 'reps':
        return Icons.repeat;
      case 'sets':
        return Icons.view_list;
      case 'load':
        return Icons.fitness_center;
      case 'distance':
        return Icons.straighten;
      case 'rounds':
        return Icons.replay;
      default:
        return Icons.help_outline;
    }
  }

  String _getLabel() {
    switch (capability) {
      case 'time':
        return 'Track by Time';
      case 'hold':
        return 'Track by Hold Time';
      case 'reps':
        return 'Track by Reps & Sets';
      case 'sets':
        return 'Track by Sets';
      case 'load':
        return 'Track by Weight';
      case 'distance':
        return 'Track by Distance';
      case 'rounds':
        return 'Track by Rounds';
      default:
        return capability;
    }
  }

  String _getDescription() {
    return ExerciseCapability.getDescription(capability);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getIcon(),
                  color: theme.colorScheme.onPrimaryContainer,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getLabel(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getDescription(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: theme.colorScheme.onSurface.withOpacity(0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
