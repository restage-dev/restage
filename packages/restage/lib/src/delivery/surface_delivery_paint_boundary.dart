import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart' show Surface;

import '../runtime/error_boundary.dart' show canReportRenderSuccessAt;

import 'surface_delivery_receipt.dart';
import 'surface_delivery_receipt_batch.dart';
import 'surface_delivery_receipt_uploader.dart';

/// Closes a surface's delivery receipt on its first paint, measuring from the
/// moment this boundary mounted.
@internal
final class SurfaceDeliveryPaintBoundary extends StatefulWidget {
  /// Observes the mount of [resolved], the object its resolution was reported for.
  const SurfaceDeliveryPaintBoundary({
    super.key,
    required Object? resolved,
    required this.child,
  })  : _resolved = resolved,
        _surfaceType = null,
        _surfaceSlug = null;

  /// Observes a mount that holds no reference to its resolved object.
  const SurfaceDeliveryPaintBoundary.forSurface({
    super.key,
    required Surface surfaceType,
    required String surfaceSlug,
    required this.child,
  })  : _resolved = null,
        _surfaceType = surfaceType,
        _surfaceSlug = surfaceSlug;

  final Object? _resolved;
  final Surface? _surfaceType;
  final String? _surfaceSlug;
  final Widget child;

  SurfaceDeliveryReceiptHandle? _handle() {
    final resolved = _resolved;
    if (resolved != null) return surfaceDeliveryReceiptFor(resolved);
    final surfaceType = _surfaceType;
    final slug = _surfaceSlug;
    if (surfaceType == null || slug == null) return null;
    return SurfaceDeliveryReceiptBatch.instance.latestFor(surfaceType, slug);
  }

  @override
  State<SurfaceDeliveryPaintBoundary> createState() =>
      _SurfaceDeliveryPaintBoundaryState();
}

final class _SurfaceDeliveryPaintBoundaryState
    extends State<SurfaceDeliveryPaintBoundary> {
  final Stopwatch _sinceMount = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    SurfaceDeliveryReceiptUploader.instance.retain();
  }

  @override
  void dispose() {
    SurfaceDeliveryReceiptUploader.instance.release();
    super.dispose();
  }

  void _painted() => widget._handle()?.painted(_sinceMount.elapsed);

  @override
  Widget build(BuildContext context) =>
      _PaintObserver(onPainted: _painted, child: widget.child);
}

/// Marks the receipt for [resolved] as failed before or instead of a paint.
@internal
void markSurfaceDeliveryRenderFailed(
  Object? resolved, {
  SurfaceDeliveryReceiptReason reason = SurfaceDeliveryReceiptReason.none,
}) {
  if (resolved == null) return;
  surfaceDeliveryReceiptFor(resolved)?.failed(reason);
}

/// Marks the latest receipt for [surfaceSlug] as failed.
@internal
void markSurfaceDeliveryRenderFailedFor(
  Surface surfaceType,
  String surfaceSlug, {
  SurfaceDeliveryReceiptReason reason = SurfaceDeliveryReceiptReason.none,
}) {
  SurfaceDeliveryReceiptBatch.instance
      .latestFor(surfaceType, surfaceSlug)
      ?.failed(reason);
}

/// Reports a load once, after the frame in which [child] first painted for
/// [load]. A new [load] re-arms it.
@internal
final class SurfaceLoadPaint extends StatefulWidget {
  /// Calls [onPainted] after [child]'s first painted frame for [load].
  const SurfaceLoadPaint({
    super.key,
    required this.load,
    required this.onPainted,
    this.requireRenderSuccess = false,
    required this.child,
  });

  /// Whether a paint the enclosing error boundary or lease counts as failed
  /// is ignored, for hosts that settle on paint without a commit of their own.
  final bool requireRenderSuccess;

  /// The load this paint settles; identity only.
  final Object? load;

  /// Settles the load; runs after the frame, outside paint.
  final VoidCallback onPainted;

  final Widget child;

  @override
  State<SurfaceLoadPaint> createState() => _SurfaceLoadPaintState();
}

final class _SurfaceLoadPaintState extends State<SurfaceLoadPaint> {
  Object? _builtFor = const Object();

  void _afterFrame() {
    final report = widget.onPainted;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.requireRenderSuccess && !canReportRenderSuccessAt(context)) {
        // The failure path settles the load with what paints instead.
        return;
      }
      report();
    });
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    // A parent-data child must stay its parent's direct child, so it reports
    // after the frame that built it.
    if (child is ParentDataWidget) {
      if (!identical(_builtFor, widget.load)) {
        _builtFor = widget.load;
        _afterFrame();
      }
      return child;
    }
    return _PaintObserver(
      token: widget.load,
      onPainted: _afterFrame,
      child: child,
    );
  }
}

final class _PaintObserver extends SingleChildRenderObjectWidget {
  const _PaintObserver({
    required this.onPainted,
    this.token,
    required super.child,
  });

  final VoidCallback onPainted;
  final Object? token;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPaintObserver(onPainted, token);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPaintObserver renderObject,
  ) {
    renderObject
      ..onPainted = onPainted
      ..token = token;
  }
}

/// Reports the first paint; a build failure never reaches paint and is
/// reported by the mount's error boundary instead.
final class _RenderPaintObserver extends RenderProxyBox {
  _RenderPaintObserver(this.onPainted, this._token);

  VoidCallback onPainted;
  Object? _token;
  bool _reported = false;

  set token(Object? value) {
    if (identical(value, _token)) return;
    _token = value;
    _reported = false;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (_reported) return;
    _reported = true;
    onPainted();
  }
}
