import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:restage/restage.dart';
import 'render_core.dart';
import 'package:rfw/rfw.dart' hide WidgetLibrary;

import 'render_completion_tracker.dart';
import 'render_bundle_view_binding.dart';

/// Application widget that connects protocol requests to the raw render core.
class RenderHostApp extends StatefulWidget {
  /// Renders each blob's root under [entryWidgetName], or the root resolved
  /// from the blob itself when it is null.
  const RenderHostApp({
    required this.transport,
    required this.manifest,
    required this.engine,
    required this.registerAppWidgets,
    this.supportedVersions = const <int>[renderProtocolV1],
    this.entryWidgetName,
    RenderBundleRasterController? rasterController,
    super.key,
  }) : _rasterController = rasterController;

  final RenderMessageTransport transport;
  final RenderBundleManifest manifest;
  final RenderEngine engine;
  final VoidCallback registerAppWidgets;
  final List<int> supportedVersions;
  final String? entryWidgetName;
  final RenderBundleRasterController? _rasterController;

  @override
  State<RenderHostApp> createState() => _RenderHostAppState();
}

class _RenderHostAppState extends State<RenderHostApp> {
  final GlobalKey _frameKey = GlobalKey();
  final GlobalKey _snapshotKey = GlobalKey();
  late final RenderProtocolServer _server;
  late final GeometryRegistry _geometryRegistry;
  late final StreamSubscription<Map<String, List<GeometryInstance>>>
      _geometrySubscription;
  late final List<RestageWidgetLibraryRegistration> _registrations;
  final RenderCompletionTracker _completions = RenderCompletionTracker();
  RenderRequest? _request;
  RemoteWidgetLibrary? _library;
  String? _activeEntryWidgetName;
  Map<String, List<GeometryInstance>>? _lastGeometry;
  int? _latestRequestedEpoch;

  @override
  void initState() {
    super.initState();
    widget.registerAppWidgets();
    _registrations = completeManifestWidgetRegistrations(
      manifest: widget.manifest,
      registrations: Restage.widgetLibraryRegistrations,
    );
    _geometryRegistry = GeometryRegistry(
      frameRenderBox: () =>
          _frameKey.currentContext?.findRenderObject() as RenderBox?,
    );
    _geometrySubscription =
        _geometryRegistry.instanceSnapshots.listen((instances) {
      final epoch = _request?.epoch;
      if (epoch == null || geometryInstancesEqual(instances, _lastGeometry)) {
        return;
      }
      _lastGeometry = instances;
      _server.publishGeometry(
        epoch,
        _geometryRegistry.capture(),
        instances: instances,
      );
    });
    _server = RenderProtocolServer(
      transport: widget.transport,
      manifest: widget.manifest,
      engine: widget.engine,
      supportedVersions: widget.supportedVersions,
      scheduleFrame: (callback) {
        WidgetsBinding.instance.addPostFrameCallback((_) => callback());
      },
      initialize: (_) {},
      render: _render,
      snapshot: _snapshot,
      mount: _render,
      reveal: (path, index) => _geometryRegistry.reveal(path, index: index),
    )..start();
  }

  void _onSurfaceEvent(String name, DynamicMap arguments) {
    final epoch = _request?.epoch;
    if (epoch == null) return;
    switch (_server.publishSurfaceEvent(epoch, name, arguments)) {
      case SurfaceEventPublication.sent:
      case SurfaceEventPublication.inactive:
        break;
      case SurfaceEventPublication.oversize:
        // A surface that fired and reported nothing needs an explanation; the
        // arguments themselves stay out of the log.
        debugPrint(
          'Surface event "$name" was not reported: its arguments exceed what '
          'one message carries.',
        );
    }
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
          // Another render or disposal completes this pending result.
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
    final fixedEntry = widget.entryWidgetName;
    if (fixedEntry == null) {
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
        _activeEntryWidgetName = fixedEntry;
      });
    }
    return completion;
  }

  void _onRenderEvent(RenderEvent event) {
    switch (event) {
      case Settled(:final epoch):
        final instances = _geometryRegistry.captureInstances();
        _lastGeometry = instances;
        _completions.completeSuccess(
          epoch,
          geometry: <String, Rect>{
            for (final entry in instances.entries)
              entry.key: entry.value.first.rect,
          },
          instances: instances,
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
        onRemoteEvent: _onSurfaceEvent,
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
      onRemoteEvent: _onSurfaceEvent,
      onRenderEvent: _onRenderEvent,
    );
  }
}
