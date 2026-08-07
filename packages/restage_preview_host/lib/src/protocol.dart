import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:restage_shared/restage_shared.dart';

import 'geometry_validation.dart';
import 'manifest.dart';
import 'snapshot_path_validation.dart';
import 'wire_json.dart';

const int renderProtocolV1 = 1;

/// Ready-handshake capability token for the additive PNG snapshot pair.
const String renderSnapshotCapability = 'snapshot';

/// Transport-independent rendering surface consumed by tooling.
abstract interface class SurfaceRenderProvider {
  Stream<GeometrySnapshot> get geometry;
  Stream<RenderEvent> get events;
  Future<void> render(RenderRequest request);
  Future<void> dispose();
}

/// Optional capability for capturing the latest settled render as a PNG.
///
/// This stays separate from [SurfaceRenderProvider] so existing render-only
/// providers do not need to implement snapshot behavior.
abstract interface class SurfaceSnapshotProvider {
  Future<Uint8List> snapshot({required String path});
}

/// Negotiated optional snapshot support for a render provider.
///
/// A provider implementing this interface may still return null when its peer
/// did not advertise [renderSnapshotCapability].
abstract interface class SurfaceSnapshotCapability {
  SurfaceSnapshotProvider? get snapshotProvider;
}

/// Resolves snapshot support without widening [SurfaceRenderProvider].
SurfaceSnapshotProvider? surfaceSnapshotProviderFor(
  SurfaceRenderProvider provider,
) {
  if (provider is SurfaceSnapshotCapability) {
    return (provider as SurfaceSnapshotCapability).snapshotProvider;
  }
  return provider is SurfaceSnapshotProvider
      ? provider as SurfaceSnapshotProvider
      : null;
}

/// Maximum encoded PNG size accepted from a render bundle.
const int renderSnapshotMaxBytes = renderBundleSnapshotMaxBytes;

/// One self-contained render request.
final class RenderRequest {
  RenderRequest({
    required this.epoch,
    required Uint8List blob,
    required Map<String, Object?> data,
    required this.env,
  })  : blob = Uint8List.fromList(blob).asUnmodifiableView(),
        data = snapshotWireMap(data, argumentName: 'data') {
    if (epoch < 0) {
      throw ArgumentError.value(epoch, 'epoch', 'must be non-negative');
    }
  }

  final int epoch;
  final Uint8List blob;
  final Map<String, Object?> data;
  final RenderEnv env;
}

/// Environment applied independently to every render request.
final class RenderEnv {
  RenderEnv({
    required Map<String, Object?> theme,
    required this.brightness,
    required this.locale,
    required this.textScale,
    required this.zoom,
    required this.frame,
  }) : theme = snapshotWireMap(theme, argumentName: 'theme') {
    if (brightness != 'light' && brightness != 'dark') {
      throw ArgumentError.value(
          brightness, 'brightness', 'must be light or dark');
    }
    if (!textScale.isFinite || textScale <= 0) {
      throw ArgumentError.value(
          textScale, 'textScale', 'must be positive and finite');
    }
    if (!zoom.isFinite || zoom <= 0) {
      throw ArgumentError.value(zoom, 'zoom', 'must be positive and finite');
    }
    validatePositiveFrame(frame, argumentName: 'frame');
  }

  factory RenderEnv.fromJson(Map<String, Object?> json) {
    final frame = _requiredMap(json, 'frame');
    return RenderEnv(
      theme: _requiredMap(json, 'theme'),
      brightness: _requiredString(json, 'brightness'),
      locale: _requiredString(json, 'locale'),
      textScale: _requiredDouble(json, 'textScale'),
      zoom: _requiredDouble(json, 'zoom'),
      frame: Size(_requiredDouble(frame, 'w'), _requiredDouble(frame, 'h')),
    );
  }

  final Map<String, Object?> theme;
  final String brightness;
  final String locale;
  final double textScale;
  final double zoom;
  final Size frame;

  Map<String, Object?> toJson() => <String, Object?>{
        'theme': theme,
        'brightness': brightness,
        'locale': locale,
        'textScale': textScale,
        'zoom': zoom,
        'frame': <String, Object?>{'w': frame.width, 'h': frame.height},
      };
}

/// One epoch-tagged geometry generation.
final class GeometrySnapshot {
  GeometrySnapshot({
    required this.epoch,
    required this.generation,
    required Map<String, Rect> rects,
  }) : rects = snapshotGeometry(rects, argumentName: 'rects') {
    if (epoch < 0) {
      throw ArgumentError.value(epoch, 'epoch', 'must be non-negative');
    }
    if (generation < 0) {
      throw ArgumentError.value(
        generation,
        'generation',
        'must be non-negative',
      );
    }
  }

  final int epoch;
  final int generation;
  final Map<String, Rect> rects;
}

abstract interface class RenderEvent {}

final class Settled implements RenderEvent {
  Settled({
    required this.epoch,
    required Iterable<RenderDiagnostic> diagnostics,
    Map<String, Object?>? timings,
  })  : diagnostics = List<RenderDiagnostic>.unmodifiable(diagnostics),
        timings = timings == null
            ? null
            : snapshotWireMap(timings, argumentName: 'timings');

  final int epoch;
  final List<RenderDiagnostic> diagnostics;
  final Map<String, Object?>? timings;
}

final class RenderError implements RenderEvent {
  const RenderError({required this.epoch, required this.message, this.path});

  final int epoch;
  final String message;
  final String? path;
}

final class ProtocolError implements RenderEvent {
  const ProtocolError(this.message);

  final String message;
}

final class RenderDiagnostic {
  RenderDiagnostic({required this.severity, required this.message, this.path}) {
    if (severity != 'info' && severity != 'warning') {
      throw ArgumentError.value(
        severity,
        'severity',
        'must be info or warning',
      );
    }
  }

  final String severity;
  final String message;
  final String? path;

  Map<String, Object?> toJson() => <String, Object?>{
        'severity': severity,
        'message': message,
        if (path != null) 'path': path,
      };
}

/// One inbound transport event with the sender's exact origin.
final class RenderTransportMessage {
  const RenderTransportMessage({required this.origin, required this.payload});

  final String origin;
  final Object? payload;
}

/// Minimal message transport implemented by browser and embedded adapters.
abstract interface class RenderMessageTransport {
  Stream<RenderTransportMessage> get messages;
  void send(Map<String, Object?> payload, {required String targetOrigin});
  Future<void> dispose();
}

typedef RenderFrameScheduler = void Function(void Function() callback);

/// Shell-side provider for an isolated render bundle.
final class SeamRenderProvider
    implements SurfaceRenderProvider, SurfaceSnapshotCapability {
  SeamRenderProvider({
    required RenderMessageTransport transport,
    required this.bundleOrigin,
    required Iterable<int> supportedVersions,
    required RenderFrameScheduler scheduleFrame,
    this.snapshotTimeout = const Duration(seconds: 5),
  })  : _transport = transport,
        _supportedVersions = _snapshotSupportedVersions(supportedVersions),
        _scheduleFrame = scheduleFrame {
    if (snapshotTimeout <= Duration.zero) {
      throw ArgumentError.value(
        snapshotTimeout,
        'snapshotTimeout',
        'must be positive',
      );
    }
    _subscription = _transport.messages.listen(_receive);
    _readyCompleter.future.ignore();
  }

  final RenderMessageTransport _transport;
  final String bundleOrigin;
  final Set<int> _supportedVersions;
  final RenderFrameScheduler _scheduleFrame;

  /// Maximum time one optional snapshot request may remain outstanding.
  final Duration snapshotTimeout;
  final StreamController<GeometrySnapshot> _geometry =
      StreamController<GeometrySnapshot>.broadcast(sync: true);
  final StreamController<RenderEvent> _events =
      StreamController<RenderEvent>.broadcast(sync: true);
  late final StreamSubscription<RenderTransportMessage> _subscription;
  final Completer<int> _readyCompleter = Completer<int>();

  int? _negotiatedVersion;
  RenderBundleManifest? _manifest;
  RenderEngine? _engine;
  int? _latestEpoch;
  bool _settled = false;
  bool _terminated = false;
  int _lastGeometry = -1;
  GeometrySnapshot? _pendingGeometry;
  bool _geometryFrameScheduled = false;
  bool _negotiationFailed = false;
  bool _disposed = false;
  bool _snapshotSupported = false;
  late final SurfaceSnapshotProvider _snapshotProvider =
      _SeamSnapshotProvider(this);
  Completer<Uint8List>? _snapshotCompleter;
  int? _snapshotEpoch;
  String? _snapshotPath;
  Timer? _snapshotTimer;

  /// Highest protocol version selected from the first accepted ready message.
  int? get negotiatedVersion => _negotiatedVersion;

  /// Completes with the selected protocol version after successful negotiation.
  Future<int> get ready => _readyCompleter.future;

  /// Capability manifest advertised by the accepted render bundle.
  RenderBundleManifest? get manifest => _manifest;

  /// Rendering engine advertised by the accepted render bundle.
  RenderEngine? get engine => _engine;

  @override
  SurfaceSnapshotProvider? get snapshotProvider =>
      _snapshotSupported ? _snapshotProvider : null;

  @override
  Stream<GeometrySnapshot> get geometry => _geometry.stream;

  @override
  Stream<RenderEvent> get events => _events.stream;

  /// Sends the optional idempotent pre-warm message after negotiation.
  Future<void> initialize({
    required Size frame,
    Iterable<Uri> fontUrls = const <Uri>[],
  }) async {
    final version = _requireReady('initialize');
    validatePositiveFrame(frame, argumentName: 'frame');
    final urls = fontUrls.map((url) => url.toString()).toList(growable: false);
    _transport.send(
      <String, Object?>{
        'v': version,
        'type': 'init',
        'protocol': version,
        'frame': <String, Object?>{'w': frame.width, 'h': frame.height},
        if (urls.isNotEmpty) 'prewarm': <String, Object?>{'fontUrls': urls},
      },
      targetOrigin: bundleOrigin,
    );
  }

  @override
  Future<void> render(RenderRequest request) async {
    final version = _requireReady('render');
    if (_latestEpoch != null && request.epoch <= _latestEpoch!) {
      throw ArgumentError.value(
          request.epoch, 'epoch', 'must be strictly monotonic');
    }
    _latestEpoch = request.epoch;
    _rejectOutstandingSnapshot('A newer render replaced the snapshot target.');
    _settled = false;
    _terminated = false;
    _lastGeometry = -1;
    _pendingGeometry = null;
    _transport.send(
      <String, Object?>{
        'v': version,
        'type': 'render',
        'epoch': request.epoch,
        'blob': encodeRenderBlob(request.blob),
        'data': request.data,
        'env': request.env.toJson(),
      },
      targetOrigin: bundleOrigin,
    );
  }

  Future<Uint8List> _snapshot({required String path}) {
    final version = _requireReady('capture a snapshot');
    final epoch = _latestEpoch;
    if (epoch == null || !_settled || _terminated) {
      throw StateError('A snapshot requires the latest settled render.');
    }
    if (_snapshotCompleter != null) {
      throw StateError('A snapshot request is already outstanding.');
    }
    validateSnapshotPath(path, argumentName: 'path');
    final completer = Completer<Uint8List>();
    _snapshotCompleter = completer;
    _snapshotEpoch = epoch;
    _snapshotPath = path;
    _snapshotTimer = Timer(
      snapshotTimeout,
      () => _rejectOutstandingSnapshot(
        'Snapshot request timed out before completion.',
      ),
    );
    try {
      _transport.send(
        <String, Object?>{
          'v': version,
          'type': 'snapshotRequest',
          'epoch': epoch,
          'path': path,
        },
        targetOrigin: bundleOrigin,
      );
    } on Object catch (error, stackTrace) {
      _clearOutstandingSnapshot();
      completer.completeError(error, stackTrace);
    }
    return completer.future;
  }

  void _receive(RenderTransportMessage message) {
    if (_disposed) return;
    if (message.origin != bundleOrigin) return;
    final payload = _asMap(message.payload);
    if (payload == null) return;
    final type = payload['type'];
    if (type is! String) return;
    if (type == 'ready') {
      _receiveReady(payload);
      return;
    }
    if (!const <String>{
      'settled',
      'geometry',
      'renderError',
      'protocolError',
      'snapshotResult',
    }.contains(type)) {
      return;
    }
    try {
      final version = _requiredInt(payload, 'v');
      if (version != _negotiatedVersion) {
        _events.add(const ProtocolError(
            'Message used an unnegotiated protocol version.'));
        return;
      }
      if (type == 'protocolError') {
        _rejectOutstandingSnapshot(
          'The bundle rejected the outstanding snapshot request.',
        );
        _events.add(ProtocolError(_requiredString(payload, 'message')));
        return;
      }
      final epoch = _requiredInt(payload, 'epoch');
      if (epoch != _latestEpoch || _terminated) return;
      if (type == 'snapshotResult') {
        _receiveSnapshotResult(payload, epoch);
        return;
      }
      switch (type) {
        case 'settled':
          if (_settled) {
            throw const FormatException('Duplicate settled message.');
          }
          final event = Settled(
            epoch: epoch,
            diagnostics: _parseDiagnostics(payload['diagnostics']),
            timings: payload['timings'] == null
                ? null
                : _requiredMap(payload, 'timings'),
          );
          _settled = true;
          _events.add(event);
        case 'geometry':
          if (!_settled) {
            throw const FormatException('Geometry preceded settled.');
          }
          final snapshot = _parseGeometry(payload);
          if (_lastGeometry == -1 && snapshot.generation != 0) {
            throw const FormatException(
                'The first geometry generation must be zero.');
          }
          if (snapshot.generation <= _lastGeometry ||
              (_pendingGeometry != null &&
                  snapshot.generation <= _pendingGeometry!.generation)) {
            throw const FormatException(
                'Geometry generations must strictly increase.');
          }
          if (snapshot.generation == 0) {
            _lastGeometry = 0;
            _geometry.add(snapshot);
          } else {
            _pendingGeometry = snapshot;
            if (!_geometryFrameScheduled) {
              _geometryFrameScheduled = true;
              _scheduleFrame(_flushGeometry);
            }
          }
        case 'renderError':
          _terminated = true;
          _pendingGeometry = null;
          _rejectOutstandingSnapshot(
            'The render failed before snapshot completion.',
          );
          _events.add(
            RenderError(
              epoch: epoch,
              message: _requiredString(payload, 'message'),
              path: payload['path'] as String?,
            ),
          );
      }
    } on Object catch (error) {
      _events.add(ProtocolError('Malformed $type message: $error'));
    }
  }

  void _receiveSnapshotResult(Map<String, Object?> payload, int epoch) {
    final completer = _snapshotCompleter;
    if (completer == null ||
        epoch != _snapshotEpoch ||
        payload['path'] != _snapshotPath) {
      return;
    }
    try {
      final bytes = decodeRenderSnapshotPng(_requiredString(payload, 'png'));
      _clearOutstandingSnapshot();
      completer.complete(bytes);
    } on Object catch (error, stackTrace) {
      _clearOutstandingSnapshot();
      completer.completeError(error, stackTrace);
      rethrow;
    }
  }

  void _receiveReady(Map<String, Object?> payload) {
    if (_negotiatedVersion != null || _negotiationFailed) return;
    try {
      final advertisedVersions = _requiredIntList(payload, 'protocolVersions');
      if (advertisedVersions.isEmpty ||
          advertisedVersions.any((version) => version < 1)) {
        throw const FormatException(
          'protocolVersions must contain positive integers.',
        );
      }
      final advertised = advertisedVersions.toSet();
      final overlap = advertised.intersection(_supportedVersions).toList()
        ..sort();
      final manifest =
          RenderBundleManifest.fromJson(_requiredMap(payload, 'manifest'));
      final engine = RenderEngine.fromJson(_requiredMap(payload, 'engine'));
      final capabilities = _optionalStringSet(payload, 'capabilities');
      if (overlap.isEmpty) {
        _negotiationFailed = true;
        const message = 'No common render protocol version.';
        _events.add(const ProtocolError(message));
        _completeReadyError(StateError(message));
        return;
      }
      _manifest = manifest;
      _engine = engine;
      _snapshotSupported = capabilities.contains(renderSnapshotCapability);
      _negotiatedVersion = overlap.last;
      _readyCompleter.complete(overlap.last);
    } on Object catch (error) {
      _events.add(ProtocolError('Malformed ready message: $error'));
    }
  }

  void _flushGeometry() {
    _geometryFrameScheduled = false;
    if (_disposed) return;
    final snapshot = _pendingGeometry;
    _pendingGeometry = null;
    if (snapshot == null || snapshot.epoch != _latestEpoch || _terminated) {
      return;
    }
    _lastGeometry = snapshot.generation;
    _geometry.add(snapshot);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _rejectOutstandingSnapshot(
      'Render provider was disposed before snapshot completion.',
    );
    if (!_readyCompleter.isCompleted) {
      _completeReadyError(
        StateError('Render provider was disposed before it became ready.'),
      );
    }
    await _subscription.cancel();
    await _geometry.close();
    await _events.close();
    await _transport.dispose();
  }

  void _rejectOutstandingSnapshot(String message) {
    final completer = _snapshotCompleter;
    _clearOutstandingSnapshot();
    if (completer != null && !completer.isCompleted) {
      completer.completeError(StateError(message), StackTrace.current);
    }
  }

  void _clearOutstandingSnapshot() {
    _snapshotTimer?.cancel();
    _snapshotTimer = null;
    _snapshotCompleter = null;
    _snapshotEpoch = null;
    _snapshotPath = null;
  }

  int _requireReady(String operation) {
    if (_disposed) {
      throw StateError('A disposed render provider cannot $operation.');
    }
    if (_negotiationFailed) {
      throw StateError(
        'Render provider cannot $operation after negotiation failed.',
      );
    }
    final version = _negotiatedVersion;
    if (version == null) {
      throw StateError(
        'Render provider is not ready; await ready before $operation.',
      );
    }
    return version;
  }

  void _completeReadyError(StateError error) {
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.completeError(error, StackTrace.current);
    }
  }
}

final class _SeamSnapshotProvider implements SurfaceSnapshotProvider {
  const _SeamSnapshotProvider(this._owner);

  final SeamRenderProvider _owner;

  @override
  Future<Uint8List> snapshot({required String path}) =>
      _owner._snapshot(path: path);
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

String encodeRenderBlob(Uint8List bytes) => base64Encode(bytes);

Uint8List decodeRenderBlob(String encoded) => base64Decode(encoded);

/// Decodes and validates one bounded PNG snapshot.
Uint8List decodeRenderSnapshotPng(String encoded) {
  final maxEncodedLength = ((renderSnapshotMaxBytes + 2) ~/ 3) * 4;
  if (encoded.isEmpty || encoded.length > maxEncodedLength) {
    throw const FormatException('Snapshot PNG is too large.');
  }
  final bytes = base64Decode(encoded);
  return validateRenderBundleSnapshotPng(bytes).bytes;
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

List<int> _requiredIntList(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! List<Object?>) throw FormatException('$key must be a list.');
  return value.map((item) {
    if (item is! int) throw FormatException('$key must contain integers.');
    return item;
  }).toList();
}

Set<String> _optionalStringSet(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) return const <String>{};
  if (value is! List<Object?>) {
    throw FormatException('$key must be a list.');
  }
  final result = <String>{};
  for (final item in value) {
    if (item is! String || item.isEmpty) {
      throw FormatException('$key must contain non-empty strings.');
    }
    result.add(item);
  }
  return Set<String>.unmodifiable(result);
}

List<RenderDiagnostic> _parseDiagnostics(Object? value) {
  if (value is! List<Object?>) {
    throw const FormatException('diagnostics must be a list.');
  }
  return value.map((item) {
    final map = _asMap(item);
    if (map == null) {
      throw const FormatException('diagnostic must be an object.');
    }
    final severity = _requiredString(map, 'severity');
    if (severity != 'info' && severity != 'warning') {
      throw const FormatException(
          'diagnostic severity must be info or warning.');
    }
    return RenderDiagnostic(
      severity: severity,
      message: _requiredString(map, 'message'),
      path: map['path'] as String?,
    );
  }).toList();
}

GeometrySnapshot _parseGeometry(Map<String, Object?> payload) {
  final rects = <String, Rect>{};
  for (final entry in _requiredMap(payload, 'rects').entries) {
    final values = entry.value;
    if (values is! List<Object?> ||
        values.length != 4 ||
        values.any((value) => value is! num)) {
      throw const FormatException('rect must contain four numbers.');
    }
    rects[entry.key] = Rect.fromLTWH(
      (values[0]! as num).toDouble(),
      (values[1]! as num).toDouble(),
      (values[2]! as num).toDouble(),
      (values[3]! as num).toDouble(),
    );
  }
  return GeometrySnapshot(
    epoch: _requiredInt(payload, 'epoch'),
    generation: _requiredInt(payload, 'generation'),
    rects: rects,
  );
}
