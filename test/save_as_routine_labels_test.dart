// Plan 258: the summary's Save as Routine sheet names how each exercise is
// tracked in plain words. Plan 279: the sheet is gone (the routine editor
// opens instead), but the plain-language mapping it depended on still holds.
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/modality_display.dart';

void main() {
  test('S-25802 effortKindLabel maps the four kinds and leaves others', () {
    expect(ModalityDisplay.effortKindLabel('set'), 'Reps & Sets');
    expect(ModalityDisplay.effortKindLabel('timed'), 'Time');
    expect(ModalityDisplay.effortKindLabel('drill'), 'Hold Time');
    expect(ModalityDisplay.effortKindLabel('round'), 'Rounds');
    expect(ModalityDisplay.effortKindLabel('mystery'), 'mystery');
  });
}

