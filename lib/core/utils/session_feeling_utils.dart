import 'package:flutter/material.dart';

Color feelingColor(int feeling, BuildContext context) {
  switch (feeling) {
    case 1:
      return Colors.red;
    case 2:
      return Colors.orange;
    case 3:
      return Colors.yellow[700]!;
    case 4:
      return Colors.green;
    case 5:
      return Theme.of(context).primaryColor;
    default:
      return Theme.of(context).primaryColor;
  }
}
