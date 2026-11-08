import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'error_boundary.dart';

/// A host's two fallback builders, read together.
///
/// A host shows fresh published content, then the last good copy on the
/// device, then the bundled copy. When none of them can render it reaches the
/// rung these builders fill: [fallbackBuilder], or the compiled original when
/// it is null, or nothing on a host without one. [errorBuilder] shows instead
/// after the load advanced, or when that rung would show nothing.
@internal
@immutable
final class SurfaceUnavailablePolicy<E extends Object> {
  /// The policy a host's [fallbackBuilder] and [errorBuilder] describe.
  const SurfaceUnavailablePolicy({this.fallbackBuilder, this.errorBuilder});

  /// Shown in place of the compiled original.
  final WidgetBuilder? fallbackBuilder;

  /// Shown for a failure after the load advanced, or with nothing below it.
  final Widget Function(BuildContext context, E error)? errorBuilder;
}

/// What a host shows for a failed load.
@internal
enum SurfaceUnavailableView {
  /// The fallback builder: the original.
  original,

  /// The error builder.
  error,

  /// Nothing.
  nothing,
}

/// The view [policy] shows for a failed load, given whether that load
/// [advanced] and whether a compiled original [hasOriginal] still fills the
/// rung below the builders.
@internal
SurfaceUnavailableView surfaceUnavailableView<E extends Object>(
  SurfaceUnavailablePolicy<E> policy, {
  required bool advanced,
  bool hasOriginal = false,
}) {
  // With nothing else to show, the error builder beats a blank host.
  if (policy.errorBuilder != null &&
      (advanced || policy.fallbackBuilder == null && !hasOriginal)) {
    return SurfaceUnavailableView.error;
  }
  if (policy.fallbackBuilder == null) return SurfaceUnavailableView.nothing;
  return SurfaceUnavailableView.original;
}

/// Whether the host's compiled original fills [policy]'s rung; a fallback
/// builder takes that rung instead.
@internal
bool surfaceUnavailableUsesCompiledOriginal<E extends Object>(
        SurfaceUnavailablePolicy<E> policy) =>
    policy.fallbackBuilder == null;

/// The builder [policy] shows for a failed load, or null for nothing.
@internal
Widget Function(BuildContext context, E error)?
    surfaceUnavailableBuilder<E extends Object>(
  SurfaceUnavailablePolicy<E> policy, {
  required bool advanced,
}) =>
        switch (surfaceUnavailableView(policy, advanced: advanced)) {
          SurfaceUnavailableView.original => (context, _) =>
              policy.fallbackBuilder!(context),
          SurfaceUnavailableView.error => policy.errorBuilder,
          SurfaceUnavailableView.nothing => null,
        };

/// Guards the widget a host's builders show: if it throws while building,
/// nothing shows in its place and [onFailed] runs once after the frame. The
/// error still reaches `FlutterError.onError`, once each time the guard is
/// mounted.
@internal
Widget guardSurfaceUnavailableWidget({
  required String debugLabel,
  required VoidCallback onFailed,
  required Widget child,
}) =>
    RuntimeErrorBoundary(
      debugLabel: debugLabel,
      guardsRendering: false,
      onError: (_, __) => onFailed(),
      errorReplacement: (_, __, ___) => const SizedBox.shrink(),
      child: child,
    );
