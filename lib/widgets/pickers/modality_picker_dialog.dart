import 'package:flutter/material.dart';

/// Dialog for selecting an exercise modality.
///
/// Returns `(true, modality)` when the user picks a modality, or `null` when
/// the user cancels.
class ModalityPickerDialog extends StatelessWidget {
  final String? initialModality;

  const ModalityPickerDialog({
    super.key,
    this.initialModality,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Color(0xFF1a1a1a),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Select Exercise Modality',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 20),
            ..._buildModalityOptions(context),
            SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildModalityOptions(BuildContext context) {
    final modalities = [
      ('cardio_endurance', 'Cardio', Icons.favorite),
      ('resistance_lifting', 'Resistance', Icons.fitness_center),
      ('sports', 'Sports', Icons.sports_basketball),
      ('isometric_stretching', 'Isometric', Icons.accessibility),
    ];

    return modalities.map((modalityTuple) {
      final modality = modalityTuple.$1;
      final displayName = modalityTuple.$2;
      final icon = modalityTuple.$3;
      final isSelected = modality == initialModality;

      return Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.pop(context, (true, modality)),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? Colors.blue : Colors.grey[700]!,
                  width: isSelected ? 2 : 1,
                ),
                color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: Colors.blue,
                    size: 24,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          _getModalityDescription(modality),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[400],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle, color: Colors.blue, size: 24),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  String _getModalityDescription(String? modality) {
    switch (modality) {
      case 'cardio_endurance':
        return 'Running, cycling, and endurance activities';
      case 'resistance_lifting':
        return 'Weight training with barbells and dumbbells';
      case 'sports':
        return 'Sport-specific movements and drills';
      case 'isometric_stretching':
        return 'Static holds, yoga, and flexibility';
      default:
        return '';
    }
  }
}
