import 'package:flutter/material.dart';

import '../../core/constants/omni_theme.dart';

/// Above this many entries the captions would not fit under their segments,
/// so they are dropped entirely (no reserved space either).
const int kSetBarCaptionMaxSets = 5;

/// Thin set-progress bar for the session exercise screen.
///
/// One segment per entry of the effort — set, interval, round or hold — so the
/// bar is identical across every modality. Tapping a segment jumps to that
/// entry; the focused segment shows its [captions] entry in the dominant text
/// colour, and every segment is 6 dp tall with no outline.
///
/// Colours come from `Theme.of(context).colorScheme` only — no literals.
class SetSegmentBar extends StatelessWidget {
  /// Number of entries in the current effort (1..`maxEntriesPerEffort`).
  final int count;

  /// Zero-based index of the entry the screen is showing.
  final int focusedIndex;

  /// Whether the entry at the given index has been logged.
  final bool Function(int) isLogged;

  /// Optional caption under each segment — the logged value, or `null` for a
  /// blank one. Rendered only when the list has exactly [count] entries and
  /// [count] is at most [kSetBarCaptionMaxSets].
  final List<String?>? captions;

  /// Called with the tapped segment's index.
  final ValueChanged<int> onTap;

  const SetSegmentBar({
    super.key,
    required this.count,
    required this.focusedIndex,
    required this.isLogged,
    required this.onTap,
    this.captions,
  });

  /// Screen-reader label: logged and focus are both spelled out, because the
  /// fill alone does not carry them.
  String _semanticsLabel(int index) {
    final base = 'Set ${index + 1} of $count, ';
    final logged = isLogged(index);
    final focused = index == focusedIndex;
    if (logged && focused) return '${base}logged, current';
    if (logged) return '${base}logged';
    if (focused) return '${base}current';
    return '${base}not logged';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final showCaptions =
        captions != null &&
        captions!.length == count &&
        count <= kSetBarCaptionMaxSets;

    return Row(
      children: [
        for (var i = 0; i < count; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Semantics(
                label: _semanticsLabel(i),
                button: true,
                excludeSemantics: true,
                child: GestureDetector(
                  key: Key('set-segment-$i'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: SizedBox(
                    height: 48,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _segment(scheme, i),
                          if (showCaptions) ...[
                            const SizedBox(height: 4),
                            SizedBox(
                              height: 20,
                              child: Text(
                                captions![i] ?? '',
                                key: Key('set-caption-$i'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: i == focusedIndex
                                      ? OmniTheme.colors.textDominant
                                      : OmniTheme.colors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _segment(ColorScheme scheme, int index) {
    final logged = isLogged(index);
    final focused = index == focusedIndex;

    final Color fill;
    if (logged) {
      fill = scheme.primary;
    } else if (focused) {
      fill = scheme.primary.withAlpha(115);
    } else {
      fill = scheme.onSurface.withAlpha(51);
    }

    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
