import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:restage_shared/restage_shared.dart';

import 'geometry_validation.dart';
import 'manifest.dart';
import 'protocol.dart';
import 'snapshot_path_validation.dart';
import 'wire_json.dart';

typedef BundleRenderHandler = Future<BundleRenderResult> Function(
    RenderRequest request);
typedef BundleInitHandler = void Function(BundleInitialization initialization);
typedef BundleSnapshotHandler = Future<Uint8List> Function(
  int epoch,
  String path,
);

/// Latest accepted logical frame and font prewarm request from the shell.
final class BundleInitialization {
  BundleInitialization({
    required this.frame,
    required Iterable<String> fontUrls,
  }) : fontUrls = List<String>.unmodifiable(fontUrls) {
    validatePositiveFrame(frame, argumentName: 'frame');
  }

  final Size frame;
  final List<String> fontUrls;
}

/// Successful output from the first successful painted frame of a render.
final class BundleRenderResult {
  BundleRenderResult({
    Iterable<RenderDiagnostic> diagnostics = const <RenderDiagnostic>[],
    Map<String, Rect> geometry = const <String, Rect>{},
    Map<String, Object?>? timings,
  })  : diagnostics = List<RenderDiagnostic>.unmodifiable(diagnostics),
        geometry = snapshotGeometry(geometry, argumentName: 'geometry'),
        timings = timings == null
            ? null
            : snapshotWireMap(timings, argumentName: 'timings');

  final List<RenderDiagnostic> diagnostics;
  final Map<String, Rect> geometry;
  final Map<String, Object?>? timings;
}

/// A controlled render failure suitable for the wire's public diagnostic.
final class BundleRenderFailure implements Exception {
  const BundleRenderFailure(this.message, {this.path});

  final String message;
  final String? path;
}

/// Bundle-side server for the render protocol.
final class RenderProtocolServer {
  RenderProtocolServer({
    required RenderMessageTransport transport,
    required this.manifest,
    required this.engine,
    required Iterable<int> supportedVersions,
    required RenderFrameScheduler scheduleFrame,
    required BundleInitHandler initialize,
    required BundleRenderHandler render,
    BundleSnapshotHandler? snapshot,
  })  : _transport = transport,
        _supportedVersions = _snapshotSupportedVersions(supportedVersions),
        _scheduleFrame = scheduleFrame,
        _initialize = initialize,
        _render = render,
        _snapshot = snapshot;

  final RenderMessageTransport _transport;
  final RenderBundleManifest manifest;
  final RenderEngine engine;
  final Set<int> _supportedVersions;
  final RenderFrameScheduler _scheduleFrame;
  final BundleInitHandler _initialize;
  final BundleRenderHandler _render;
  final BundleSnapshotHandler? _snapshot;

  StreamSubscription<RenderTransportMessage>? _subscription;
  String? _lockedOrigin;
  int? _selectedVersion;
  int? _currentEpoch;
  final Set<int> _settledEpochs = <int>{};
  final Set<int> _terminatedEpochs = <int>{};
  final Map<int, int> _geometryGenerations = <int, int>{};
  final Map<int, Map<String, Rect>> _pendingGeometry =
      <int, Map<String, Rect>>{};
  final Set<int> _scheduledGeometry = <int>{};
  final Set<String> _snapshotRequests = <String>{};
  bool _disposed = false;
  BundleInitialization? _latestInitialization;

  /// Origin captured from the first fully valid supported init or render.
  String? get lockedOrigin => _lockedOrigin;

  /// Latest fully valid supported init accepted from the locked origin.
  BundleInitialization? get latestInitialization => _latestInitialization;

  void start() {
    if (_disposed) throw StateError('A disposed render server cannot restart.');
    if (_subscription != null) return;
    _subscription = _transport.messages.listen(_receive);
    _transport.send(
      <String, Object?>{
        'type': 'ready',
        'protocolVersions': (_supportedVersions.toList()..sort()),
        if (_snapshot != null)
          'capabilities': const <String>[renderSnapshotCapability],
        'manifest': manifest.toJson(),
        'engine': engine.toJson(),
      },
      targetOrigin: '*',
    );
  }

  void _receive(RenderTransportMessage message) {
    if (_disposed) return;
    final origin = _lockedOrigin;
    if (origin != null && origin != message.origin) return;
    final payload = _asMap(message.payload);
    if (payload == null) return;
    final type = payload['type'];
    if (type != 'init' && type != 'render' && type != 'snapshotRequest') {
      return;
    }
    try {
      if (type == 'snapshotRequest') {
        final snapshot = _snapshot;
        if (snapshot == null) return;
        _receiveSnapshotRequest(message.origin, payload, snapshot);
        return;
      }
      if (type == 'init') {
        final parsed = _parseInit(payload);
        final version = parsed.version;
        if (!_supportedVersions.contains(version)) {
          _sendProtocolErrorTo(
            message.origin,
            'Unsupported render protocol version.',
            attemptedVersion: version,
          );
          return;
        }
        if (!_selectOrAccept(message.origin, version)) return;
        _latestInitialization = parsed.initialization;
        _initialize(parsed.initialization);
        return;
      }

      final parsed = _parseRender(payload);
      final version = parsed.version;
      if (!_supportedVersions.contains(version)) {
        _sendProtocolErrorTo(
          message.origin,
          'Unsupported render protocol version.',
          attemptedVersion: version,
        );
        return;
      }
      if (!_selectOrAccept(message.origin, version)) return;
      final request = parsed.request;
      final current = _currentEpoch;
      if (current != null && request.epoch <= current) return;
      _currentEpoch = request.epoch;
      _snapshotRequests.clear();
      unawaited(_performRender(request, version));
    } on Object catch (error) {
      _sendProtocolErrorTo(
        message.origin,
        'Malformed $type message: $error',
        attemptedVersion:
            payload['v'] is int ? payload['v']! as int : renderProtocolV1,
      );
    }
  }

  void _receiveSnapshotRequest(
    String origin,
    Map<String, Object?> payload,
    BundleSnapshotHandler snapshot,
  ) {
    final selectedVersion = _selectedVersion;
    final epoch = _currentEpoch;
    if (_lockedOrigin == null ||
        origin != _lockedOrigin ||
        selectedVersion == null ||
        epoch == null ||
        !_settledEpochs.contains(epoch) ||
        _terminatedEpochs.contains(epoch)) {
      return;
    }
    if (_requiredInt(payload, 'v') != selectedVersion ||
        _requiredInt(payload, 'epoch') != epoch) {
      throw const FormatException('snapshotRequest fields are invalid.');
    }
    final path = _requiredString(payload, 'path');
    validateSnapshotPath(path, argumentName: 'snapshotRequest.path');
    final requestIdentity = '$epoch\u0000$path';
    if (!_snapshotRequests.add(requestIdentity)) return;
    unawaited(
      _performSnapshot(
        snapshot,
        epoch: epoch,
        path: path,
        version: selectedVersion,
        requestIdentity: requestIdentity,
      ),
    );
  }

  Future<void> _performSnapshot(
    BundleSnapshotHandler snapshot, {
    required int epoch,
    required String path,
    required int version,
    required String requestIdentity,
  }) async {
    try {
      final png = validateRenderBundleSnapshotPng(
        await snapshot(epoch, path),
      );
      final encoded = base64Encode(png.bytes);
      if (epoch != _currentEpoch ||
          !_settledEpochs.contains(epoch) ||
          _terminatedEpochs.contains(epoch)) {
        return;
      }
      _send(<String, Object?>{
        'v': version,
        'type': 'snapshotResult',
        'epoch': epoch,
        'path': path,
        'png': encoded,
      });
    } on Object {
      // A snapshot is an optional, per-epoch capability, and capture can fail
      // for ordinary reasons — a frame larger than the fixed payload bound,
      // most commonly. Deliberately send nothing: `protocolError` means a
      // contract violation outside any epoch, the shell treats every one of
      // them as terminal, and escalating here would discard the session and
      // tear a healthy settled render down to placeholders because an
      // optional capture did not fit. The requester's own snapshot timeout
      // resolves the outstanding request instead, leaving the render intact
      // and the capability retryable. Dropping the in-flight identity above
      // is what makes that retry possible.
      _snapshotRequests.remove(requestIdentity);
    }
  }

  bool _selectOrAccept(String origin, int version) {
    if (_lockedOrigin == null) {
      _lockedOrigin = origin;
      _selectedVersion = version;
      return true;
    }
    if (_lockedOrigin != origin) return false;
    if (_selectedVersion != version) {
      _sendProtocolError('Render protocol version changed after selection.');
      return false;
    }
    return true;
  }

  ({int version, BundleInitialization initialization}) _parseInit(
    Map<String, Object?> payload,
  ) {
    final version = _requiredInt(payload, 'v');
    final protocol = _requiredInt(payload, 'protocol');
    if (protocol != version) {
      throw const FormatException('protocol must equal v.');
    }
    final frame = _requiredMap(payload, 'frame');
    final width = _requiredDouble(frame, 'w');
    final height = _requiredDouble(frame, 'h');
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      throw const FormatException(
        'frame dimensions must be finite and positive.',
      );
    }
    var fontUrls = const <String>[];
    final prewarm = payload['prewarm'];
    if (prewarm != null) {
      final map = _asMap(prewarm);
      final rawFontUrls = map?['fontUrls'];
      if (map == null ||
          rawFontUrls is! List<Object?> ||
          rawFontUrls.any((url) => url is! String)) {
        throw const FormatException('prewarm.fontUrls must be a list.');
      }
      fontUrls = List<String>.unmodifiable(rawFontUrls.cast<String>());
    }
    return (
      version: version,
      initialization: BundleInitialization(
        frame: Size(width, height),
        fontUrls: fontUrls,
      ),
    );
  }

  ({int version, RenderRequest request}) _parseRender(
    Map<String, Object?> payload,
  ) {
    final version = _requiredInt(payload, 'v');
    return (
      version: version,
      request: RenderRequest(
        epoch: _requiredInt(payload, 'epoch'),
        blob: decodeRenderBlob(_requiredString(payload, 'blob')),
        data: _requiredMap(payload, 'data'),
        env: RenderEnv.fromJson(_requiredMap(payload, 'env')),
      ),
    );
  }

  Future<void> _performRender(RenderRequest request, int version) async {
    try {
      final result = await _render(request);
      if (request.epoch != _currentEpoch ||
          _terminatedEpochs.contains(request.epoch)) {
        return;
      }
      _settledEpochs.add(request.epoch);
      _geometryGenerations[request.epoch] = 0;
      _send(
        <String, Object?>{
          'v': version,
          'type': 'settled',
          'epoch': request.epoch,
          if (result.timings != null) 'timings': result.timings,
          'diagnostics': result.diagnostics
              .map((diagnostic) => diagnostic.toJson())
              .toList(),
        },
      );
      _sendGeometry(request.epoch, 0, result.geometry, version);
    } on BundleRenderFailure catch (error) {
      _fail(request.epoch, version, error.message, error.path);
    } on Object {
      _fail(request.epoch, version, 'Render failed.', null);
    }
  }

  void _fail(int epoch, int version, String message, String? path) {
    if (epoch != _currentEpoch || _terminatedEpochs.contains(epoch)) return;
    _terminatedEpochs.add(epoch);
    _pendingGeometry.remove(epoch);
    _send(
      <String, Object?>{
        'v': version,
        'type': 'renderError',
        'epoch': epoch,
        'message': message,
        if (path != null) 'path': path,
      },
    );
  }

  /// Reports a controlled failure discovered after render setup completed.
  ///
  /// The current epoch is terminated exactly once. Failures for stale or
  /// already terminated epochs are ignored.
  void reportRenderFailure(int epoch, BundleRenderFailure failure) {
    if (_disposed) return;
    final version = _selectedVersion;
    if (version == null) return;
    _fail(epoch, version, failure.message, failure.path);
  }

  /// Publishes the latest geometry, coalesced to one emission per frame.
  void publishGeometry(int epoch, Map<String, Rect> rects) {
    if (_disposed) return;
    if (epoch != _currentEpoch ||
        !_settledEpochs.contains(epoch) ||
        _terminatedEpochs.contains(epoch)) {
      return;
    }
    final snapshot = snapshotGeometry(rects, argumentName: 'rects');
    _pendingGeometry[epoch] = snapshot;
    if (!_scheduledGeometry.add(epoch)) return;
    _scheduleFrame(() {
      _scheduledGeometry.remove(epoch);
      final pending = _pendingGeometry.remove(epoch);
      if (pending == null ||
          epoch != _currentEpoch ||
          _terminatedEpochs.contains(epoch)) {
        return;
      }
      final generation = (_geometryGenerations[epoch] ?? 0) + 1;
      _geometryGenerations[epoch] = generation;
      final version = _selectedVersion;
      if (version == null) return;
      _sendGeometry(
        epoch,
        generation,
        pending,
        version,
      );
    });
  }

  void _sendGeometry(
      int epoch, int generation, Map<String, Rect> rects, int version) {
    validateGeometry(rects, argumentName: 'rects');
    _send(
      <String, Object?>{
        'v': version,
        'type': 'geometry',
        'epoch': epoch,
        'generation': generation,
        'rects': <String, Object?>{
          for (final entry in rects.entries)
            entry.key: <double>[
              entry.value.left,
              entry.value.top,
              entry.value.width,
              entry.value.height,
            ],
        },
      },
    );
  }

  void _sendProtocolError(String message) {
    _send(<String, Object?>{
      'v': _selectedVersion ?? renderProtocolV1,
      'type': 'protocolError',
      'message': message,
    });
  }

  void _sendProtocolErrorTo(
    String origin,
    String message, {
    int? attemptedVersion,
  }) {
    if (_disposed) return;
    _transport.send(
      <String, Object?>{
        'v': _selectedVersion ?? attemptedVersion ?? renderProtocolV1,
        'type': 'protocolError',
        'message': message,
      },
      targetOrigin: origin,
    );
  }

  void _send(Map<String, Object?> payload) {
    if (_disposed) return;
    final origin = _lockedOrigin;
    if (origin != null) _transport.send(payload, targetOrigin: origin);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _subscription?.cancel();
    await _transport.dispose();
  }
}

Set<int> _snapshotSupportedVersions(Iterable<int> versions) {
  final snapshot = versions.toSet();
  if (snapshot.isEmpty || snapshot.any((version) => version < 1)) {
    throw ArgumentError.value(
      versions,
      'supportedVersions',
      'must contain at least one positive protocol version',
    );
  }
  return Set<int>.unmodifiable(snapshot);
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is! Map<Object?, Object?>) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    result[entry.key! as String] = entry.value;
  }
  return result;
}

Map<String, Object?> _requiredMap(Map<String, Object?> map, String key) {
  final value = _asMap(map[key]);
  if (value == null) throw FormatException('$key must be an object.');
  return value;
}

String _requiredString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String) throw FormatException('$key must be a string.');
  return value;
}

int _requiredInt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! int) throw FormatException('$key must be an integer.');
  return value;
}

double _requiredDouble(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! num) throw FormatException('$key must be a number.');
  return value.toDouble();
}
