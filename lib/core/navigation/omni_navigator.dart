import 'package:flutter/widgets.dart';
import 'omni_route.dart';

/// Centralized navigation helper. All screen-level navigation in OmniTrain
/// goes through this class. Callers never instantiate route objects directly.
///
/// Cross-cutting concerns (analytics, deep links, auth gates) are added here
/// in a single place rather than patched across every call site.
abstract final class OmniNavigator {
  /// Push [builder] onto the navigator using the standard [OmniRoute]
  /// (platform-appropriate slide transition + gradient background).
  static Future<T?> push<T>(
    BuildContext context,
    WidgetBuilder builder, {
    bool fullscreenDialog = false,
    RouteSettings? settings,
  }) {
    return Navigator.of(context).push(
      OmniRoute<T>(
        builder: builder,
        settings: settings,
        fullscreenDialog: fullscreenDialog,
      ),
    );
  }

  /// Replace the current route with [builder] using [OmniRoute].
  static Future<T?> pushReplacement<T, TO>(
    BuildContext context,
    WidgetBuilder builder, {
    TO? result,
    RouteSettings? settings,
  }) {
    return Navigator.of(context).pushReplacement(
      OmniRoute<T>(builder: builder, settings: settings),
      result: result,
    );
  }

  /// Replace the current route with [builder] using the fade variant
  /// [OmniFadeRoute]. Used for the splash→home transition.
  static Future<T?> pushReplacementFade<T, TO>(
    BuildContext context,
    WidgetBuilder builder, {
    Duration transitionDuration = const Duration(milliseconds: 600),
    TO? result,
    RouteSettings? settings,
  }) {
    return Navigator.of(context).pushReplacement(
      OmniFadeRoute<T>(
        builder: builder,
        settings: settings,
        transitionDuration: transitionDuration,
      ),
      result: result,
    );
  }

  /// Pop routes until [predicate] returns true.
  static void popUntil(BuildContext context, RoutePredicate predicate) {
    Navigator.of(context).popUntil(predicate);
  }
}
