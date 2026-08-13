import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show internal, mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:restage/restage.dart';
import 'package:restage_preview_host/restage_preview_host.dart';
import 'package:rfw/rfw.dart' hide WidgetLibrary;

import 'render_completion_tracker.dart';
import 'render_bundle_view_binding.dart';

/// Starts the minimal render-bundle application.
void runRestagePreviewHarness({
  required RenderMessageTransport transport,
  required RenderBundleManifest manifest,
  required RenderEngine engine,
  required VoidCallback registerCustomerWidgets,
  required BundleInitHandler initialize,
  List<int> supportedVersions = const <int>[renderProtocolV1],
  String entryWidgetName = 'Preview',
}) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    RestagePreviewHarnessApp(
      transport: transport,
      manifest: manifest,
      engine: engine,
      registerCustomerWidgets: registerCustomerWidgets,
      supportedVersions: supportedVersions,
      initialize: initialize,
      entryWidgetName: entryWidgetName,
    ),
  );
}

/// Starts the production render-bundle application.
///
/// Unlike the local preview entrypoint, this resolves the root privately from
/// each exact RFW blob. No entry name is carried on the render wire.
void runRestageRenderBundleHarness({
  required RenderMessageTransport transport,
  required RenderBundleManifest manifest,
  required RenderEngine engine,
  required VoidCallback registerCustomerWidgets,
  required BundleInitHandler initialize,
  List<int> supportedVersions = const <int>[renderProtocolV1],
}) {
  final rasterBinding = RenderBundleViewBinding();
  runApp(
    RestagePreviewHarnessApp.renderBundleWithRasterController(
      transport: transport,
      manifest: manifest,
      engine: engine,
      registerCustomerWidgets: registerCustomerWidgets,
      supportedVersions: supportedVersions,
      initialize: initialize,
      rasterController: rasterBinding,
    ),
  );
}

/// Application widget that connects protocol requests to the raw render core.
class RestagePreviewHarnessApp extends StatefulWidget {
  const RestagePreviewHarnessApp({
    required this.transport,
    required this.manifest,
    required this.engine,
    required this.registerCustomerWidgets,
    required this.initialize,
    this.supportedVersions = const <int>[renderProtocolV1],
    this.entryWidgetName = 'Preview',
    super.key,
  })  : _rasterController = null,
        _resolveEntryFromBlob = false;

  /// Creates the fixed per-blob entry-selection mode used by built bundles.
  const RestagePreviewHarnessApp.renderBundle({
    required this.transport,
    required this.manifest,
    required this.engine,
    required this.registerCustomerWidgets,
    required this.initialize,
    this.supportedVersions = const <int>[renderProtocolV1],
    super.key,
  })  : entryWidgetName = 'Preview',
        _rasterController = null,
        _resolveEntryFromBlob = true;

  /// Creates built-bundle mode with its private backing-raster controller.
  @internal
  const RestagePreviewHarnessApp.renderBundleWithRasterController({
    required this.transport,
    required this.manifest,
    required this.engine,
    required this.registerCustomerWidgets,
    required this.initialize,
    required RenderBundleRasterController rasterController,
    this.supportedVersions = const <int>[renderProtocolV1],
    super.key,
  })  : entryWidgetName = 'Preview',
        _rasterController = rasterController,
        _resolveEntryFromBlob = true;

  final RenderMessageTransport transport;
  final RenderBundleManifest manifest;
  final RenderEngine engine;
  final VoidCallback registerCustomerWidgets;
  final List<int> supportedVersions;
  final BundleInitHandler initialize;
  final String entryWidgetName;
  final bool _resolveEntryFromBlob;
  final RenderBundleRasterController? _rasterController;

  @override
  State<RestagePreviewHarnessApp> createState() =>
      _RestagePreviewHarnessAppState();
}

class _RestagePreviewHarnessAppState extends State<RestagePreviewHarnessApp> {
  final GlobalKey _frameKey = GlobalKey();
  final GlobalKey _snapshotKey = GlobalKey();
  late final RenderProtocolServer _server;
  late final GeometryRegistry _geometryRegistry;
  late final StreamSubscription<Map<String, Rect>> _geometrySubscription;
  late final List<RestageWidgetLibraryRegistration> _registrations;
  final RenderCompletionTracker _completions = RenderCompletionTracker();
  RenderRequest? _request;
  RemoteWidgetLibrary? _library;
  String? _activeEntryWidgetName;
  Map<String, Rect>? _lastGeometry;
  int? _latestRequestedEpoch;

  @override
  void initState() {
    super.initState();
    widget.registerCustomerWidgets();
    _registrations = completeManifestWidgetRegistrations(
      manifest: widget.manifest,
      registrations: Restage.widgetLibraryRegistrations,
    );
    _geometryRegistry = GeometryRegistry(
      frameRenderBox: () =>
          _frameKey.currentContext?.findRenderObject() as RenderBox?,
    );
    _geometrySubscription = _geometryRegistry.snapshots.listen((rects) {
      final epoch = _request?.epoch;
      if (epoch == null || mapEquals(rects, _lastGeometry)) return;
      _lastGeometry = Map<String, Rect>.unmodifiable(rects);
      _server.publishGeometry(epoch, rects);
    });
    _server = RenderProtocolServer(
      transport: widget.transport,
      manifest: widget.manifest,
      engine: widget.engine,
      supportedVersions: widget.supportedVersions,
      scheduleFrame: (callback) {
        WidgetsBinding.instance.addPostFrameCallback((_) => callback());
      },
      initialize: widget.initialize,
      render: _render,
      snapshot: _snapshot,
    )..start();
  }

  Future<Uint8List> _snapshot(int epoch, String path) async {
    final request = _request;
    final entryWidgetName = _activeEntryWidgetName;
    if (request == null ||
        request.epoch != epoch ||
        entryWidgetName == null ||
        path != DocumentPathCodec.encode(<Object>[entryWidgetName])) {
      throw const FormatException('Snapshot target is not current.');
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _request?.epoch != epoch) {
      throw const FormatException('Snapshot target became stale.');
    }
    final boundary = _snapshotKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) {
      throw const FormatException('Snapshot frame is not painted.');
    }
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        throw const FormatException('Snapshot encoding failed.');
      }
      return Uint8List.fromList(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  }

  Future<BundleRenderResult> _render(RenderRequest request) async {
    final completion = _completions.begin(request.epoch);
    _latestRequestedEpoch = request.epoch;
    _lastGeometry = null;
    final rasterController = widget._rasterController;
    if (rasterController != null) {
      try {
        final ready = await rasterController.prepare(request.env);
        if (!ready || _latestRequestedEpoch != request.epoch) {
          // Handed back pending on purpose: this future is completed by
          // whichever render pass settles the epoch, so awaiting it here would
          // both stall inside the guard and route its outcome through the
          // catch below.
          // ignore: unawaited_return_in_try_block
          return completion;
        }
      } on Object {
        const failure = BundleRenderFailure(
          'Unable to prepare the render bundle viewport.',
        );
        _completions.completeFailure(request.epoch, failure);
        return completion;
      }
    }
    if (widget._resolveEntryFromBlob) {
      try {
        final library = decodeLibraryBlob(request.blob);
        final entryWidgetName = selectRenderBundleEntryWidgetName(library);
        setState(() {
          _request = request;
          _library = library;
          _activeEntryWidgetName = entryWidgetName;
        });
      } on Object {
        const failure = BundleRenderFailure(
          'Unable to select the render bundle entry.',
        );
        setState(() {
          _request = null;
          _library = null;
          _activeEntryWidgetName = null;
        });
        _completions.completeFailure(request.epoch, failure);
      }
    } else {
      setState(() {
        _request = request;
        _library = null;
        _activeEntryWidgetName = widget.entryWidgetName;
      });
    }
    return completion;
  }

  void _onRenderEvent(RenderEvent event) {
    switch (event) {
      case Settled(:final epoch):
        final geometry = _geometryRegistry.capture();
        _lastGeometry = geometry;
        _completions.completeSuccess(
          epoch,
          geometry: geometry,
        );
      case RenderError(:final epoch, :final message, :final path):
        final failure = BundleRenderFailure(message, path: path);
        final completed = _completions.completeFailure(epoch, failure);
        if (!completed) {
          _server.reportRenderFailure(epoch, failure);
        }
      case ProtocolError():
        break;
    }
  }

  @override
  void dispose() {
    widget._rasterController?.cancelPending();
    _completions.completeAllWithFailure(
      const BundleRenderFailure('Render host was disposed.'),
    );
    unawaited(_geometrySubscription.cancel());
    _geometryRegistry.dispose();
    unawaited(_server.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: _snapshotKey,
          child: SizedBox(
            key: _frameKey,
            width: _request?.env.frame.width,
            height: _request?.env.frame.height,
            child: _buildRenderSurface(),
          ),
        ),
      ),
    );
  }

  Widget _buildRenderSurface() {
    final request = _request;
    final library = _library;
    final entryWidgetName = _activeEntryWidgetName;
    if (request == null || entryWidgetName == null) {
      return const SizedBox.shrink();
    }
    if (library == null) {
      return RawRfwRenderSurface(
        epoch: request.epoch,
        blob: request.blob,
        data: request.data,
        environment: request.env,
        registrations: _registrations,
        geometryRegistry: _geometryRegistry,
        entryWidgetName: entryWidgetName,
        onRemoteEvent: (_, __) {},
        onRenderEvent: _onRenderEvent,
      );
    }
    return RawRfwRenderSurface.library(
      epoch: request.epoch,
      library: library,
      data: request.data,
      environment: request.env,
      registrations: _registrations,
      geometryRegistry: _geometryRegistry,
      entryWidgetName: entryWidgetName,
      onRemoteEvent: (_, __) {},
      onRenderEvent: _onRenderEvent,
    );
  }
}
