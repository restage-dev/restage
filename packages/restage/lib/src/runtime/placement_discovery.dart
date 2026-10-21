import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show PlacementKeyV1;
import 'package:restage_shared/restage_shared.dart';

import 'render_geometry.dart';

/// Local placement declarations and frame observations owned by the SDK.
final class PlacementDiscovery {
  /// Creates a local owner; reporting is installed separately by configuration.
  PlacementDiscovery();

  /// App-wide local owner used by runtime hosts and authoring capture.
  static final PlacementDiscovery instance = PlacementDiscovery();

  final List<PlacementDiscoveryRegistration> _registrations = [];
  List<PlacementMountRequestV1> _mounts = [];
  Map<String, SurfaceHostContractV1> _contracts = {};
  InstalledCapability Function()? _installedCapability;
  Future<bool> Function(PlacementDiscoveryReportV1)? _report;
  String? _platform;
  int? _buildOrdinal;
  String? _appVersion;
  int _epoch = 0;
  int _generation = 0;
  bool _observationScheduled = false;
  bool _firstPaintPending = false;
  Timer? _reportTimer;
  PlacementDiscoveryReportV1? _pendingReport;
  List<int>? _lastReportBytes;
  List<_Observation> _previousGeometry = [];

  /// Installs offline build inputs and an optional authenticated report sink.
  void configure({
    required InstalledCapability Function() installedCapability,
    required String platform,
    int? buildOrdinal,
    List<PlacementMountRequestV1> mounts = const [],
    Map<String, SurfaceHostContractV1> contractsByHash = const {},
    Future<bool> Function(PlacementDiscoveryReportV1)? report,
  }) {
    final capability = installedCapability();
    final build = PlacementBuildContractV1(
      platform: platform,
      buildOrdinal: buildOrdinal,
      mounts: mounts,
      contractsByHash: contractsByHash,
      installedCapability: capability,
      installedCapabilityHash: capability.contentHash,
    );
    reset();
    _installedCapability = installedCapability;
    _platform = platform;
    _buildOrdinal = buildOrdinal;
    _mounts = build.mounts.toList();
    _contracts = Map.of(build.contractsByHash);
    _report = report;
  }

  /// Replaces observed app facts without removing live registrations. An
  /// omitted [appVersion] keeps the one already known.
  void updateBuildInputs(
      {required String platform, int? buildOrdinal, String? appVersion}) {
    final version = appVersion ?? _appVersion;
    if (_platform == platform &&
        _buildOrdinal == buildOrdinal &&
        _appVersion == version) {
      return;
    }
    _makeBuild(platform: platform, buildOrdinal: buildOrdinal);
    _platform = platform;
    _buildOrdinal = buildOrdinal;
    _appVersion = version;
    _epoch++;
    _scheduleObservation();
  }

  /// Merges known declarations without retiring live occurrences.
  void rememberDeclarations({
    required List<PlacementMountRequestV1> mounts,
    required Map<String, SurfaceHostContractV1> contractsByHash,
  }) {
    final previous = buildContract;
    final next = _makeBuild(
      mounts: [..._mounts, ...mounts],
      contracts: {..._contracts, ...contractsByHash},
    );
    if (next.appBuildContractHash == previous.appBuildContractHash) return;
    _mounts = next.mounts.toList();
    _contracts = Map.of(next.contractsByHash);
    _epoch++;
    _scheduleObservation();
  }

  /// Registers the exact effective declaration supplied by a runtime host.
  PlacementDiscoveryRegistration register({
    required BuildContext context,
    required PlacementMountRequestV1 mount,
    required SurfaceHostContractV1 hostContract,
    required bool Function() isCurrent,
  }) {
    if (_installedCapability == null) {
      throw StateError('Placement discovery is not configured.');
    }
    if (mount.hostContractHash != hostContract.contentHash) {
      throw const FormatException('The placement host hash does not match.');
    }
    final nextMounts = [..._mounts, mount];
    final nextContracts = {
      ..._contracts,
      hostContract.contentHash: hostContract
    };
    final nextBuild = _makeBuild(mounts: nextMounts, contracts: nextContracts);
    _mounts = nextBuild.mounts.toList();
    _contracts = Map.of(nextBuild.contractsByHash);
    final registration = PlacementDiscoveryRegistration._(
      this,
      context: context,
      mount: mount,
      isCurrent: isCurrent,
    );
    _registrations.add(registration);
    _epoch++;
    registration._bind();
    return registration;
  }

  /// The complete target-free declaration, available before any remote resolve.
  PlacementBuildContractV1 get buildContract => _makeBuild();

  PlacementBuildContractV1 _makeBuild({
    String? platform,
    int? buildOrdinal,
    List<PlacementMountRequestV1>? mounts,
    Map<String, SurfaceHostContractV1>? contracts,
  }) {
    final capability = _installedCapability?.call();
    if (capability == null || _platform == null) {
      throw StateError('Placement discovery is not configured.');
    }
    return PlacementBuildContractV1(
      platform: platform ?? _platform!,
      buildOrdinal: platform == null ? _buildOrdinal : buildOrdinal,
      mounts: mounts ?? _mounts,
      contractsByHash: contracts ?? _contracts,
      installedCapability: capability,
      installedCapabilityHash: capability.contentHash,
    );
  }

  /// Captures fresh geometry in one explicitly selected Flutter frame.
  ///
  /// This local read does not enqueue a report or request remote content.
  PlacementDiscoveryFrame captureFrame({
    required RenderView view,
    RenderRepaintBoundary? boundary,
  }) {
    final frame = boundary ?? view;
    final geometry = _collect(view, frame, strict: true);
    final viewport = _viewport(frame);
    final build = buildContract;
    return PlacementDiscoveryFrame._(
      this,
      epoch: _epoch,
      view: view,
      boundary: boundary,
      viewport: viewport,
      logicalSize: _frameSize(frame),
      buildContract: build,
      geometry: geometry,
    );
  }

  List<_Observation> _collect(
    RenderView view,
    RenderObject frame, {
    bool strict = false,
    bool paintedOnly = false,
  }) {
    final viewport = _viewport(frame);
    final logicalSize = _frameSize(frame);
    final order = geometryDrawnOrder(frame);
    final observations = <_Observation>[];
    for (final registration in _registrations) {
      final box = registration._renderBox;
      if (box == null || !identical(placementOwningView(box), view)) continue;
      if (!order.containsKey(box)) continue;
      if (!registration._current) {
        if (strict) {
          throw const FormatException('Placement selection is stale.');
        }
        continue;
      }
      if (paintedOnly && !registration._painted) continue;
      try {
        if (!box.hasSize) {
          throw const FormatException('Placement is not laid out.');
        }
        final rect = geometryBoundsInFrame(box, frame);
        final bounds = PlacementLogicalRectV1.fromLogical(
          x: rect.left,
          y: rect.top,
          width: rect.width,
          height: rect.height,
        );
        observations.add(_Observation(
            registration, box, view, bounds, viewport, rect, logicalSize));
      } on Object {
        if (strict) {
          throw const FormatException(
              'Placement bounds are not finite and positive.');
        }
      }
    }
    observations.sort((a, b) => order[a.box]!.compareTo(order[b.box]!));
    return observations;
  }

  void _scheduleObservation() {
    if (_observationScheduled || _installedCapability == null) return;
    _observationScheduled = true;
    final generation = _generation;
    void observe() {
      if (_generation != generation) return;
      _observationScheduled = false;
      if (_installedCapability == null) return;
      _observe();
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.transientCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks ||
        phase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance
          .addPostFrameCallback((_) => scheduleMicrotask(observe));
    } else {
      scheduleMicrotask(observe);
    }
  }

  void _observe() {
    final views = <RenderView>{
      for (final registration in _registrations)
        if (placementOwningView(registration._renderBox)
            case final RenderView view)
          view,
    };
    final geometry = <_Observation>[];
    final painted = <_Observation>[];
    for (final view in views) {
      try {
        geometry.addAll(_collect(view, view));
        painted.addAll(_collect(view, view, paintedOnly: true));
      } on Object {
        // A detached view contributes no runtime bounds.
      }
    }
    if (!listEquals(geometry, _previousGeometry)) {
      _previousGeometry = geometry;
      _epoch++;
    }
    // Every mounted declaration reports; only painted ones carry bounds.
    final mounts = {
      for (final registration in _registrations)
        if (registration._current) registration.mount,
    };
    if (_report == null ||
        (mounts.isEmpty &&
            _lastReportBytes == null &&
            _pendingReport == null)) {
      return;
    }
    final PlacementDiscoveryReportV1 report;
    try {
      final build = buildContract;
      final occurrences = <(PlacementKeyV1, String), int>{};
      report = PlacementDiscoveryReportV1(
        mounts: mounts.toList(),
        buildContract: build,
        appBuildContractHash: build.appBuildContractHash,
        appVersion: _appVersion,
        bounds: [
          for (final observation in painted)
            PlacementMountBoundsV1(
              key: observation.registration.mount.key,
              hostContractHash: observation.registration.mount.hostContractHash,
              logicalBounds: observation.rect,
              logicalViewport: observation.viewport,
              occurrenceIndex:
                  _nextOccurrence(occurrences, observation.registration.mount),
            ),
        ],
      );
    } on Object {
      return;
    }
    if (listEquals(report.canonicalBytes,
        _pendingReport?.canonicalBytes ?? _lastReportBytes)) {
      return;
    }
    _pendingReport = report;
    _reportTimer?.cancel();
    if (_firstPaintPending) {
      _firstPaintPending = false;
      _sendReport();
    } else {
      _reportTimer = Timer(const Duration(milliseconds: 250), _sendReport);
    }
  }

  void _sendReport() {
    final report = _pendingReport;
    final sink = _report;
    if (report == null || sink == null) return;
    _pendingReport = null;
    _lastReportBytes = report.canonicalBytes;
    unawaited(
        Future<bool>.sync(() => sink(report)).catchError((Object _) => false));
  }

  /// Invalidates captures, retires registrations and clears configured inputs.
  void reset() {
    _epoch++;
    _generation++;
    _observationScheduled = false;
    _installedCapability = null;
    for (final registration in _registrations.toList()) {
      registration.dispose();
    }
    _reportTimer?.cancel();
    _reportTimer = null;
    _report = null;
    _mounts = [];
    _contracts = {};
    _platform = null;
    _buildOrdinal = null;
    _appVersion = null;
    _pendingReport = null;
    _lastReportBytes = null;
    _previousGeometry = [];
    _firstPaintPending = false;
  }
}

/// A renderless local registration retired by its runtime host.
final class PlacementDiscoveryRegistration {
  PlacementDiscoveryRegistration._(
    this._owner, {
    required this.context,
    required this.mount,
    required bool Function() isCurrent,
  }) : _isCurrent = isCurrent;

  final PlacementDiscovery _owner;
  final BuildContext context;
  final PlacementMountRequestV1 mount;
  final bool Function() _isCurrent;
  GeometryRenderBoxBinding? _binding;
  bool _disposed = false;
  bool _painted = false;

  bool get _current => !_disposed && context.mounted && _isCurrent();

  RenderBox? get _renderBox {
    if (_disposed || !context.mounted) return null;
    final candidate = context.findRenderObject();
    return candidate is RenderBox && candidate.attached ? candidate : null;
  }

  void _bind() {
    _binding = GeometryRenderBoxBinding(
      renderObject: () => _renderBox,
      onChanged: (_, __) => _owner._scheduleObservation(),
      onFrame: (_) => _owner._scheduleObservation(),
    );
  }

  /// Marks the host's committed first paint; repeated marks are inert.
  void markPainted() {
    if (!_current || _painted) return;
    _painted = true;
    _owner._firstPaintPending = true;
    _owner._epoch++;
    _owner._scheduleObservation();
  }

  /// Removes this occurrence and invalidates captures that included it.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _binding?.dispose();
    _owner._registrations.remove(this);
    _owner._epoch++;
    _owner._scheduleObservation();
  }
}

/// An immutable local frame lease used while the Flutter image is encoded.
final class PlacementDiscoveryFrame {
  PlacementDiscoveryFrame._(
    this._owner, {
    required this.epoch,
    required this.view,
    required this.boundary,
    required this.viewport,
    required Size logicalSize,
    required this.buildContract,
    required List<_Observation> geometry,
  })  : _logicalSize = logicalSize,
        _geometry = List.unmodifiable(geometry) {
    final occurrences = <(PlacementKeyV1, String), int>{};
    mounts = List.unmodifiable([
      for (final observation in _geometry)
        PlacementSampleMountV1(
          key: observation.registration.mount.key,
          hostContractHash: observation.registration.mount.hostContractHash,
          rect: observation.rect,
          occurrenceIndex:
              _nextOccurrence(occurrences, observation.registration.mount),
        ),
    ]);
  }

  final PlacementDiscovery _owner;
  final int epoch;
  final RenderView view;
  final RenderRepaintBoundary? boundary;
  final PlacementLogicalSizeV1 viewport;
  final Size _logicalSize;
  final PlacementBuildContractV1 buildContract;
  final List<_Observation> _geometry;
  late final List<PlacementSampleMountV1> mounts;

  /// Whether declarations, selection, owning view and exact geometry still agree.
  bool get isCurrent {
    if (_owner._epoch != epoch || !view.attached) return false;
    try {
      final frame = boundary ?? view;
      return _owner.buildContract.appBuildContractHash ==
              buildContract.appBuildContractHash &&
          _viewport(frame) == viewport &&
          _frameSize(frame) == _logicalSize &&
          listEquals(_owner._collect(view, frame, strict: true), _geometry);
    } on Object {
      return false;
    }
  }
}

RenderView? placementOwningView(RenderObject? object) {
  for (var current = object; current != null; current = current.parent) {
    if (current is RenderView) return current.attached ? current : null;
  }
  return null;
}

Size _frameSize(RenderObject frame) {
  final Size size;
  if (frame is RenderView && frame.attached) {
    size = frame.size;
  } else if (frame is RenderBox && frame.attached && frame.hasSize) {
    size = frame.size;
  } else {
    throw const FormatException(
        'The capture frame is detached or not laid out.');
  }
  return size;
}

PlacementLogicalSizeV1 _viewport(RenderObject frame) {
  final size = _frameSize(frame);
  return PlacementLogicalSizeV1.fromLogical(
      width: size.width, height: size.height);
}

int _nextOccurrence(
    Map<(PlacementKeyV1, String), int> counts, PlacementMountRequestV1 mount) {
  final identity = (mount.key, mount.hostContractHash);
  final next = counts[identity] ?? 0;
  counts[identity] = next + 1;
  return next;
}

final class _Observation {
  const _Observation(this.registration, this.box, this.view, this.rect,
      this.viewport, this.logicalRect, this.logicalSize);

  final PlacementDiscoveryRegistration registration;
  final RenderBox box;
  final RenderView view;
  final PlacementLogicalRectV1 rect;
  final PlacementLogicalSizeV1 viewport;
  final Rect logicalRect;
  final Size logicalSize;

  @override
  bool operator ==(Object other) =>
      other is _Observation &&
      identical(registration, other.registration) &&
      identical(box, other.box) &&
      identical(view, other.view) &&
      rect == other.rect &&
      viewport == other.viewport &&
      logicalRect == other.logicalRect &&
      logicalSize == other.logicalSize;

  @override
  int get hashCode => Object.hash(
      registration, box, view, rect, viewport, logicalRect, logicalSize);
}
