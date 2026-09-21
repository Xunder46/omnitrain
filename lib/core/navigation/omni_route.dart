import 'package:flutter/material.dart';
import '../../widgets/layout/omni_gradient_background.dart';

/// Shared route primitive used for every screen-level navigation push
/// in OmniTrain. Wraps the destination page in [OmniGradientBackground]
/// so the route fully occludes any route beneath it during transitions,
/// eliminating the bleed-through bug that occurs when every Scaffold is
/// transparent and `opaque == false`.
///
/// Uses [CupertinoPageTransitionsBuilder] on all platforms (slide + edge-swipe-back
/// on iOS/macOS) for a consistent, smooth transition everywhere.
///
/// See docs/navigation_contract.md for the rule: raw MaterialPageRoute /
/// PageRouteBuilder outside this module is a code-review blocker.
class OmniRoute<T> extends PageRoute<T> {
  OmniRoute({
    required this.builder,
    super.settings,
    this.fullscreenDialog = false,
    this.maintainState = true,
  });

  final WidgetBuilder builder;

  @override
  final bool fullscreenDialog;

  @override
  final bool maintainState;

  @override
  bool get opaque => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return OmniGradientBackground(child: builder(context));
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const builder = CupertinoPageTransitionsBuilder();
    return builder.buildTransitions<T>(
      this,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}

/// Fade variant used for the splash→home transition.
/// Same gradient-wrapping guarantees as [OmniRoute]; no bleed-through.
class OmniFadeRoute<T> extends PageRoute<T> {
  OmniFadeRoute({
    required this.builder,
    super.settings,
    this.transitionDuration = const Duration(milliseconds: 600),
    this.maintainState = true,
  });

  final WidgetBuilder builder;

  @override
  final Duration transitionDuration;

  @override
  final bool maintainState;

  @override
  bool get opaque => true;

  @override
  bool get fullscreenDialog => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return OmniGradientBackground(child: builder(context));
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(opacity: animation, child: child);
  }
}
