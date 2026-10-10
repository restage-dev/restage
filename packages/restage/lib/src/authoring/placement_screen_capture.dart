import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show kDebugMode, listEquals, visibleForTesting;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show TargetCoordinate;
import 'package:restage_shared/restage_shared.dart';

import '../runtime/placement_discovery.dart';

/// A local image and its immutable target-free authored frame.
final class PlacementScreenSample {
  PlacementScreenSample._({required this.pngBytes, required this.capture});

  /// Defensive immutable PNG bytes; exporting them does not upload content.
  final Uint8List pngBytes;

  /// Complete offline build and every occurrence in the captured frame.
  final PlacementScreenCaptureV1 capture;

  /// Canonical target-free capture evidence for local export.
  PlacementScreenCaptureV1 toCaptureManifest() => capture;

  /// Binds the local evidence to an authoring tool's authenticated target.
  PlacementScreenSampleManifestV1 toManifest(
          {required TargetCoordinate target}) =>
      capture.bindTarget(target);
}

/// Captures a debug Flutter view or an explicitly selected repaint boundary.
///
/// Native platform views are refused. Capture and export make no network calls;
/// the returned PNG and canonical capture can be saved for explicit review.
/// Authored screen and flow fallback bounds remain available to local capture;
/// runtime bounds require a committed paint signal from the host.
Future<PlacementScreenSample> capturePlacementScreenSample({
  required BuildContext context,
  required String screenLabel,
  GlobalKey? repaintBoundaryKey,
  double pixelRatio = 1,
}) async {
  if (!kDebugMode) {
    throw UnsupportedError(
        'Placement screen capture is available only in debug builds.');
  }
  final scale = PlacementRasterScaleV1.fromRequestedScale(pixelRatio);
  final view = _contextView(context);
  final initialBuild = PlacementDiscovery.instance.buildContract;
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted ||
      !identical(_contextView(context), view) ||
      PlacementDiscovery.instance.buildContract.appBuildContractHash !=
          initialBuild.appBuildContractHash) {
    throw const FormatException(
        'The selected Flutter view or build became stale.');
  }
  final boundary = _boundary(repaintBoundaryKey, view);
  final frame =
      PlacementDiscovery.instance.captureFrame(view: view, boundary: boundary);
  final root = boundary ?? view;
  _requireFlutterRaster(root);
  final layer = root.debugLayer;
  if (layer is! OffsetLayer) {
    throw const FormatException('The Flutter frame is not painted.');
  }
  final rootTransform = view.configuration.toMatrix();
  final rootLayer = view.debugLayer;
  final rootScale = view.configuration.devicePixelRatio;
  if (rootLayer is! TransformLayer ||
      !rootScale.isFinite ||
      rootScale <= 0 ||
      !listEquals(rootLayer.transform?.storage, rootTransform.storage)) {
    throw const FormatException(
        'The Flutter view root transform is unsupported.');
  }
  final size = boundary?.size ?? view.size;
  _requireRasterBound(size, scale.value);
  final rasterize = boundary == null
      ? () =>
          layer.toImage(view.paintBounds, pixelRatio: scale.value / rootScale)
      : () => boundary.toImage(pixelRatio: scale.value);
  final image =
      await (debugPlacementScreenRasterizer?.call(rasterize) ?? rasterize());
  try {
    final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
    if (encoded == null) {
      throw const FormatException('Flutter PNG encoding failed.');
    }
    if (!frame.isCurrent ||
        !context.mounted ||
        !identical(_contextView(context), view) ||
        !identical(_boundary(repaintBoundaryKey, view), boundary) ||
        !identical(root.debugLayer, layer) ||
        !listEquals(
            view.configuration.toMatrix().storage, rootTransform.storage)) {
      throw const FormatException('The captured placement frame became stale.');
    }
    final png = validatePlacementScreenSamplePng(encoded.buffer.asUint8List(
      encoded.offsetInBytes,
      encoded.lengthInBytes,
    ));
    final capture = PlacementScreenCaptureV1(
      buildContract: frame.buildContract,
      appBuildContractHash: frame.buildContract.appBuildContractHash,
      screenLabel: screenLabel,
      captureScope: boundary == null
          ? PlacementScreenCaptureScopeV1.flutterView
          : PlacementScreenCaptureScopeV1.explicitBoundary,
      logicalViewport: frame.viewport,
      rasterScale: scale,
      pngWidth: png.width,
      pngHeight: png.height,
      pngByteLength: png.byteLength,
      pngSha256: png.contentHash,
      mounts: frame.mounts,
    );
    return PlacementScreenSample._(pngBytes: png.bytes, capture: capture);
  } finally {
    image.dispose();
  }
}

/// Overrides raster scheduling in focused tests while retaining real encoding.
@visibleForTesting
Future<ui.Image> Function(Future<ui.Image> Function() rasterize)?
    debugPlacementScreenRasterizer;

RenderView _contextView(BuildContext context) {
  if (!context.mounted) {
    throw const FormatException('The capture context is detached.');
  }
  final view = placementOwningView(context.findRenderObject());
  if (view == null) {
    throw const FormatException('The capture has no owning Flutter view.');
  }
  return view;
}

RenderRepaintBoundary? _boundary(GlobalKey? key, RenderView view) {
  if (key == null) return null;
  final object = key.currentContext?.findRenderObject();
  if (object is! RenderRepaintBoundary ||
      !object.attached ||
      !identical(placementOwningView(object), view)) {
    throw const FormatException(
        'The explicit capture boundary is detached or belongs to another view.');
  }
  return object;
}

void _requireRasterBound(Size size, double scale) {
  final width = (size.width * scale).ceil();
  final height = (size.height * scale).ceil();
  if (width <= 0 ||
      height <= 0 ||
      width > placementScreenSampleMaxDimension ||
      height > placementScreenSampleMaxDimension ||
      height > placementScreenSampleMaxDecodedBytes ~/ (width * 4 + 1)) {
    throw const FormatException(
        'The capture exceeds the bounded PNG raster limits.');
  }
}

void _requireFlutterRaster(RenderObject root) {
  void visit(RenderObject object) {
    if (object is PlatformViewRenderBox ||
        object is RenderUiKitView ||
        object is RenderAppKitView) {
      throw UnsupportedError(
          'Native platform views cannot be exported as a Flutter screen sample.');
    }
    object.visitChildren(visit);
  }

  visit(root);
}
