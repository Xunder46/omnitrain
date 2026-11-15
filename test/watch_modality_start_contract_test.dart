// The phone half of the watch Start surface's modality grid contract: the four
// cells the wrist offers are the phone's own modality colours and short labels.
//
// Plan: `docs/plans/2026-11-15-176-watch-modality-start-grid-plan/2026-11-15-176-watch-modality-start-grid-plan.md`,
// D-17602 and scenario S-17602. The wrist half is
// `watch/watchos/Tests/WatchSessionEngineTests/WatchModalityStartContractTests.swift`,
// which holds `WatchModalityStart.cells` to the same file.
//
// Nothing is restated here: the rows are read from the shared contract and
// walked against `ModalityColors` and `HomeTiles`, so a phone colour or label
// that moves fails this suite until the contract row moves with it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitrain/core/constants/home_tiles.dart';
import 'package:omnitrain/core/constants/modality_colors.dart';
import 'package:omnitrain/core/utils/watch_reference_sync.dart';

/// `watch/contract/watch_modality_start_contract.json`, parsed.
Map<String, Object?> _contract() {
  final file = File(
    '${Directory.current.path}/watch/contract/'
    'watch_modality_start_contract.json',
  );
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

/// The grid's rows, in contract order.
List<Map<String, Object?>> _rows() {
  final rows = _contract()['gridOrder'];
  if (rows is! List) {
    throw StateError('the contract carries gridOrder');
  }
  return rows.cast<Map<String, Object?>>();
}

void main() {
  group('S-17602 the grid is the phone\'s modalities, colours and labels', () {
    test('S-17602 the rows are the four modalities in the phone\'s home-tile '
        'order', () {
      final phoneOrder = [
        for (final tile in HomeTiles.all)
          if (tile.modality != null) tile.modality,
      ];

      expect(
        [for (final row in _rows()) row['key']],
        phoneOrder,
        reason:
            'S-17602 the wrist offers the modalities the phone offers, in the '
            'order the phone shows them',
      );
    });

    test('S-17602 every row wears the phone\'s own ModalityColors hex', () {
      for (final row in _rows()) {
        final key = row['key']! as String;

        expect(
          ModalityColors.byModality[key],
          isNotNull,
          reason: 'S-17602 $key is a modality the phone colors',
        );
        expect(
          WatchReferenceSync.accentHexOf(ModalityColors.byModality[key]!),
          row['hex'],
          reason:
              'S-17602 the wrist wears the phone\'s accent for $key, so a '
              'ModalityColors change fails here until the contract row moves',
        );
      }
    });

    test('S-17602 every row carries the phone\'s own home-tile label', () {
      for (final row in _rows()) {
        final key = row['key']! as String;
        final tile = HomeTiles.all.firstWhere(
          (candidate) => candidate.modality == key,
          orElse: () => throw StateError('$key has a home tile'),
        );

        expect(
          row['label'],
          tile.label,
          reason:
              'S-17602 the cell shows the short home-tile word for $key, not '
              'the long ModalityDisplay name a 40 mm cell cannot hold',
        );
      }
    });
  });

  group('S-17603 the cell\'s spoken sentence', () {
    test('S-17603 the contract\'s sentence pattern is what the wrist builds '
        'from, and the four labels fill it', () {
      final pattern = _contract()['startSurfaceSentence']! as String;

      expect(
        pattern,
        'Start <Label> workout',
        reason: 'S-17603 the one sentence every cell is spoken with',
      );
      expect(
        [
          for (final row in _rows())
            pattern.replaceFirst('<Label>', row['label']! as String),
        ],
        [
          'Start Cardio workout',
          'Start Resistance workout',
          'Start Sports workout',
          'Start Isometric workout',
        ],
        reason: 'S-17603 the four sentences the owner and the QA step read',
      );
    });
  });
}
