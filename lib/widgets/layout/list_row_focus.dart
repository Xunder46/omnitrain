import 'package:flutter/material.dart';

/// Brings one row of a long list back into view (plan 139).
///
/// A lazy list builds only the rows near its viewport, so a row far away has
/// no [BuildContext] to scroll to. [request] therefore raises [cacheExtent]
/// for ONE frame so the whole list is built; [reveal] then scrolls the row to
/// [kRevealAlignment] and clears the request, and the owner rebuilds so the
/// list returns to its default cache extent.
///
/// Rows are registered with [track], which uses a [Builder] (no `GlobalKey`:
/// a duplicated key clashes inside a `ReorderableListView` during a drag).
class ListRowFocus {
  /// Where the row's top edge lands: this fraction of the free viewport space
  /// (`viewportHeight - rowHeight`) from the top of the list.
  static const double kRevealAlignment = 0.3;

  /// Cache extent while a request is pending. Finite on purpose:
  /// `double.infinity` trips a Flutter assertion (`value.isFinite`).
  static const double kRevealCacheExtent = 100000;

  final Map<String, BuildContext> _rows = <String, BuildContext>{};
  String? _pendingId;

  /// Pass to the list's `cacheExtent`: raised while a request is pending, and
  /// `null` (the framework default) otherwise.
  double? get cacheExtent => _pendingId == null ? null : kRevealCacheExtent;

  /// Wraps [child] so the row can be found by [id]. Adds no visible widget.
  Widget track(String id, Widget child) {
    // Keyed by id so a row that leaves the list unmounts its own element
    // (without a key the framework reuses it for the next row and [reveal]
    // would scroll to the wrong one).
    return Builder(
      key: ValueKey<String>('list-row-focus-$id'),
      builder: (BuildContext context) {
        _rows[id] = context;
        return child;
      },
    );
  }

  /// Asks for the row [id] to be revealed by the next [reveal] call. The
  /// owner must rebuild its list so [cacheExtent] takes effect.
  void request(String id) => _pendingId = id;

  /// Scrolls the requested row into view with no animation. Returns false (and
  /// moves nothing) when nothing was requested, the id was never built, or the
  /// row is gone. The request is cleared either way.
  bool reveal() {
    final String? id = _pendingId;
    _pendingId = null;
    if (id == null) return false;
    final BuildContext? rowContext = _rows[id];
    if (rowContext == null || !rowContext.mounted) return false;
    Scrollable.ensureVisible(
      rowContext,
      alignment: kRevealAlignment,
      duration: Duration.zero,
    );
    return true;
  }
}
