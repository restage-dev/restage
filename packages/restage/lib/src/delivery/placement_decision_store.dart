import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_measurement_schema/canonical_forms.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/rfw.dart' as rfw;

import '../restage_rpc_client/placement_delivery_adapter.dart';
import '../restage_rpc_client/restage_rpc_client.dart'
    show storedSurfaceAssignmentKey;
import 'decoded_surface_library.dart';
import 'placement_fit_verdicts.dart';
import 'surface_artifact_store.dart';
import 'raced_surface_resolver.dart';
import '../surface_screen/surface_screen_runtime_provenance.dart'
    show
        SurfaceScreenContract,
        SurfaceScreenContractSource,
        decodeSurfaceScreenContract;

/// A saved decision or frame, with the decision decoded when it was read.
@internal
typedef SavedRow = ({StoredSurface stored, PlacementBatchEntryV1? decision});

/// Decisions and frames read before the first mount, kept in step with this
/// process's writes and removals.
@internal
final class SavedDecisions {
  SavedDecisions(Future<Map<SurfaceStoreKey, SavedRow>> rows) {
    _rows = rows.then((loaded) => _loaded = loaded);
  }

  late Future<Map<SurfaceStoreKey, SavedRow>> _rows;
  Map<SurfaceStoreKey, SavedRow>? _loaded;
  int _version = 0;
  bool _dropped = false;

  /// The rows after the read ahead and every change made so far.
  Future<Map<SurfaceStoreKey, SavedRow>> get rows {
    final loaded = _loaded;
    return loaded == null ? _rows : Future.value(loaded);
  }

  /// The rows once the read ahead has loaded and while they follow the store.
  Map<SurfaceStoreKey, SavedRow>? get rowsNow => _dropped ? null : _loaded;

  /// Counts changes, so a read can tell one landed while it ran.
  int get version => _version;

  /// Whether the rows no longer follow the store; reads then go to storage.
  bool get isDropped => _dropped;

  void drop() => _dropped = true;

  /// Applies [change] after the read ahead and every earlier change.
  void update(void Function(Map<SurfaceStoreKey, SavedRow> rows) change) {
    _version++;
    final loaded = _loaded;
    if (loaded != null) return change(loaded);
    _rows = _rows.then((rows) {
      change(rows);
      return rows;
    });
  }
}

/// Placement metadata and shared frames in the existing artifact store.
@internal
final class PlacementDecisionStore {
  PlacementDecisionStore(
      {required this.scope, required this.store, this.saved});

  final String scope;
  final SurfaceArtifactStore store;

  /// The read ahead, kept in step with this store's writes and removals.
  final SavedDecisions? saved;

  /// This scope's decisions with the frames they name, and its remembered
  /// mounts, read and decoded in one pass away from the frame isolate.
  /// With [installed], each decision's fit on its remembered host is judged
  /// in the same pass, which also decodes each of [hostContracts] and
  /// [screenContracts].
  Future<SavedReadAhead> readAhead(
      {InstalledCapability? installed,
      List<Map<String, Object?>> hostContracts = const [],
      List<SurfaceScreenContractSource> screenContracts = const [],
      BuildSeedInputs? build}) async {
    final (decisions, frames, mounts, contracts, screens, seed, forms) =
        await readStoreScope(
            store,
            scope,
            const {'placementDecision', 'placementArtifact', 'placementMount'},
            (rows) => _readAheadHere(
                rows, installed, hostContracts, screenContracts, build));
    adoptCanonicalForms(forms);
    final rows = <SurfaceStoreKey, SavedRow>{};
    for (final (key, value, decision, fit) in decisions) {
      if (decision != null) _decodedFrom[decision] = value.descriptorJson;
      if ((decision, fit, installed)
          case (
            final PlacementBatchAvailableV1 available,
            final verdict?,
            final runtime?
          )) {
        notePlacementFitVerdict(
            available.publicDelivery.fitRequirement,
            available.descriptor.hostContractHash,
            runtime.contentHash,
            verdict);
      }
      rows[key] = (stored: value, decision: decision);
    }
    for (final (key, value, artifact, library) in frames) {
      if (artifact != null) noteVerifiedArtifact(value.artifactBytes, artifact);
      if (artifact?.payload case final BlobSurfacePayload payload
          when library != null) {
        noteDecodedSurfaceLibrary(payload.blob, library);
      }
      rows[key] = (stored: value, decision: null);
    }
    return (
      saved: rows,
      contracts: contracts,
      screenContracts: screens,
      build: seed,
      mounts: [
        for (final (key, known) in mounts)
          if (known != null && mountKey(known.mount) == key) known,
      ],
    );
  }

  SurfaceStoreKey mountKey(PlacementMountRequestV1 mount) => SurfaceStoreKey(
        scope: scope,
        surfaceType: 'placementMount',
        slug: _hash(mount.canonicalBytes),
        contractVersion: 1,
      );

  Future<void> remember(PlacementMountRequestV1 mount,
      SurfaceHostContractV1 host, bool Function() isCurrent) async {
    if (!isCurrent()) return;
    await store.write(
        mountKey(mount),
        StoredSurface(
          descriptorJson: CanonicalJsonCodec.encode({
            'mount': mount.toJson(),
            'host': host.toJson(),
          }),
          artifactBytes: Uint8List(0),
        ));
  }

  Future<void> forget(PlacementMountRequestV1 mount) =>
      store.remove(mountKey(mount));

  // A decision is kept per mount and installed runtime; the build ordinal is
  // judged like any fact it consulted.
  SurfaceStoreKey decisionKey(
          PlacementBatchRequestV1 request, PlacementMountRequestV1 mount,
          {required TargetCoordinate target}) =>
      decisionKeyFor(mount,
          platform: request.buildContract.platform,
          installedCapabilityHash:
              request.buildContract.installedCapabilityHash,
          target: target);

  SurfaceStoreKey decisionKeyFor(PlacementMountRequestV1 mount,
          {required String platform,
          required String installedCapabilityHash,
          required TargetCoordinate target}) =>
      SurfaceStoreKey(
        scope: scope,
        surfaceType: 'placementDecision',
        slug: _hash(CanonicalJsonCodec.encode({
          'mount': mount.toJson(),
          'platform': platform,
          'installedCapability': installedCapabilityHash,
          'target': target.toJson(),
        })),
        contractVersion: 3,
      );

  /// Whether this scope holds no artifact, so an answer may carry the closure.
  Future<bool> holdsNoArtifacts() async => !(await store.keys()).any(
      (key) => key.scope == scope && key.surfaceType == 'placementArtifact');

  SurfaceStoreKey _artifactKey(
          TargetCoordinate target, ArtifactIdentityV1 identity) =>
      SurfaceStoreKey(
          scope: scope,
          surfaceType: 'placementArtifact',
          slug: _hash(CanonicalJsonCodec.encode({
            'target': target.toJson(),
            'identity': identity.toJson(),
          })),
          contractVersion: identity.payloadFormatVersion);

  /// Frames become durable before metadata can point at them. The placement's
  /// other decisions and the frames nothing names are then evicted, after the
  /// caller has its answer.
  Future<void> write(
      SurfaceStoreKey key,
      PlacementBatchAvailableV1 decision,
      PlacementDeliveryArtifacts artifacts,
      Map<String, Object?> sidecar,
      bool Function() isCurrent) {
    final target = decision.descriptor.placement.target;
    final frames = <SurfaceStoreKey, StoredSurface>{};
    for (final ref in decision.artifactClosure) {
      final bytes = artifacts.frames[ref.identity];
      if (bytes == null) return Future<void>.value();
      frames[_artifactKey(target, ref.identity)] = StoredSurface(
          descriptorJson: ref.identity.canonicalBytes, artifactBytes: bytes);
    }
    final placement = _hash(decision.descriptor.placement.canonicalBytes);
    final row = StoredSurface(
        descriptorJson: decision.canonicalBytes,
        artifactBytes: Uint8List(0),
        sidecar: {
          ...sidecar,
          'placement': placement,
          'frames': [for (final frame in frames.keys) frame.toJson()],
        });
    // A remount reads what was just accepted from memory.
    saved?.update((rows) {
      for (final MapEntry(:key, :value) in frames.entries) {
        rows[key] = (stored: value, decision: null);
      }
      if (!_keepsHeld(rows[key]?.stored, row)) {
        _decodedFrom[decision] = row.descriptorJson;
        rows[key] = (stored: row, decision: decision);
      }
    });
    final written = (_writes[store] ?? Future<void>.value())
        .then((_) => _write(key, row, frames, isCurrent));
    _writes[store] = written
        .then((stored) => stored
            ? _evict(keep: key, placement: placement)
            : Future<void>.value())
        .catchError((Object _) {});
    return written.then((_) {});
  }

  // A keyless decision never replaces one held under this device's key.
  static bool _keepsHeld(StoredSurface? held, StoredSurface row) =>
      held != null &&
      storedSurfaceAssignmentKey(row) == null &&
      storedSurfaceAssignmentKey(held) != null;

  // Writes and their evictions run one at a time per store, so an eviction
  // never sees frames whose decision is still being written.
  static final _writes = Expando<Future<void>>();

  /// Completes when every write begun on [store] so far has settled.
  static Future<void> writesSettled(SurfaceArtifactStore store) =>
      _writes[store] ?? Future<void>.value();

  // Whether the decision was stored.
  Future<bool> _write(
      SurfaceStoreKey key,
      StoredSurface row,
      Map<SurfaceStoreKey, StoredSurface> frames,
      bool Function() isCurrent) async {
    var stored = false;
    try {
      for (final MapEntry(:key, :value) in frames.entries) {
        if (!isCurrent()) return false;
        await store.write(key, value);
      }
      if (!isCurrent()) return false;
      stored = await persistAcceptedDelivery(store, key, row,
          publicationGuard: isCurrent, rethrowFailure: true);
      return stored;
    } finally {
      // The rows follow what storage holds once the write settles.
      final held = await store.read(key).catchError((Object _) => null);
      saved?.update((rows) {
        final kept = rows[key]?.stored;
        if (held == null) {
          rows.remove(key);
        } else if (kept == null ||
            !_sameBytes(held.descriptorJson, kept.descriptorJson)) {
          rows[key] = (stored: held, decision: null);
        }
      });
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _evict(
      {required SurfaceStoreKey keep, required String placement}) async {
    final kept = await store.read(keep);
    // Nothing is evicted for a decision that was not stored.
    if (kept == null) return;
    final named = <SurfaceStoreKey>{...?_framesOf(kept)};
    final frames = <SurfaceStoreKey>[];
    for (final key in await store.keys()) {
      if (key.scope != scope || key == keep) continue;
      if (key.surfaceType == 'placementArtifact') {
        frames.add(key);
      } else if (key.surfaceType == 'placementDecision') {
        final stored = await store.read(key);
        if (stored == null) continue;
        final framesOf = _framesOf(stored);
        if (framesOf == null || stored.sidecar['placement'] == placement) {
          await remove(key);
        } else {
          named.addAll(framesOf);
        }
      }
    }
    for (final frame in frames) {
      if (!named.contains(frame)) await remove(frame);
    }
  }

  /// The frames a decision this version wrote names, or null for another
  /// version's row.
  static List<SurfaceStoreKey>? _framesOf(StoredSurface stored) {
    final frames = stored.sidecar['frames'];
    if (stored.sidecar['placement'] is! String || frames is! List) return null;
    final keys = <SurfaceStoreKey>[];
    for (final frame in frames) {
      final key = SurfaceStoreKey.tryFromJson(frame);
      if (key == null) return null;
      keys.add(key);
    }
    return keys;
  }

  /// Re-enters the strict batch codec, with the complete stored frame closure.
  Future<
          ({
            PlacementBatchResolvedV1 response,
            Map<ArtifactIdentityV1, Uint8List> frames,
          })?>
      read(
          {required PlacementBatchRequestV1 request,
          required String configurationFingerprint,
          TargetCoordinate? expectedTarget,
          required Future<bool> Function(
                  StoredSurface stored, PlacementBatchAvailableV1 decision)
              acceptsStored}) async {
    final snapshot = saved;
    // A change during a read repeats it against the changed rows.
    for (var attempt = 0;
        snapshot != null && !snapshot.isDropped && attempt < 3;
        attempt++) {
      final version = snapshot.version;
      final Map<SurfaceStoreKey, SavedRow> rows;
      try {
        rows = await snapshot.rows;
      } on Object {
        break;
      }
      final found = await _read(rows, request, configurationFingerprint,
          expectedTarget, acceptsStored);
      if (snapshot.isDropped) break;
      if (snapshot.version == version) return found;
    }
    return _read(
        null, request, configurationFingerprint, expectedTarget, acceptsStored);
  }

  Future<
          ({
            PlacementBatchResolvedV1 response,
            Map<ArtifactIdentityV1, Uint8List> frames,
          })?>
      _read(
          Map<SurfaceStoreKey, SavedRow>? rows,
          PlacementBatchRequestV1 request,
          String configurationFingerprint,
          TargetCoordinate? expectedTarget,
          Future<bool> Function(
                  StoredSurface stored, PlacementBatchAvailableV1 decision)
              acceptsStored) async {
    final mount = request.mounts.single;
    Future<StoredSurface?> rowAt(SurfaceStoreKey key) async =>
        rows == null ? store.read(key) : rows[key]?.stored;
    final Iterable<SurfaceStoreKey> keys;
    try {
      keys = expectedTarget == null
          ? (rows?.keys ?? await store.keys()).where((key) =>
              key.scope == scope && key.surfaceType == 'placementDecision')
          : [decisionKey(request, mount, target: expectedTarget)];
    } on Object {
      return null;
    }
    // One unreadable entry never hides the others; it is dropped.
    for (final key in keys.toList()) {
      try {
        final stored = await rowAt(key);
        if (stored == null ||
            stored.sidecar['authenticatedConfigurationFingerprint'] !=
                configurationFingerprint) {
          continue;
        }
        final PlacementBatchEntryV1 decision;
        try {
          final held = rows?[key]?.decision;
          // A held decision is used only with the exact bytes it came from.
          if (held != null &&
              identical(_decodedFrom[held], stored.descriptorJson)) {
            decision = held;
          } else {
            decision =
                PlacementBatchEntryV1.fromCanonicalBytes(stored.descriptorJson);
            _decodedFrom[decision] = stored.descriptorJson;
          }
        } on Object {
          await remove(key);
          continue;
        }
        if (decision is! PlacementBatchAvailableV1 ||
            stored.sidecar['authenticatedDeliveryDigest'] !=
                decision.publicDelivery.publicProjectionDigest.hex) {
          continue;
        }
        final target = decision.descriptor.placement.target;
        if ((expectedTarget != null && target != expectedTarget) ||
            key != decisionKey(request, mount, target: target) ||
            !await acceptsStored(stored, decision)) {
          continue;
        }
        final frames = <ArtifactIdentityV1, Uint8List>{};
        var complete = true;
        for (final identity
            in decision.artifactClosure.map((ref) => ref.identity).toSet()) {
          final artifact = await rowAt(_artifactKey(target, identity));
          if (artifact == null ||
              ArtifactIdentityV1.fromCanonicalBytes(artifact.descriptorJson) !=
                  identity) {
            complete = false;
            break;
          }
          frames[identity] = artifact.artifactBytes;
        }
        if (!complete) continue;
        return (
          // A decision decoded from these exact bytes is not decoded again.
          response: identical(_decodedFrom[decision], stored.descriptorJson)
              ? PlacementBatchResolvedV1.fromBuiltRows(
                  request: request,
                  expectedTarget: target,
                  decisions: [decision])
              : PlacementBatchResolvedV1(
                  request: request,
                  expectedTarget: target,
                  decisions: [decision]),
          frames: frames,
        );
      } on Object {
        continue;
      }
    }
    return null;
  }

  Future<void> remove(SurfaceStoreKey key) {
    saved?.update((rows) => rows.remove(key));
    return store.remove(key);
  }

  Future<void> removeAccepted(
      SurfaceStoreKey key, PlacementBatchAvailableV1 accepted) {
    bool matches(StoredSurface stored) {
      final current =
          PlacementBatchEntryV1.fromCanonicalBytes(stored.descriptorJson);
      return current is PlacementBatchAvailableV1 &&
          current.publicDelivery.publicProjectionDigest ==
              accepted.publicDelivery.publicProjectionDigest &&
          current.watch?.decisionIdentityDigest ==
              accepted.watch?.decisionIdentityDigest;
    }

    saved?.update((rows) {
      final row = rows[key];
      if (row != null && matches(row.stored)) rows.remove(key);
    });
    return evictAcceptedDelivery(store, key, matches);
  }

  static String _hash(List<int> bytes) =>
      crypto.sha256.convert(bytes).toString();
}

// The bytes each held decision was decoded from or written as.
final _decodedFrom = Expando<List<int>>('placement decision bytes');

/// A remembered mount and the host contract it was declared with.
@internal
typedef KnownMount = ({
  PlacementMountRequestV1 mount,
  SurfaceHostContractV1 host
});

/// The saved rows and remembered mounts one read ahead found.
@internal
typedef SavedReadAhead = ({
  Map<SurfaceStoreKey, SavedRow> saved,
  List<KnownMount> mounts,
  List<SurfaceHostContractV1?> contracts,
  List<SurfaceScreenContract?> screenContracts,
  BuildSeed? build,
});

/// The platform and the declared mounts, in the order of their host
/// contracts, that the read ahead builds the first build contract from.
@internal
typedef BuildSeedInputs = ({
  String platform,
  List<(PlacementKeyV1, DeliverySurfaceLocatorV1?)> declared,
});

/// A build contract for the declared and remembered mounts with no build
/// ordinal, built by the read ahead.
@internal
typedef BuildSeed = ({
  String platform,
  Map<PlacementMountRequestV1, SurfaceHostContractV1> mounts,
  InstalledCapability installed,
  PlacementBuildContractV1 contract,
});

typedef _ReadAheadRows = (
  List<
      (
        SurfaceStoreKey,
        StoredSurface,
        PlacementBatchEntryV1?,
        SurfaceFitVerdictV1?
      )>,
  List<_FrameRow>,
  List<(SurfaceStoreKey, KnownMount?)>,
  List<SurfaceHostContractV1?>,
  List<SurfaceScreenContract?>,
  BuildSeed?,
  CanonicalForms,
);

_ReadAheadRows _readAheadHere(
    StoredScopeRows all,
    InstalledCapability? installed,
    List<Map<String, Object?>> hostContracts,
    List<SurfaceScreenContractSource> screenContracts,
    BuildSeedInputs? build) {
  final byKey = {for (final (key, value) in all) key: value};
  final decisions = <(SurfaceStoreKey, StoredSurface)>[];
  final mounts = <(SurfaceStoreKey, StoredSurface)>[];
  final named = <SurfaceStoreKey>{};
  for (final (key, value) in all) {
    if (key.surfaceType == 'placementMount') mounts.add((key, value));
    if (key.surfaceType != 'placementDecision') continue;
    // A row this version did not write is evicted by the next write.
    final frames = PlacementDecisionStore._framesOf(value);
    if (frames == null) continue;
    decisions.add((key, value));
    named.addAll(frames);
  }
  final ((saved, frames, known, contracts, screens, seed), forms) =
      recordCanonicalForms(() {
    final known = [
      for (final (key, value) in mounts)
        (key, _decodeMount(value.descriptorJson))
    ];
    final hosts = {
      for (final (_, mount) in known)
        if (mount != null) mount.host.contentHash: mount.host
    };
    final contracts = [
      for (final json in hostContracts) _decodeHostContract(json)
    ];
    // A decision's fit on the host it was remembered with.
    SurfaceFitVerdictV1? fitOf(PlacementBatchEntryV1? decision) =>
        switch ((decision, installed)) {
          (final PlacementBatchAvailableV1 available, final runtime?)
              when hosts[available.descriptor.hostContractHash] != null =>
            SurfaceFitEvaluator.evaluate(
                host: hosts[available.descriptor.hostContractHash]!,
                requirement: available.publicDelivery.fitRequirement,
                installed: runtime),
          _ => null,
        };
    return (
      [
        for (final (key, value) in decisions)
          if (_decodeEntry(value.descriptorJson) case final decision)
            (key, value, decision, fitOf(decision))
      ],
      [
        for (final key in named)
          if (byKey[key] case final value?) _frameRow(key, value)
      ],
      known,
      contracts,
      [for (final source in screenContracts) _decodeScreenContract(source)],
      _seedBuild(build, installed, contracts, known),
    );
  });
  return (saved, frames, known, contracts, screens, seed, forms);
}

// The build contract a first capture would build, from the same host
// contract instances the frame isolate adopts; null when one is missing.
BuildSeed? _seedBuild(
    BuildSeedInputs? build,
    InstalledCapability? installed,
    List<SurfaceHostContractV1?> contracts,
    List<(SurfaceStoreKey, KnownMount?)> known) {
  if (build == null ||
      installed == null ||
      build.declared.length != contracts.length) {
    return null;
  }
  try {
    final mounts = <PlacementMountRequestV1, SurfaceHostContractV1>{};
    for (final (index, (key, locator)) in build.declared.indexed) {
      final host = contracts[index];
      if (host == null) return null;
      mounts[PlacementMountRequestV1(
          key: key,
          hostContractHash: host.contentHash,
          defaultSurface: locator)] = host;
    }
    final declared = mounts.keys.toSet();
    for (final (key, remembered) in known) {
      if (remembered == null ||
          key.slug !=
              PlacementDecisionStore._hash(remembered.mount.canonicalBytes) ||
          // An older build's generated mount is forgotten.
          (remembered.mount.key.isGeneratedDefault &&
              !declared.contains(remembered.mount))) {
        continue;
      }
      mounts.putIfAbsent(remembered.mount, () => remembered.host);
    }
    return (
      platform: build.platform,
      mounts: mounts,
      installed: installed,
      contract: PlacementBuildContractV1(
          platform: build.platform,
          mounts: mounts.keys.toList(),
          contractsByHash: {
            for (final host in mounts.values) host.contentHash: host
          },
          installedCapability: installed,
          installedCapabilityHash: installed.contentHash),
    );
  } on Object {
    return null;
  }
}

// A generated screen's schemas, decoded and hashed; null when invalid, so
// its provenance decodes them again and reports why.
SurfaceScreenContract? _decodeScreenContract(
    SurfaceScreenContractSource source) {
  try {
    return decodeSurfaceScreenContract(source);
  } on Object {
    return null;
  }
}

// A generated host contract, decoded and hashed; null when it is invalid,
// so its definition decodes it again and reports why.
SurfaceHostContractV1? _decodeHostContract(Map<String, Object?> json) {
  try {
    return SurfaceHostContractV1.fromJson(json)..contentHash;
  } on Object {
    return null;
  }
}

KnownMount? _decodeMount(Uint8List bytes) {
  try {
    final json = CanonicalJsonCodec.decode(bytes) as Map;
    final mount = PlacementMountRequestV1.fromJson(json['mount']);
    final host = SurfaceHostContractV1.fromJson(json['host']);
    return host.contentHash == mount.hostContractHash
        ? (mount: mount, host: host)
        : null;
  } on Object {
    // Unreadable declarations never become build facts.
    return null;
  }
}

typedef _FrameRow = (
  SurfaceStoreKey,
  StoredSurface,
  PlacementBatchArtifactV1?,
  rfw.RemoteWidgetLibrary?,
);

// A frame verified against its identity, with its widget library decoded.
_FrameRow _frameRow(SurfaceStoreKey key, StoredSurface value) {
  final artifact = _verifyFrame(value.descriptorJson, value.artifactBytes);
  return (
    key,
    value,
    artifact,
    artifact == null ? null : decodePayloadLibrary(artifact.payload)
  );
}

PlacementBatchArtifactV1? _verifyFrame(Uint8List identity, Uint8List bytes) {
  try {
    return PlacementBatchArtifactV1(
        identity: ArtifactIdentityV1.fromCanonicalBytes(identity),
        bytes: bytes);
  } on Object {
    return null;
  }
}

PlacementBatchEntryV1? _decodeEntry(Uint8List bytes) {
  try {
    return PlacementBatchEntryV1.fromCanonicalBytes(bytes);
  } on Object {
    return null;
  }
}
