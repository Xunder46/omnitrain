/// The Wear wrist's exercise pager rule: which page is current, the one jump a
/// settled swipe makes, and the lock that refuses a swipe during an effort.
///
/// Plan: `docs/plans/2026-11-21-287-wear-swipe-pager-plan/2026-11-21-287-wear-swipe-pager-plan.md`
/// (D-28701, D-28702). The Dart twin of `WatchPagerModel.swift`, minus the
/// focus (D-28703). It owns no session structure of its own: a settled page is
/// the menu's `jump`, which is the engine's own select path, and the rows and
/// the position are read from the menu on every access, never cached.
library;

import 'watch_menu_state.dart';

/// The words and numbers the pager uses; the lock notice is the menu's own caption.
abstract final class WatchPagerCopy {
  static const String lockedNotice = WatchMenuCopy.lockedCaption;
  static const Duration noticeDuration = Duration(milliseconds: 1500);
  static const Duration slideDuration = Duration(milliseconds: 200);

  /// Points of horizontal travel a swipe must exceed to count.
  static const double swipeThreshold = 24;
}

class WatchPagerState {
  WatchPagerState({required this.menu, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final WatchMenuState menu;
  final DateTime Function() _clock;
  DateTime? _noticeUntil;

  static int _indexOfCurrent(List<WatchMenuRow> rows) {
    final index = rows.indexWhere((row) => row.isCurrent);
    return index < 0 ? 0 : index;
  }

  List<WatchMenuRow> get rows => menu.rows;

  int get pageCount => rows.length;

  int get currentIndex => _indexOfCurrent(rows);

  /// The current page's slot id, or null when the session has no exercise.
  String? get currentSlotId {
    final all = rows;
    return all.isEmpty ? null : all[_indexOfCurrent(all)].slotId;
  }

  bool get isLocked => menu.isLocked;

  /// The pager shows with two or more exercises and no work clock running.
  bool get showsPager => pageCount > 1 && !isLocked;

  /// `n/N` with two or more exercises, else null.
  String? get pageLabel {
    final all = rows;
    return all.length > 1 ? '${_indexOfCurrent(all) + 1}/${all.length}' : null;
  }

  /// The page a horizontal swipe from page [index] reaches: the next one when
  /// [towardsNext], else the previous one. Null when the pager is not shown or
  /// the swipe runs off either end; the pager does not wrap.
  int? neighbourIndex(int index, {required bool towardsNext}) {
    if (!showsPager) return null;
    final target = towardsNext ? index + 1 : index - 1;
    return target >= 0 && target < pageCount ? target : null;
  }

  /// Moves the session to page [index] once the swipe has settled: true when
  /// that exercise is now (or already was) the current one. A locked session
  /// refuses and starts the notice; a page that no longer exists changes nothing.
  Future<bool> land(int index) async {
    final all = rows;
    if (index < 0 || index >= all.length) return false;
    if (all[index].isCurrent) return true;
    if (isLocked) {
      noteLockedSwipe();
      return false;
    }
    return menu.jump(all[index].slotId);
  }

  void noteLockedSwipe() {
    _noticeUntil = _clock().add(WatchPagerCopy.noticeDuration);
  }

  /// Whether the locked notice shows at [instant]: until 1.5 s after the swipe.
  bool noticeVisible(DateTime instant) {
    final until = _noticeUntil;
    return until != null && instant.isBefore(until);
  }
}
