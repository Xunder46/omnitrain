/// The Wear wrist's swipeable exercise pages over the logging surface.
///
/// Plan: `docs/plans/2026-11-21-287-wear-swipe-pager-plan/2026-11-21-287-wear-swipe-pager-plan.md`
/// (D-28703..D-28708). The Dart counterpart of `WatchLoggingPagerView.swift`:
/// one logger, and a swipe switches to the neighbouring exercise. The session
/// moves only when the swipe has settled, through the menu's own jump. While a
/// work clock runs there is no paging: a swipe gives a short vibration and a
/// notice. While a landing is in flight the logger ignores touches, so `Log`
/// cannot write to the exercise being left (the Wear stand-in for the Apple
/// focus, D-28703).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/omni_theme.dart';
import 'watch_logging_screen.dart';
import 'watch_logging_state.dart';
import 'watch_menu_state.dart';
import 'watch_pager_state.dart';

class WatchLoggingPager extends StatefulWidget {
  const WatchLoggingPager({
    super.key,
    required this.menu,
    required this.logging,
    this.onMoved,
    this.clock,
  });

  /// The menu the pager moves the session through: the one the shell's Menu
  /// button opens, so both share one rule.
  final WatchMenuState menu;
  final WatchLoggingState logging;

  /// Called after a swipe has moved the session, so the shell can follow it.
  final VoidCallback? onMoved;

  /// The clock the locked notice reads; tests pass their own.
  final DateTime Function()? clock;

  @override
  State<WatchLoggingPager> createState() => _WatchLoggingPagerState();
}

class _WatchLoggingPagerState extends State<WatchLoggingPager> {
  /// A little longer than the thing it waits for, so the repaint lands after it.
  static const Duration _grace = Duration(milliseconds: 100);

  late final WatchPagerState _pager = WatchPagerState(
    menu: widget.menu,
    clock: widget.clock,
  );

  double _across = 0;
  bool _landing = false;

  /// The slot the user's own swipe is heading for, and the side it enters from.
  /// The slide runs only while the current slot is this one (D-28705).
  String? _swipeTarget;
  bool _fromTrailing = true;

  /// The page on screen: a new number each time the current slot changes, so a
  /// page that is leaving is never mistaken for one that has come back (a swipe
  /// onward and straight back keeps two entries for the same exercise alive for
  /// the length of the slide).
  String? _shownSlot;
  int _page = 0;

  Timer? _noticeTimer;
  Timer? _slideTimer;

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _slideTimer?.cancel();
    super.dispose();
  }

  DateTime _now() => (widget.clock ?? DateTime.now)();

  Future<void> _dragEnded() async {
    final across = _across;
    _across = 0;
    if (across.abs() <= WatchPagerCopy.swipeThreshold) return;
    if (_landing) return;

    if (_pager.isLocked) {
      HapticFeedback.heavyImpact();
      _pager.noteLockedSwipe();
      _noticeTimer?.cancel();
      _noticeTimer = Timer(WatchPagerCopy.noticeDuration + _grace, () {
        if (mounted) setState(() {});
      });
      setState(() {});
      return;
    }

    final target = _pager.neighbourIndex(
      _pager.currentIndex,
      towardsNext: across < 0,
    );
    if (target == null) return;
    final targetSlot = _pager.rows[target].slotId;

    HapticFeedback.selectionClick();
    setState(() {
      _landing = true;
      _fromTrailing = across < 0;
      _swipeTarget = targetSlot;
    });
    // A write that fails (a full disk) must not leave the logger deaf to
    // touches: the landing ends either way and the session stays where it was.
    var moved = false;
    try {
      moved = await _pager.land(target);
    } on Object catch (error, stack) {
      debugPrint(
        'OmniTrain wrist swipe could not move the session: $error\n$stack',
      );
    }
    if (!mounted) return;
    _slideTimer?.cancel();
    _slideTimer = Timer(WatchPagerCopy.slideDuration + _grace, () {
      _swipeTarget = null;
    });
    setState(() => _landing = false);
    if (moved) widget.onMoved?.call();
  }

  @override
  Widget build(BuildContext context) {
    final slotId = _pager.currentSlotId ?? '';
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final animate = _swipeTarget != null && _swipeTarget == slotId;
    if (slotId != _shownSlot) {
      _shownSlot = slotId;
      _page += 1;
    }
    final key = ValueKey<int>(_page);

    final logger = KeyedSubtree(
      key: key,
      child: AbsorbPointer(
        absorbing: _landing,
        child: WatchLoggingScreen(
          state: widget.logging,
          pageLabel: _pager.pageLabel,
        ),
      ),
    );

    final switcher = AnimatedSwitcher(
      duration: WatchPagerCopy.slideDuration,
      switchInCurve: Curves.easeOut,
      transitionBuilder: (child, animation) {
        // The page being left goes at once (Apple `removal: .identity`).
        if (child.key != key) return const SizedBox.shrink();
        // A move the user did not make shows at once, with no slide.
        if (!animate) return child;
        final fade = FadeTransition(opacity: animation, child: child);
        if (reduceMotion) return fade;
        return SlideTransition(
          position: Tween<Offset>(
            begin: Offset(_fromTrailing ? 1 : -1, 0),
            end: Offset.zero,
          ).animate(animation),
          child: fade,
        );
      },
      child: logger,
    );

    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _across = 0,
      onHorizontalDragUpdate: (details) => _across += details.delta.dx,
      onHorizontalDragEnd: (_) => unawaited(_dragEnded()),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(child: switcher),
          if (_pager.noticeVisible(_now()))
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Material(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(
                      OmniTheme.buttonUtilityRadius,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(
                        WatchLoggingScreen.surfaceInset,
                      ),
                      child: Text(
                        WatchPagerCopy.lockedNotice,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
