import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart'
    show BuildContext, PageMetrics, ScrollPosition, TickerMode;
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
  // Reports wait for the observed build inputs when configure says they follow.
  bool _inputsPending = false;
  int _epoch = 0;
  int _generation = 0;
  bool _observationScheduled = false;
  Timer? _reportTimer;
  PlacementDiscoveryReportV1? _pendingReport;
  List<int>? _lastReportBytes;
  DateTime Function() _now = DateTime.now;
  // What the server holds from this launch; a report goes out only to change it.
  String? _reportedBuild;
  final Set<String> _reportedMounts = {};
  final Map<String, String> _reportedBounds = {};
  bool _sending = false;
  int _failedSends = 0;
  int _settleHolds = 0;
  List<_Observation> _previousGeometry = [];

  // The build contract is rebuilt only when one of its inputs changes.
  PlacementBuildContractV1? _build;
  InstalledCapability? _buildCapability;

  // The inputs of the last report built, so an unchanged frame builds none.
  _ReportInputs? _reportInputs;

  /// Installs offline build inputs and an optional authenticated report sink.
  void configure({
    required InstalledCapability Function() installedCapability,
    required String platform,
    int? buildOrdinal,
    List<PlacementMountRequestV1> mounts = const [],
    Map<String, SurfaceHostContractV1> contractsByHash = const {},
    Future<bool> Function(PlacementDiscoveryReportV1)? report,
    DateTime Function()? now,
    bool buildInputsPending = false,
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
    _now = now ?? DateTime.now;
    _inputsPending = buildInputsPending;
  }

  /// Replaces observed app facts without removing live registrations. An
  /// omitted [appVersion] keeps the one already known.
  void updateBuildInputs(
      {required String platform, int? buildOrdinal, String? appVersion}) {
    final version = appVersion ?? _appVersion;
    if (!_inputsPending &&
        _platform == platform &&
        _buildOrdinal == buildOrdinal &&
        _appVersion == version) {
      return;
    }
    _inputsPending = false;
    _makeBuild(platform: platform, buildOrdinal: buildOrdinal);
    _platform = platform;
    _buildOrdinal = buildOrdinal;
    _build = null;
    _appVersion = version;
    _epoch++;
    _scheduleObservation();
  }

  /// Merges known declarations without retiring live occurrences.
  void rememberDeclarations({
    required List<PlacementMountRequestV1> mounts,
    required Map<String, SurfaceHostContractV1> contractsByHash,
  }) {
    if (mounts.every(_mounts.contains) &&
        contractsByHash.keys.every(_contracts.containsKey)) {
      return;
    }
    final previous = buildContract;
    final next = _makeBuild(
      mounts: [..._mounts, ...mounts],
      contracts: {..._contracts, ...contractsByHash},
    );
    if (next.appBuildContractHash == previous.appBuildContractHash) return;
    _mounts = next.mounts.toList();
    _contracts = Map.of(next.contractsByHash);
    _build = null;
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
    // A known declaration leaves the build as it is.
    if (!_mounts.contains(mount) ||
        !_contracts.containsKey(hostContract.contentHash)) {
      final nextBuild = _makeBuild(
          mounts: [..._mounts, mount],
          contracts: {..._contracts, hostContract.contentHash: hostContract});
      _mounts = nextBuild.mounts.toList();
      _contracts = Map.of(nextBuild.contractsByHash);
      _build = null;
    }
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
  PlacementBuildContractV1 get buildContract {
    final capability = _installedCapability?.call();
    final cached = _build;
    if (cached != null && capability == _buildCapability) return cached;
    _buildCapability = capability;
    return _build = _makeBuild();
  }

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
        _inputsPending ||
        (mounts.isEmpty &&
            _lastReportBytes == null &&
            _pendingReport == null)) {
      return;
    }
    final PlacementDiscoveryReportV1 report;
    try {
      final build = buildContract;
      final occurrences = <(PlacementKeyV1, String), int>{};
      final bounds = <PlacementMountBoundsV1>[];
      final tracked = <PlacementDiscoveryRegistration>{};
      for (final observation in painted) {
        final registration = observation.registration;
        final index = _nextOccurrence(occurrences, registration.mount);
        // Tickers off is taken to mean not visible, as under an opaque route:
        // the server keeps the last settled bounds.
        if (!TickerMode.getValuesNotifier(registration.context).value.enabled) {
          continue;
        }
        tracked.add(registration);
        final settled = registration._settle(
            _layoutRect(observation), observation.viewport,
            hold: _headerAwayFromStart(observation.box));
        if (settled == null) continue;
        bounds.add(PlacementMountBoundsV1(
          key: registration.mount.key,
          hostContractHash: registration.mount.hostContractHash,
          logicalBounds: settled.$1,
          logicalViewport: settled.$2,
          occurrenceIndex: index,
        ));
      }
      for (final registration in _registrations) {
        if (!tracked.contains(registration)) registration._unsettle();
      }
      // An unchanged frame builds no report.
      final inputs = _ReportInputs(build, _appVersion, _utcDay(), mounts, [
        for (final bound in bounds)
          (
            bound.key,
            bound.hostContractHash,
            bound.occurrenceIndex,
            bound.logicalBounds,
            bound.logicalViewport,
          ),
      ]);
      if (inputs == _reportInputs) return;
      _reportInputs = inputs;
      report = PlacementDiscoveryReportV1(
        mounts: mounts.toList(),
        buildContract: build,
        appBuildContractHash: build.appBuildContractHash,
        appVersion: _appVersion,
        bounds: bounds,
      );
    } on Object {
      return;
    }
    if (_addsNothing(report)) {
      _pendingReport = null;
      _reportTimer?.cancel();
      return;
    }
    if (listEquals(report.canonicalBytes, _pendingReport?.canonicalBytes)) {
      return;
    }
    _pendingReport = report;
    _reportTimer?.cancel();
    // A report held for a first paint goes as soon as that paint settles.
    _reportTimer = Timer(
        _settleHolds > 0 && !_firstPaintSettling
            ? Duration.zero
            : _reportDebounce,
        _sendReport);
  }

  bool get _firstPaintSettling => _registrations.any((registration) =>
      registration._settling && registration._settled == null);

  // Content bounds: each enclosing viewport scrolled to its start, or a paged
  // view to the placement's own page. A pinned sliver keeps its drawn place,
  // which can move with scrolling; see [_headerAwayFromStart].
  PlacementLogicalRectV1 _layoutRect(_Observation observation) {
    RenderObject target = observation.box;
    var rect = Offset.zero & observation.box.size;
    for (var viewport = RenderAbstractViewport.maybeOf(target.parent);
        viewport != null;
        viewport = RenderAbstractViewport.maybeOf(viewport.parent)) {
      try {
        rect = _atScrollStart(viewport, target, rect);
        target = viewport;
      } on Object {
        // A viewport without settled layout leaves the rest as drawn.
        break;
      }
    }
    final bounds = MatrixUtils.transformRect(
        geometryTransformToFrame(target, observation.view), rect);
    return PlacementLogicalRectV1.fromLogical(
        x: bounds.left,
        y: bounds.top,
        width: bounds.width,
        height: bounds.height);
  }

  // The server refreshes a build's recency once per UTC day.
  String _buildFact(PlacementDiscoveryReportV1 report) =>
      '${report.appBuildContractHash}|${report.appVersion}|${_utcDay()}';

  String _utcDay() {
    final day = _now().toUtc();
    return '${day.year}-${day.month}-${day.day}';
  }

  bool _addsNothing(PlacementDiscoveryReportV1 report) {
    if (_reportedBuild != _buildFact(report)) return false;
    final facts = _reportFacts(report);
    return facts.mounts.every(_reportedMounts.contains) &&
        facts.bounds.entries
            .every((entry) => _reportedBounds[entry.key] == entry.value);
  }

  // One send at a time. Its facts count as reported only once the sink
  // accepts it; a refused send is retried with a bounded backoff.
  void _sendReport() {
    final report = _pendingReport;
    final sink = _report;
    if (report == null || sink == null || _sending) return;
    // A first paint still settling joins this report, for a bounded wait.
    if (_firstPaintSettling && _settleHolds < _maxSettleHolds) {
      _settleHolds++;
      _reportTimer = Timer(_reportDebounce, _sendReport);
      return;
    }
    _settleHolds = 0;
    _pendingReport = null;
    _sending = true;
    final generation = _generation;
    unawaited(Future<bool>.sync(() => sink(report))
        .catchError((Object _) => false)
        .then((sent) {
      if (generation != _generation) return;
      _sending = false;
      if (sent) {
        _failedSends = 0;
        _lastReportBytes = report.canonicalBytes;
        final build = _buildFact(report);
        if (build != _reportedBuild) {
          _reportedMounts.clear();
          _reportedBounds.clear();
          _reportedBuild = build;
        }
        final facts = _reportFacts(report);
        _reportedMounts.addAll(facts.mounts);
        _reportedBounds.addAll(facts.bounds);
        final next = _pendingReport;
        if (next != null && _addsNothing(next)) {
          _pendingReport = null;
          _reportTimer?.cancel();
        } else if (next != null && _reportTimer?.isActive != true) {
          _reportTimer = Timer(_reportDebounce, _sendReport);
        }
        return;
      }
      _pendingReport ??= report;
      if (_failedSends >= _retryDelays.length) return;
      _reportTimer?.cancel();
      _reportTimer = Timer(_retryDelays[_failedSends++], _sendReport);
    }));
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
    _inputsPending = false;
    _pendingReport = null;
    _lastReportBytes = null;
    _reportedBuild = null;
    _reportedMounts.clear();
    _reportedBounds.clear();
    _sending = false;
    _failedSends = 0;
    _settleHolds = 0;
    _previousGeometry = [];
    _now = DateTime.now;
    _build = null;
    _buildCapability = null;
    _reportInputs = null;
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
  (PlacementLogicalRectV1, PlacementLogicalSizeV1)? _seen;
  (PlacementLogicalRectV1, PlacementLogicalSizeV1)? _settled;
  Timer? _settleTimer;

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

  // Bounds settle once they hold still for the settle window; until then the
  // last settled bounds stand.
  (PlacementLogicalRectV1, PlacementLogicalSizeV1)? _settle(
      PlacementLogicalRectV1 rect, PlacementLogicalSizeV1 viewport,
      {required bool hold}) {
    // Held bounds keep the last settled ones; a first settle is never held.
    if (hold && _settled != null) {
      _unsettle();
      return _settled;
    }
    final seen = (rect, viewport);
    if (seen != _seen) {
      _seen = seen;
      _settleTimer?.cancel();
      _settleTimer = Timer(_settleWindow, () {
        _settled = seen;
        _owner._scheduleObservation();
      });
    }
    return _settled;
  }

  bool get _settling => _settleTimer?.isActive ?? false;

  void _unsettle() {
    _seen = null;
    _settleTimer?.cancel();
  }

  /// Marks the host's committed first paint; repeated marks are inert.
  void markPainted() {
    if (!_current || _painted) return;
    _painted = true;
    _owner._epoch++;
    _owner._scheduleObservation();
  }

  /// Removes this occurrence and invalidates captures that included it.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _settleTimer?.cancel();
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

const _reportDebounce = Duration(milliseconds: 250);
const _settleWindow = Duration(milliseconds: 250);

/// Debounce periods a report waits for a first paint to settle.
const _maxSettleHolds = 4;

/// Retry delays after a refused report; afterwards only a changed
/// observation sends again.
const _retryDelays = [
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 16),
  Duration(seconds: 30),
];

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

/// [rect] in [viewport]'s coordinates with the viewport at its scroll start.
Rect _atScrollStart(
    RenderAbstractViewport viewport, RenderObject target, Rect rect) {
  final leading = viewport.getOffsetToReveal(target, 0, rect: rect);
  if (!leading.offset.isFinite) return leading.rect;
  final Offset step;
  if (viewport is RenderViewportBase) {
    step = switch (viewport.axisDirection) {
      AxisDirection.down => const Offset(0, -1),
      AxisDirection.up => const Offset(0, 1),
      AxisDirection.right => const Offset(-1, 0),
      AxisDirection.left => const Offset(1, 0),
    };
  } else {
    // How far the content moves for each pixel scrolled.
    final trailing = viewport.getOffsetToReveal(target, 1, rect: rect);
    final scrolled = leading.offset - trailing.offset;
    if (!trailing.offset.isFinite || scrolled.abs() < 1e-6) return leading.rect;
    step = (leading.rect.topLeft - trailing.rect.topLeft) / scrolled;
  }
  return leading.rect
      .shift(step * (_scrollStart(viewport, leading.offset) - leading.offset));
}

/// Whether [box] sits in a persistent header whose list is scrolled away from
/// its start. Collapsing and sticky headers move there. Their placements take
/// new bounds only at the scroll start, after their first settle.
bool _headerAwayFromStart(RenderObject box) {
  for (var node = box.parent; node != null; node = node.parent) {
    if (node is! RenderSliverPersistentHeader) continue;
    final viewport = RenderAbstractViewport.maybeOf(node);
    if (viewport is! RenderViewportBase) return false;
    final offset = viewport.offset;
    if (!offset.hasPixels) return false;
    final start = offset is ScrollPosition && offset.hasContentDimensions
        ? offset.minScrollExtent
        : 0.0;
    return (offset.pixels - start).abs() > 0.5;
  }
  return false;
}

/// Zero, or in a paged view the start of the page holding [offset].
double _scrollStart(RenderAbstractViewport viewport, double offset) {
  final position = viewport is RenderViewportBase ? viewport.offset : null;
  if (position is! PageMetrics) return 0;
  final metrics = position as PageMetrics;
  if (!metrics.hasViewportDimension) return 0;
  final dimension = metrics.viewportDimension;
  final page = dimension * metrics.viewportFraction;
  if (page <= 0) return 0;
  final first = math.max(0.0, dimension * (metrics.viewportFraction - 1) / 2);
  return ((offset - first) / page + 1e-6).floorToDouble() * page + first;
}

int _nextOccurrence(
    Map<(PlacementKeyV1, String), int> counts, PlacementMountRequestV1 mount) {
  final identity = (mount.key, mount.hostContractHash);
  final next = counts[identity] ?? 0;
  counts[identity] = next + 1;
  return next;
}

/// Each reported mount, and each mount's reported bounds.
({Set<String> mounts, Map<String, String> bounds}) _reportFacts(
    PlacementDiscoveryReportV1 report) {
  final bounds = <String, List<Object?>>{};
  for (final bound in report.bounds) {
    (bounds['${jsonEncode(bound.key.toJson())}|${bound.hostContractHash}'] ??=
            [])
        .add(bound.toJson());
  }
  return (
    mounts: {for (final mount in report.mounts) jsonEncode(mount.toJson())},
    bounds: bounds.map((mount, value) => MapEntry(mount, jsonEncode(value))),
  );
}

/// What a discovery report is built from.
final class _ReportInputs {
  _ReportInputs(
      this.build, this.appVersion, this.day, this.mounts, this.bounds);

  final PlacementBuildContractV1 build;
  final String? appVersion;
  final String day;
  final Set<PlacementMountRequestV1> mounts;
  final List<
      (
        PlacementKeyV1,
        String,
        int,
        PlacementLogicalRectV1,
        PlacementLogicalSizeV1
      )> bounds;

  @override
  bool operator ==(Object other) =>
      other is _ReportInputs &&
      identical(other.build, build) &&
      other.appVersion == appVersion &&
      other.day == day &&
      setEquals(other.mounts, mounts) &&
      listEquals(other.bounds, bounds);

  @override
  int get hashCode => Object.hash(build, appVersion, day, mounts.length);
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
