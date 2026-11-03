import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

import '../delivery/placement_decision_store.dart';
import '../delivery/placement_fit_verdicts.dart';
import '../delivery/raced_surface_resolver.dart';
import '../delivery/surface_artifact_store.dart';
import '../delivery/mounted_surface_report.dart';
import '../resolver/delivery_input_budget.dart';
import '../resolver/placement_fallback_log.dart'
    show
        PlacementNoAnswerCause,
        PlacementNoAnswerStale,
        PlacementNoAnswerUndecodable,
        PlacementNoAnswerUnregistered,
        PlacementStaleChange;
import '../resolver/surface_assignment_key_provider.dart';
import '../resolver/surface_canonical_carrier_provider.dart';
import '../resolver/surface_delivery_observations.dart';
import '../resolver/surface_request_inputs.dart';
import '../resolver/placement_mount_resolver.dart'
    show
        placementCacheIsValid,
        placementDeferredFacts,
        PlacementDeliveryAdmission;
import '../refresh/surface_update_channel.dart';
import 'installed_widget_vocabulary.dart';
import '../restage_rpc_client/placement_delivery_adapter.dart';
import '../delivery/surface_delivery_receipt.dart'
    show SurfaceDeliveryReceiptReason;
import '../restage_rpc_client/restage_rpc_client.dart';
import 'placement_mount.dart';

typedef PlacementDeclaration = ({
  PlacementMountRequestV1 mount,
  SurfaceHostContractV1 host
});

/// Configuration-owned discovery over the existing RPC and artifact store.
@internal
final class PlacementRegistry {
  PlacementRegistry(
      {required this.scope,
      required this.configurationFingerprint,
      required this.client,
      required this.isCurrent,
      this.onBuildInputs,
      this.onDeclarations,
      DateTime Function()? now})
      : now = now ?? DateTime.now;

  final String scope;
  final String configurationFingerprint;
  TargetCoordinate? _storedTarget;
  TargetCoordinate? get target => client().placementTarget ?? _storedTarget;
  final RestageRpcClient Function() client;
  final bool Function() isCurrent;
  final void Function(String platform, int? buildOrdinal)? onBuildInputs;
  final void Function(List<PlacementDeclaration> declarations)? onDeclarations;
  final DateTime Function() now;
  final Map<PlacementMountRequestV1, SurfaceHostContractV1> _mounts = {};

  PlacementDecisionStore get decisions => PlacementDecisionStore(
      scope: scope, store: sharedSurfaceArtifactStore, saved: _saved);

  SavedDecisions? _saved;

  final _accepted = <PlacementMountRequestV1, PlacementAccepted>{};

  /// Remembers what a mount accepted, so a later mount can paint it at once.
  void noteAccepted(
          PlacementMountRequestV1 mount, PlacementAccepted accepted) =>
      _accepted[mount] = accepted;

  /// Accepts, before their mounts, the saved decisions of [declarations] that
  /// read no deferred fact, so a mount's first build can paint them.
  Future<void> warmAccepted(
      Future<List<PlacementDeclaration>> declarations) async {
    await Future.wait([
      for (final declaration in await declarations)
        withSurfaceDeliveryObservations(
          cell: SurfaceDeliveryObservationCell(
              readKnownSurfaceDeliveryObservations),
          resolve: () async {
            final context = await capture(
                mounts: [declaration.mount],
                sendAssignmentKey: false,
                deferFacts: placementDeferredFacts);
            final local = context == null ? null : await this.local(context);
            if (local != null) {
              _accepted.putIfAbsent(declaration.mount, () => local);
            }
          },
        ).catchError((Object _) {}),
    ]);
  }

  /// What a mount last accepted, while the saved rows still hold it.
  PlacementAccepted? acceptedNow(PlacementMountRequestV1 mount) {
    final accepted = _accepted[mount];
    if (accepted == null) return null;
    final request = accepted.context.request;
    final key = decisions.decisionKey(request, request.mounts.single,
        target: accepted.decision.descriptor.placement.target);
    final rows = _saved?.rowsNow;
    if (rows == null) return null;
    // A later answer with the same delivery keeps it; another delivery or
    // no row drops it.
    final digest = rows[key]?.stored.sidecar['authenticatedDeliveryDigest'];
    if (digest != accepted.decision.publicDelivery.publicProjectionDigest.hex) {
      _accepted.remove(mount);
      return null;
    }
    // A stale decision waits for its new answer before it paints.
    if (_saved?.isStale(key) ?? false) return null;
    return accepted;
  }

  /// Reads the saved decisions before the first mount asks for them.
  void warmSaved() => _saved ??=
      SavedDecisions(_readAhead().then((readAhead) => readAhead.saved));

  // The saved rows and remembered mounts, read once per configuration. The
  // same pass decodes the generated host contracts and screen schemas not
  // decoded yet.
  Future<SavedReadAhead> _readAhead() => _readingAhead ??= () async {
        final pending = [
          for (final definition in _generated)
            if (definition.undecodedHostContract != null) definition
        ];
        final screens = [
          for (final definition in _generated)
            if (definition.undecodedScreen case final screen?) screen
        ];
        final installed = currentInstalledCapability();
        final platform = normalizeDeliveryPlatform(
            isWeb: kIsWeb, targetPlatform: defaultTargetPlatform);
        final readAhead = await decisions.readAhead(
            installed: installed,
            hostContracts: [
              for (final definition in pending)
                definition.undecodedHostContract!
            ],
            screenContracts: [
              for (final screen in screens) screen.undecodedContract!
            ],
            build: platform == null
                ? null
                : (
                    platform: platform,
                    declared: [
                      for (final definition in pending)
                        (definition.key, definition.defaultSurfaceLocator)
                    ],
                  ));
        for (final (index, contract) in readAhead.contracts.indexed) {
          if (contract != null) pending[index].adoptHostContract(contract);
        }
        for (final (index, contract) in readAhead.screenContracts.indexed) {
          if (contract != null) screens[index].adoptContract(contract);
        }
        // The first capture reuses the build contract built alongside.
        if (readAhead.build case final seed?) {
          _build = (
            platform: seed.platform,
            ordinal: null,
            mounts: seed.mounts,
            installed: adoptInstalledCapability(installed, seed.installed),
            contract: seed.contract,
          );
        }
        _readAheadDone = readAhead;
        return readAhead;
      }();
  Future<SavedReadAhead>? _readingAhead;
  SavedReadAhead? _readAheadDone;

  /// The read ahead, decoding every declared generated host contract.
  Future<SavedReadAhead> readAhead() => _readAhead();

  /// Whether a finished read ahead holds, for each of [mounts], a saved
  /// decision under the installed capability, which a mount can paint from.
  bool holdsDecisionsFor(Iterable<PlacementMountRequestV1> mounts) {
    final saved = _readAheadDone?.saved;
    final build = _build;
    final wanted = mounts.toList();
    if (saved == null || build == null || wanted.isEmpty) return false;
    final targets = {
      for (final row in saved.values)
        if (row.decision case PlacementBatchAvailableV1(:final descriptor))
          descriptor.placement.target,
    };
    return wanted.every((mount) => targets.any((target) => saved[
            decisions.decisionKeyFor(mount,
                platform: build.platform,
                installedCapabilityHash: build.installed.contentHash,
                target: target)]
        ?.decision is PlacementBatchAvailableV1));
  }

  /// The indexes of [mounts] whose closure the answer should carry: those
  /// this device holds no saved decision for.
  Future<List<int>> _mountsNeedingArtifacts(
      List<PlacementMountRequestV1> mounts) async {
    final saved = _saved?.rowsNow ?? _readAheadDone?.saved;
    if (saved == null) {
      final none = await decisions.holdsNoArtifacts().catchError((_) => false);
      return none ? [for (var i = 0; i < mounts.length; i++) i] : const [];
    }
    // A mount's decision may name another placement than the mount's own key,
    // as a default mount does, so its host contract identifies it.
    final held = <String>{};
    for (final row in saved.values) {
      if (row.decision case PlacementBatchAvailableV1(:final descriptor)) {
        held.add(descriptor.hostContractHash);
      }
    }
    return [
      for (var i = 0; i < mounts.length; i++)
        if (!held.contains(mounts[i].hostContractHash)) i,
    ];
  }

  List<PlacementMountRequestV1> _startupRoster = const [];
  bool _remembering = false;
  bool _rememberAgain = false;

  /// The saved decisions changed, so the request the next launch sends
  /// changes with them; the platform's copy is renewed, one at a time.
  void savedChanged() {
    if (_startupRoster.isEmpty) return;
    if (_remembering) {
      _rememberAgain = true;
      return;
    }
    _remembering = true;
    unawaited(_rememberNextLaunch(_startupRoster).whenComplete(() {
      _remembering = false;
      if (_rememberAgain) {
        _rememberAgain = false;
        savedChanged();
      }
    }));
  }

  /// Keeps the request the next launch will send, so the platform's early
  /// request equals it: the confirmed handle, the held paths, and no tuple.
  /// After an identity reset the platform's copy is renewed with the request
  /// the next launch sends, which registers again.
  Future<void> rememberAfterReset() =>
      _rememberNextLaunch(_startupRoster, registering: true);

  Future<void> _rememberNextLaunch(List<PlacementMountRequestV1> mounts,
      {bool registering = false}) async {
    try {
      await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
      final next = await capture(
          mounts: mounts,
          sendAssignmentKey: true,
          mode: PlacementBatchModeV1.prefetch,
          inlineMounts: await _mountsNeedingArtifacts(mounts),
          startup: true);
      if (next == null ||
          (next.request.assignmentKey == null &&
              !(registering && next.request.registration != null))) {
        return;
      }
      client().rememberStartupRequest(next.request);
    } on Object {
      // The next launch's early request then differs and Dart sends it.
    }
  }

  /// Generated definitions whose host contracts and screen schemas the read
  /// ahead decodes.
  void declareGenerated(Iterable<GeneratedPlacementDefinition> definitions) =>
      _generated.addAll(definitions);
  final _generated = <GeneratedPlacementDefinition>{};

  /// Sends later reads to storage, after a reset.
  void dropSaved() {
    _saved?.drop();
    _saved = null;
    _readingAhead = null;
    _readAheadDone = null;
    _remembered.clear();
  }

  List<PlacementDeclaration> configure(
      Iterable<GeneratedPlacementDefinition> definitions) {
    final configured = <PlacementDeclaration>[];
    for (final definition in definitions) {
      definition.vocabulary.addToInstalled();
      final declaration =
          PlacementMountBinding(definition: () => definition).capture();
      _mounts[declaration.mount] = declaration.host;
      configured.add(declaration);
    }
    onDeclarations?.call(configured);
    return configured;
  }

  /// Mounts remembered from earlier runs. Given the build's generated
  /// [declared] mounts, a remembered generated mount outside them is from an
  /// older build and is forgotten.
  Future<List<PlacementDeclaration>> loadKnownMounts(
      {Set<PlacementMountRequestV1> Function()? declared}) async {
    try {
      final store = decisions;
      final known = <PlacementDeclaration>[];
      final stored = (await _readAhead()).mounts;
      final current = declared?.call() ?? const {};
      for (final declaration in stored) {
        if (current.isNotEmpty &&
            declaration.mount.key.isGeneratedDefault &&
            !current.contains(declaration.mount)) {
          await store.forget(declaration.mount);
          continue;
        }
        known.add(declaration);
      }
      if (!isCurrent()) return [];
      for (final declaration in known) {
        _mounts.putIfAbsent(declaration.mount, () => declaration.host);
        _remembered.add(declaration.mount);
      }
      onDeclarations?.call(known);
      return known;
    } on Object {
      // Startup still includes generated declarations if storage is unavailable.
      return [];
    }
  }

  void remember(PlacementDeclaration declaration) {
    if (!isCurrent()) return;
    _mounts[declaration.mount] = declaration.host;
    onDeclarations?.call([declaration]);
    // A mount saved once, here or by an earlier launch, is not saved again.
    if (!_remembered.add(declaration.mount)) return;
    decisions
        .remember(declaration.mount, declaration.host, isCurrent)
        .catchError((Object _) {});
  }

  final _remembered = <PlacementMountRequestV1>{};

  // The last build contract, reused while what it describes is unchanged.
  ({
    String platform,
    int? ordinal,
    Map<PlacementMountRequestV1, SurfaceHostContractV1> mounts,
    InstalledCapability installed,
    PlacementBuildContractV1 contract,
  })? _build;

  PlacementBuildContractV1 _buildFor(
      String platform,
      int? ordinal,
      Map<PlacementMountRequestV1, SurfaceHostContractV1> mounts,
      InstalledCapability installed,
      String installedHash) {
    final last = _build;
    if (last != null &&
        last.platform == platform &&
        last.ordinal == ordinal &&
        identical(last.installed, installed) &&
        last.mounts.length == mounts.length &&
        mounts.entries
            .every((entry) => identical(last.mounts[entry.key], entry.value))) {
      return last.contract;
    }
    final contract = PlacementBuildContractV1(
        platform: platform,
        buildOrdinal: ordinal,
        mounts: mounts.keys.toList(),
        contractsByHash: {
          for (final host in mounts.values) host.contentHash: host
        },
        installedCapability: installed,
        installedCapabilityHash: installedHash);
    _build = (
      platform: platform,
      ordinal: ordinal,
      mounts: mounts,
      installed: installed,
      contract: contract,
    );
    return contract;
  }

  Future<PlacementRequestContext?> capture(
      {required List<PlacementMountRequestV1> mounts,
      required bool sendAssignmentKey,
      Future<void>? keyDeadline,
      bool Function()? publicationGuard,
      SurfaceAssignmentResolutionLease? retainedLease,
      PlacementBatchModeV1 mode = PlacementBatchModeV1.mount,
      Set<String> deferFacts = const {},
      bool inMemory = false,
      List<int> inlineMounts = const [],
      bool startup = false,
      void Function(String reason, [PlacementNoAnswerCause? cause])?
          onDeclined}) async {
    final declarations =
        Map<PlacementMountRequestV1, SurfaceHostContractV1>.of(_mounts);
    if (mounts.isEmpty || !isCurrent() || !(publicationGuard?.call() ?? true)) {
      onDeclined?.call(placementSupersededReason);
      return null;
    }
    return DeliveryInputBudget.run((budget) async {
      final cell = currentSurfaceDeliveryObservationCell();
      final inputs = await SurfaceRequestInputs.gather(
          budget: budget,
          surface: mounts.first.defaultSurface?.surfaceType.value ?? 'paywall',
          slug: mounts.first.defaultSurface?.slug ?? 'placement',
          sendAssignmentKey: sendAssignmentKey,
          keyDeadline: keyDeadline,
          deferFacts: deferFacts,
          inMemory: inMemory);
      if (!isCurrent() || !(publicationGuard?.call() ?? true)) {
        onDeclined?.call(placementSupersededReason);
        return null;
      }
      if (!inputs.lease.isCurrent) {
        onDeclined?.call(placementStaleReason,
            const PlacementNoAnswerStale(PlacementStaleChange.configuration));
        return null;
      }
      if (!inputs.lease.canSend) {
        onDeclined?.call(PlacementBatchRefusalReasonV1.enrollmentRequired.name,
            PlacementNoAnswerUnregistered(late: inputs.lease.registrationLate));
        return null;
      }
      final observations = inputs.builtIns == null
          ? <String, Object?>{}
          : CanonicalJsonCodec.decode(
              base64Url.decode(base64Url.normalize(inputs.builtIns!))) as Map;
      final platform = observations['platform'] as String? ??
          normalizeDeliveryPlatform(
              isWeb: kIsWeb, targetPlatform: defaultTargetPlatform);
      if (platform == null) {
        onDeclined?.call(SurfaceDeliveryReceiptReason.unsupported.name);
        return null;
      }
      if (!inputs.pendingFacts.contains('appBuildOrdinal')) {
        onBuildInputs?.call(platform, observations['appBuildOrdinal'] as int?);
      }
      final build = _buildFor(
          platform,
          observations['appBuildOrdinal'] as int?,
          declarations,
          inputs.installedCapability,
          inputs.installedCapabilityHash);
      final localNow = now();
      final clock = DeliveryLocalClockV1(localNow.timeZoneOffset.inMinutes);
      // An answer is judged by the facts its request was sent with.
      List<String> changedFacts(List<String> consulted) {
        if (cell == null || consulted.isEmpty) return const [];
        final current = cell.currentBuiltInsBase64;
        if (current == inputs.builtIns) return const [];
        final now = placementBuiltInFacts(current);
        final then = placementBuiltInFacts(inputs.builtIns);
        if (now == null || then == null) return consulted;
        return [
          for (final name in consulted)
            if (now[name] != then[name]) name,
        ];
      }

      final registration = inputs.lease.registration;
      final lease = retainedLease ?? inputs.lease;
      final assignmentKey = (sendAssignmentKey || retainedLease != null) &&
              lease.isCurrent &&
              lease.assignmentsAllowed
          ? lease.assignmentKey
          : null;
      final held = assignmentKey == null
          ? <PlacementHeldAssignmentV1>[]
          : await budget
              .bound(Future.wait([
                for (final mount in mounts)
                  SurfaceCanonicalCarrierProvider.heldPlacement(
                          mount: mount, assignmentKey: assignmentKey)
                      .then((carrier) {
                    if (carrier == null) return null;
                    final assignment =
                        PresentationAssignmentCarrierV2.fromCanonicalBytes(
                            base64Url.decode(base64Url.normalize(carrier)));
                    if (assignment.owner !=
                        PresentationAssignmentOwnerV2.path) {
                      return Future<PlacementHeldAssignmentV1?>.value(null);
                    }
                    return SurfaceCanonicalCarrierProvider.heldPlacementProof(
                            mount: mount, assignmentKey: assignmentKey)
                        .then((proof) => PlacementHeldAssignmentV1(
                            key: mount.key,
                            hostContractHash: mount.hostContractHash,
                            retainedPathHandle: assignment.outcomeLinkCarrier,
                            proof: proof));
                  })
              ]))
              .then((values) =>
                  values?.whereType<PlacementHeldAssignmentV1>().toList() ??
                  <PlacementHeldAssignmentV1>[]);
      // A mount the service declined for this credential presents its proof.
      final registering = mode != PlacementBatchModeV1.refresh &&
          sendAssignmentKey &&
          registration != null &&
          registration.credentialHandle == null;
      final declines = assignmentKey == null || registering
          ? <PlacementHeldDeclineV1>[]
          : await budget
              .bound(Future.wait([
                for (final mount in mounts)
                  SurfaceCanonicalCarrierProvider.heldDecline(
                          mount: mount, assignmentKey: assignmentKey)
                      .then((proof) => proof == null
                          ? null
                          : PlacementHeldDeclineV1(
                              key: mount.key,
                              hostContractHash: mount.hostContractHash,
                              proof: proof))
              ]))
              .then((values) =>
                  values?.whereType<PlacementHeldDeclineV1>().toList() ??
                  <PlacementHeldDeclineV1>[]);
      // Surfaces mounted since the service last answered ride this request.
      final mounted =
          await budget.bound(MountedSurfaceReport.instance.pending()) ??
              const <PlacementMountedSurfaceV1>[];
      final request = PlacementBatchRequestV1(
          mounts: mounts,
          buildContract: build,
          appBuildContractHash: build.appBuildContractHash,
          mode: mode,
          localClock: clock,
          sdkInstalledLibraries: inputs.sdkInstalledLibraries,
          sdkBuiltInsCanonicalBase64: inputs.builtIns,
          sdkSupportedPolicyRevisions: supportedPolicyRevisionsCarrier(),
          assignmentKey: assignmentKey,
          heldAssignments: held,
          heldDeclines: declines,
          mountedSince: mounted,
          // A confirmed handle travels as the assignment key alone.
          registration: registering
              ? SurfaceRegistrationTupleV1.fromJson(registration.tuple)
              : null,
          meteringKey: inputs.meteringKey,
          analyticsAnonymousId: inputs.analyticsAnonymousId,
          inlineMounts: inlineMounts,
          startup: startup);
      return PlacementRequestContext(
          request: request,
          lease: lease,
          capturedAt: localNow.toUtc(),
          isCurrent: () =>
              isCurrent() &&
              (publicationGuard?.call() ?? true) &&
              inputs.lease.isCurrent &&
              lease.isCurrent &&
              currentInstalledCapability().contentHash ==
                  inputs.installedCapabilityHash,
          capabilityChanged: () =>
              currentInstalledCapability().contentHash !=
              inputs.installedCapabilityHash,
          changedFacts: changedFacts,
          pendingFacts: inputs.pendingFacts,
          superseded: () =>
              !isCurrent() || !(publicationGuard?.call() ?? true));
    });
  }

  Future<void>? _startup;
  Set<PlacementMountRequestV1> _startupMounts = const {};
  final _startupAnswers = <PlacementMountRequestV1,
      ({
    PlacementBatchEntryV1 entry,
    PlacementDeliveryArtifacts artifacts,
    PlacementRequestContext context,
    int index
  })>{};

  /// The startup batch's answer for [waiter]'s mount, taken once, or null
  /// when the mount needs a request of its own.
  ({
    PlacementBatchEntryV1 entry,
    PlacementDeliveryArtifacts artifacts,
    PlacementRequestContext context
  })? _takeStartupAnswer(_MountWaiter waiter, bool sendAssignmentKey) {
    final answer = _startupAnswers[waiter.mount];
    if (answer == null) return null;
    final request = answer.context.request;
    // A batch sent without the key cannot answer a mount that wants one.
    if (!answer.context.isCurrent() ||
        (sendAssignmentKey &&
            request.assignmentKey == null &&
            request.registration == null) ||
        !waiter.guard() ||
        now().toUtc().difference(answer.context.capturedAt) >
            const Duration(seconds: 30)) {
      _startupAnswers.remove(waiter.mount);
      return null;
    }
    _startupAnswers.remove(waiter.mount);
    return (
      entry: answer.entry,
      artifacts: answer.artifacts,
      context: _mountContext(answer.context, waiter),
    );
  }

  /// The startup batch in flight, if any.
  Future<void>? get startup => _startup;

  /// Marks the startup batch as in flight until the returned one completes.
  /// Mounts in [answering] wait for the batch and take its answers.
  /// Holds every mount's request until the startup batch has answered or
  /// failed, from configuration on; the batch names its mounts later, when
  /// their contracts are decoded.
  Completer<void> expectStartup() {
    _startupRosterKnown = false;
    final done = _startupGate = Completer<void>();
    final future = _startup = done.future;
    unawaited(future.whenComplete(() {
      if (identical(_startup, future)) _startup = null;
    }));
    return done;
  }

  Completer<void>? _startupGate;
  bool _startupRosterKnown = true;

  Completer<void> beginStartup(
      [Iterable<PlacementMountRequestV1> answering = const []]) {
    _startupMounts = answering.toSet();
    _startupRosterKnown = true;
    final gate = _startupGate;
    if (gate != null) {
      _startupGate = null;
      return gate;
    }
    final done = Completer<void>();
    final future = _startup = done.future;
    unawaited(future.whenComplete(() {
      if (identical(_startup, future)) _startup = null;
    }));
    return done;
  }

  /// Sends [declarations] in one prefetch; [inMemory] sends only the facts
  /// this process holds without a platform read.
  /// An [assigned] batch carries the assignment key and keeps assigned
  /// decisions, as a mount's request does.
  ///
  /// The startup batch publishes its answers: a mount of one of its
  /// placements takes its answer instead of sending a request of its own.
  Future<void> prefetch(Iterable<PlacementDeclaration> declarations,
      {bool inMemory = false,
      bool assigned = false,
      bool publishAnswers = false}) async {
    final roster = declarations.toList(growable: false);
    if (!isCurrent() || roster.isEmpty) return;
    // A mount batch already on its way answers its own mounts; the startup
    // batch sends only what is left.
    final answered = <PlacementMountRequestV1>{
      for (final batch in _mountBatches.toList()) ...await batch.future,
    };
    final mounts = {
      for (final declaration in roster)
        if (!answered.contains(declaration.mount)) declaration.mount,
    }.toList();
    if (mounts.isEmpty) return;
    // A client holding no artifact is sent the closure with the answer.
    final inline = await _mountsNeedingArtifacts(mounts);
    final context = await capture(
        mounts: mounts,
        sendAssignmentKey: assigned,
        mode: PlacementBatchModeV1.prefetch,
        inMemory: inMemory,
        inlineMounts: inline,
        startup: publishAnswers);
    if (context == null) return;
    if (publishAnswers) _startupRoster = mounts;
    // Most installs run a build the service already holds.
    if (inMemory || publishAnswers) {
      client().expectHeldBuildContract(context.request.appBuildContractHash);
    }
    final response = await fetch(context);
    if (response == null) return;
    if (publishAnswers) {
      // The startup answer is kept: the platform needs the request the next
      // launch will send, which a registering request's handle, the held
      // paths and the saved decisions all change.
      savedChanged();
      for (var index = 0; index < mounts.length; index++) {
        _startupAnswers[mounts[index]] = (
          entry: response.response.decisions[index],
          artifacts: response.artifacts,
          context: context,
          index: index,
        );
      }
    }
    // The answer is usable now; remembering the mounts runs behind it.
    unawaited(() async {
      for (final declaration in roster) {
        if (!mounts.contains(declaration.mount)) continue;
        if (!context.isCurrent()) return;
        await decisions.remember(
            declaration.mount, declaration.host, context.isCurrent);
      }
    }());
  }

  /// Fetches every mount this process knows so saved
  /// content is current the next time the app opens.
  Future<void> refreshKnown() => _startup != null
      // The startup batch in flight asks for every mount already.
      ? Future<void>.value()
      : prefetch([
          for (final entry in _mounts.entries)
            (mount: entry.key, host: entry.value),
        ], assigned: true);

  /// Checks the accepted decision through the same side-effect-free batch route.
  Future<PlacementRefreshProbeV1> probe(PlacementDeliveryAdmission accepted,
      PlacementRefreshStateV1 rendered) async {
    if (accepted.refreshState?.decisionIdentityDigest !=
            rendered.decisionIdentityDigest ||
        !accepted.context.isCurrent()) {
      return const PlacementRefreshProbeV1.requiresResolution();
    }
    final context = await capture(
        mounts: accepted.context.request.mounts,
        sendAssignmentKey: false,
        retainedLease: accepted.context.lease,
        mode: PlacementBatchModeV1.refresh,
        publicationGuard: accepted.context.isCurrent);
    if (context == null) return const PlacementRefreshProbeV1.unavailable();
    Duration? retryAfter;
    // A request whose inputs changed in flight needs a fresh decision.
    final response = await fetchBatch(context,
        expectedTarget: accepted.delivery.mount.placement.target,
        onRateLimited: (delay) => retryAfter = delay);
    if (retryAfter != null) {
      return PlacementRefreshProbeV1.rateLimited(retryAfter!);
    }
    if (response is PlacementBatchResolvedV1) {
      await _forgetUnprovenCarriers(context, response);
    }
    if (!context.isCurrent() ||
        response is! PlacementBatchResolvedV1 ||
        response.decisions.single is! PlacementBatchAvailableV1) {
      return const PlacementRefreshProbeV1.requiresResolution();
    }
    final decision = response.decisions.single as PlacementBatchAvailableV1;
    final watch = decision.watch;
    return watch == null
        ? const PlacementRefreshProbeV1.requiresResolution()
        : PlacementRefreshProbeV1.unchanged(watch.decisionIdentityDigest,
            watch: watch);
  }

  /// Posts [context]'s batch. With no answer, [onNoAnswer] says why: a
  /// [SurfaceDeliveryReceiptReason] name, or [placementStaleReason].
  Future<PlacementBatchResponseV1?> fetchBatch(PlacementRequestContext context,
      {TargetCoordinate? expectedTarget,
      void Function(Duration retryAfter)? onRateLimited,
      void Function(String reason, [PlacementNoAnswerCause? cause])? onNoAnswer,
      void Function()? onStaleBeforeSend,
      void Function()? onDecoded}) async {
    if (!context.isCurrent()) {
      if (context.superseded()) {
        onNoAnswer?.call(placementSupersededReason);
        return null;
      }
      // Nothing left the device, so it may be gathered again from the
      // current inputs.
      onStaleBeforeSend?.call();
      onNoAnswer?.call(placementStaleReason, placementStaleCause(context));
      return null;
    }
    try {
      return await client().fetchPlacements(context.request,
          savedArtifacts: savedFrames,
          onDecoded: () {
            arrivals++;
            onDecoded?.call();
          },
          publicationGuard: context.isCurrent,
          registrationLease: context.lease,
          expectedTarget: expectedTarget,
          onRateLimited: onRateLimited,
          onNoAnswer: (reason, cause) => onNoAnswer?.call(reason.name, cause));
    } on SurfaceRequestPublicationRejected {
      _answeredStale(context, onNoAnswer);
      return null;
    } on PlacementRegistrationRetired {
      onNoAnswer?.call(
          placementStaleReason,
          const PlacementNoAnswerStale(
              PlacementStaleChange.registrationRetired));
      return null;
    }
  }

  /// Placement responses decoded so far; a mount compares it with its value
  /// when it asked, to know whether its answer is on the device.
  int arrivals = 0;

  final _pendingMounts = <bool, List<_MountWaiter>>{};

  /// Mount batches queued or in flight, each completing with the mounts it
  /// answered.
  final _mountBatches = <Completer<Set<PlacementMountRequestV1>>>{};

  /// Resolves [mount] in one request with every other mount whose resolution
  /// reaches here before the queued microtasks run out, as mounts built in
  /// one frame do. The context returned is the mount's own.
  Future<
          ({
            PlacementBatchEntryV1 entry,
            PlacementDeliveryArtifacts artifacts,
            PlacementRequestContext context
          })?>
      fetchMount(PlacementMountRequestV1 mount,
          {required bool sendAssignmentKey,
          Future<void>? keyDeadline,
          required bool Function() publicationGuard,
          void Function(PlacementBatchRefusalReasonV1 reason)? onRefused,
          void Function(String reason, [PlacementNoAnswerCause? cause])?
              onNoAnswer,
          void Function()? onStaleBeforeSend}) {
    final waiter = _MountWaiter(mount, keyDeadline, publicationGuard, onRefused,
        onNoAnswer, onStaleBeforeSend);
    // A mount of a placement the startup batch asked about waits for that
    // answer instead of sending its own request.
    final startup = _startup;
    if (startup != null &&
        (!_startupRosterKnown || _startupMounts.contains(mount))) {
      return startup.then((_) => _joinOrQueue(waiter, sendAssignmentKey));
    }
    return _joinOrQueue(waiter, sendAssignmentKey);
  }

  Future<
      ({
        PlacementBatchEntryV1 entry,
        PlacementDeliveryArtifacts artifacts,
        PlacementRequestContext context
      })?> _joinOrQueue(_MountWaiter waiter, bool sendAssignmentKey) {
    final taken = _takeStartupAnswer(waiter, sendAssignmentKey);
    if (taken != null) return Future.value(taken);
    final pending = _pendingMounts[sendAssignmentKey];
    if (pending != null) {
      pending.add(waiter);
    } else {
      final batch = [waiter];
      final answered = Completer<Set<PlacementMountRequestV1>>();
      _pendingMounts[sendAssignmentKey] = batch;
      _mountBatches.add(answered);
      scheduleMicrotask(() {
        if (identical(_pendingMounts[sendAssignmentKey], batch)) {
          _pendingMounts.remove(sendAssignmentKey);
        }
        unawaited(_fetchMounts(batch, sendAssignmentKey, answered));
      });
    }
    return waiter.result.future;
  }

  Future<void> _fetchMounts(List<_MountWaiter> waiters, bool sendAssignmentKey,
      Completer<Set<PlacementMountRequestV1>> answered) async {
    final resolved = <PlacementMountRequestV1>{};
    try {
      final live = <_MountWaiter>[];
      for (final waiter in waiters) {
        if (waiter.guard()) {
          live.add(waiter);
        } else {
          waiter.tell((w) => w.onNoAnswer?.call(placementSupersededReason));
          waiter.finish(null);
        }
      }
      if (live.isEmpty) return;
      final mounts = <PlacementMountRequestV1>[];
      for (final waiter in live) {
        if (!mounts.contains(waiter.mount)) mounts.add(waiter.mount);
      }
      final context = await capture(
          mounts: mounts,
          sendAssignmentKey: sendAssignmentKey,
          // No mount waits for its key past its own deadline.
          keyDeadline: _earliest([
            for (final waiter in live)
              if (waiter.keyDeadline case final deadline?) deadline,
          ]),
          publicationGuard: () => live.any((waiter) => waiter.guard()),
          onDeclined: (reason, [cause]) {
            for (final waiter in live) {
              waiter.tell((w) {
                // A capture never sends, so its stale decline is gathered
                // again.
                if (reason == placementStaleReason) w.onStaleBeforeSend?.call();
                w.onNoAnswer?.call(reason, cause);
              });
            }
          });
      final fetched = context == null
          ? null
          : await fetch(context, onRefused: (reason) {
              for (final waiter in live) {
                waiter.tell((w) => w.onRefused?.call(reason));
              }
            }, onNoAnswer: (reason, [cause]) {
              for (final waiter in live) {
                waiter.tell((w) => w.onNoAnswer?.call(reason, cause));
              }
            }, onStaleBeforeSend: () {
              for (final waiter in live) {
                waiter.tell((w) => w.onStaleBeforeSend?.call());
              }
            });
      for (final waiter in live) {
        if (context == null || fetched == null) {
          waiter.finish(null);
          continue;
        }
        final index = context.request.mounts.indexOf(waiter.mount);
        resolved.add(waiter.mount);
        waiter.finish((
          entry: fetched.response.decisions[index],
          artifacts: fetched.artifacts,
          context: _mountContext(context, waiter),
        ));
      }
    } on Object catch (error, stack) {
      for (final waiter in waiters) {
        if (!waiter.result.isCompleted) {
          waiter.result.completeError(error, stack);
        }
      }
    } finally {
      _mountBatches.remove(answered);
      answered.complete(resolved);
    }
  }

  static Future<void>? _earliest(List<Future<void>> deadlines) =>
      switch (deadlines) {
        [] => null,
        [final only] => only,
        _ => Future.any(deadlines),
      };

  /// [context] narrowed to [waiter]'s mount, as if it had been sent alone.
  PlacementRequestContext _mountContext(
      PlacementRequestContext context, _MountWaiter waiter) {
    final batch = context.request;
    final mount = waiter.mount;
    return PlacementRequestContext(
        request: batch.mounts.length == 1
            ? batch
            : PlacementBatchRequestV1(
                mounts: [mount],
                buildContract: batch.buildContract,
                appBuildContractHash: batch.appBuildContractHash,
                mode: batch.mode,
                localClock: batch.localClock,
                sdkInstalledLibraries: batch.sdkInstalledLibraries,
                sdkBuiltInsCanonicalBase64: batch.sdkBuiltInsCanonicalBase64,
                sdkSupportedPolicyRevisions: batch.sdkSupportedPolicyRevisions,
                assignmentKey: batch.assignmentKey,
                heldAssignments: [
                  for (final held in batch.heldAssignments)
                    if (held.key == mount.key &&
                        held.hostContractHash == mount.hostContractHash)
                      held
                ],
                registration: batch.registration,
                meteringKey: batch.meteringKey,
                analyticsAnonymousId: batch.analyticsAnonymousId),
        lease: context.lease,
        capturedAt: context.capturedAt,
        isCurrent: () => context.isCurrent() && waiter.guard(),
        capabilityChanged: context.capabilityChanged,
        changedFacts: context.changedFacts,
        superseded: () => context.superseded() || !waiter.guard());
  }

  // After the send, a gone mount stays silent as it does before the send.
  void _answeredStale(
      PlacementRequestContext context,
      void Function(String reason, [PlacementNoAnswerCause? cause])?
          onNoAnswer) {
    if (context.superseded()) {
      onNoAnswer?.call(placementSupersededReason);
    } else {
      onNoAnswer?.call(placementStaleReason, placementStaleCause(context));
    }
  }

  /// The artifact bytes this device saved, so an answer naming content it
  /// already holds does not download it again.
  Map<ArtifactIdentityV1, Uint8List> savedFrames() {
    final rows = _saved?.rowsNow;
    if (rows == null) return const {};
    final held = <ArtifactIdentityV1, Uint8List>{};
    for (final MapEntry(:key, :value) in rows.entries) {
      if (key.surfaceType != 'placementArtifact') continue;
      try {
        held[ArtifactIdentityV1.fromCanonicalBytes(
            value.stored.descriptorJson)] = value.stored.artifactBytes;
      } on Object {
        // A frame whose identity cannot be read is fetched like any other.
      }
    }
    return held;
  }

  /// Answers decoded on this device and still being checked and stored; a mount
  /// whose window ends meanwhile waits for them.
  int processing = 0;

  Future<
          ({
            PlacementBatchResolvedV1 response,
            PlacementDeliveryArtifacts artifacts
          })?>
      fetch(PlacementRequestContext context,
          {void Function(PlacementBatchRefusalReasonV1 reason)? onRefused,
          void Function(String reason, [PlacementNoAnswerCause? cause])?
              onNoAnswer,
          void Function()? onStaleBeforeSend}) async {
    var counted = false;
    try {
      final answered = await _fetchChecked(context, onDecoded: () {
        counted = true;
        processing++;
      },
          onRefused: onRefused,
          onNoAnswer: onNoAnswer,
          onStaleBeforeSend: onStaleBeforeSend);
      // What this device saves changes with every answer it keeps.
      if (answered != null) savedChanged();
      return answered;
    } finally {
      if (counted) processing--;
    }
  }

  Future<
          ({
            PlacementBatchResolvedV1 response,
            PlacementDeliveryArtifacts artifacts
          })?>
      _fetchChecked(PlacementRequestContext context,
          {void Function()? onDecoded,
          void Function(PlacementBatchRefusalReasonV1 reason)? onRefused,
          void Function(String reason, [PlacementNoAnswerCause? cause])?
              onNoAnswer,
          void Function()? onStaleBeforeSend}) async {
    final response = await fetchBatch(context,
        expectedTarget: target,
        onNoAnswer: onNoAnswer,
        onStaleBeforeSend: onStaleBeforeSend,
        onDecoded: onDecoded);
    if (response == null) return null;
    // The answer is stored with the facts its request carried. Acceptance
    // judges the facts it read against them.
    if (!context.isCurrent()) {
      _answeredStale(context, onNoAnswer);
      return null;
    }
    if (response is PlacementBatchRefusedV1) onRefused?.call(response.reason);
    if (response is! PlacementBatchResolvedV1) return null;
    await _forgetUnprovenCarriers(context, response);
    final artifacts = placementArtifactsFor(response);
    if (artifacts == null) {
      onNoAnswer?.call(PlacementBatchRefusalReasonV1.decodeFailed.name,
          const PlacementNoAnswerUndecodable());
      return null;
    }
    for (var index = 0; index < response.decisions.length; index++) {
      final entry = response.decisions[index];
      // A saved decision is removed only when the service says it no longer
      // holds: the content is unavailable. A refused request proof says
      // nothing about the device's arm.
      if (entry is PlacementBatchUseFallbackV1 &&
          entry.reason == PlacementBatchRefusalReasonV1.unavailable) {
        final mount = context.request.mounts[index];
        _accepted.remove(mount);
        await decisions.remove(decisions.decisionKey(context.request, mount,
            target: entry.descriptor.placement.target));
        savedChanged();
      }
      if (entry is! PlacementBatchAvailableV1) continue;
      // A row whose content could not be fetched is not stored.
      if (!artifacts.publications
          .containsKey(entry.publicDelivery.actualPublication)) {
        continue;
      }
      // A decision on a fact this request left out is not kept.
      if (entry.publicDelivery.cacheValidity.consultedBuiltIns
          .any(context.pendingFacts.contains)) {
        continue;
      }
      if (entry.publicDelivery.assignment != null &&
          !answeredUnderLeaseKey(context)) {
        continue;
      }
      final host = context.request.buildContract
          .contractsByHash[entry.descriptor.hostContractHash]!;
      if (!placementCacheIsValid(entry.publicDelivery.cacheValidity,
              now: now(), clock: context.request.localClock) ||
          !placementFitVerdict(
                  host: host,
                  requirement: entry.publicDelivery.fitRequirement,
                  installed: context.request.buildContract.installedCapability)
              .accepted ||
          entry.artifactClosure.any((ref) {
            final document = artifacts.documents[ref]!;
            return BlobRenderCapabilityGate.evaluate(
                required: CapabilityManifest(
                    builtInFloor: document.minClient,
                    requiredLibraries: document.requiredLibraries),
                installed: context.request.buildContract
                    .installedCapability) is BlobRenderRejected;
          })) {
        continue;
      }
      final key = decisions.decisionKey(
          context.request, context.request.mounts[index],
          target: entry.descriptor.placement.target);
      try {
        final assignment = entry.publicDelivery.assignment;
        if (assignment != null) {
          await SurfaceCanonicalCarrierProvider.retainPlacement(
              mount: context.request.mounts[index],
              lease: context.lease,
              assignment: assignment,
              proof: entry.heldProof);
        } // A declined device keeps the proof; any other answer drops it.
        if (assignment == null) {
          await SurfaceCanonicalCarrierProvider.retainDecline(
              mount: context.request.mounts[index],
              lease: context.lease,
              proof: entry.declineProof);
        }
        // The verified answer is returned now; keeping it runs behind it.
        unawaited(decisions
            .write(
                key,
                entry,
                artifacts,
                {
                  'authenticatedConfigurationFingerprint':
                      configurationFingerprint,
                  'authenticatedDeliveryDigest':
                      entry.publicDelivery.publicProjectionDigest.hex,
                  'builtIns': context.request.sdkBuiltInsCanonicalBase64,
                  'utcOffsetMinutes':
                      context.request.localClock?.utcOffsetMinutes,
                  'capturedAtMicros': context.capturedAt.microsecondsSinceEpoch,
                  'assignmentKey': context.lease.assignmentKey,
                  'registrationFingerprint':
                      context.lease.registration?.fingerprint,
                },
                context.isCurrent)
            .catchError((Object error) {
          debugPrint("[restage] This device couldn't save a placement "
              "decision (${error.runtimeType}). It's saved again on the next "
              'mount.');
        }));
      } on Object {
        // A storage failure cannot prevent this verified response from rendering.
      }
    }
    if (!context.isCurrent()) {
      _answeredStale(context, onNoAnswer);
      return null;
    }
    return (response: response, artifacts: artifacts);
  }

  Future<void> _forgetUnprovenCarriers(PlacementRequestContext context,
      PlacementBatchResolvedV1 response) async {
    final key = answeredUnderLeaseKey(context)
        ? context.lease.assignmentKey
        : context.request.assignmentKey;
    if (key == null) return;
    for (var index = 0; index < response.decisions.length; index++) {
      final entry = response.decisions[index];
      if (entry is PlacementBatchUseFallbackV1 &&
          entry.reason == PlacementBatchRefusalReasonV1.assignmentUnavailable) {
        final mount = context.request.mounts[index];
        await SurfaceCanonicalCarrierProvider.forgetPlacement(
            mount: mount, assignmentKey: key);
        // The withdrawn decision is neither painted again nor read back.
        _accepted.remove(mount);
        await decisions.remove(decisions.decisionKey(context.request, mount,
            target: entry.descriptor.placement.target));
        savedChanged();
      }
    }
  }

  Future<
          ({
            PlacementBatchAvailableV1 decision,
            PlacementDeliveryArtifacts artifacts,
            PlacementRequestContext context
          })?>
      local(PlacementRequestContext context,
          {void Function()? onPendingFacts}) async {
    final expectedTarget = target;
    if (!context.isCurrent()) return null;
    SurfaceAssignmentResolutionLease? storedLease;
    final stored = await decisions.read(
        request: context.request,
        expectedTarget: expectedTarget,
        configurationFingerprint: configurationFingerprint,
        acceptsStored: (stored, decision) async {
          // A decision on facts this request has not read waits for them.
          if (decision.publicDelivery.cacheValidity.consultedBuiltIns
              .any(context.pendingFacts.contains)) {
            onPendingFacts?.call();
            return false;
          }
          final sidecar = stored.sidecar;
          if (!_sameConsultedFacts(sidecar, decision, context.request) ||
              sidecar['capturedAtMicros'] is! int ||
              (sidecar['capturedAtMicros']! as int) >
                  now().toUtc().microsecondsSinceEpoch) {
            return false;
          }
          final mount = context.request.mounts.single;
          final identity = await storedDeliveryIdentity(
              stored: stored,
              assignment: null,
              placement: mount,
              placementAssignment: decision.publicDelivery.assignment,
              surface: mount.defaultSurface?.surfaceType.value ?? 'paywall',
              slug: mount.defaultSurface?.slug ?? mount.key.slug);
          storedLease = identity.lease;
          return identity.reusable;
        });
    if (stored == null || !context.isCurrent() || storedLease == null) {
      return null;
    }
    final localContext = PlacementRequestContext(
        request: context.request,
        lease: storedLease!,
        capturedAt: context.capturedAt,
        isCurrent: () => context.isCurrent() && storedLease!.isCurrent,
        changedFacts: context.changedFacts,
        pendingFacts: context.pendingFacts);
    final response = stored.response;
    final artifacts = await assemblePlacementDeliveryArtifacts(response,
        heldArtifactBytes: stored.frames,
        publicationGuard: localContext.isCurrent,
        fresh: false);
    if (artifacts == null ||
        artifacts.publications.isEmpty ||
        !localContext.isCurrent()) {
      return null;
    }
    _storedTarget ??= response.decisions.single.descriptor.placement.target;
    return (
      decision: response.decisions.single as PlacementBatchAvailableV1,
      artifacts: artifacts,
      context: localContext
    );
  }
}

/// Why a placement request brought no answer when its inputs changed in
/// flight.
@internal
const String placementStaleReason = 'stale';

/// The mount or configuration a placement request was for is gone; nothing
/// reports it.
@internal
const String placementSupersededReason = 'superseded';

/// One mount waiting for the batch it joined.
final class _MountWaiter {
  _MountWaiter(this.mount, this.keyDeadline, this.guard, this.onRefused,
      this.onNoAnswer, this.onStaleBeforeSend);
  final PlacementMountRequestV1 mount;
  final Future<void>? keyDeadline;
  final bool Function() guard;
  final void Function(PlacementBatchRefusalReasonV1 reason)? onRefused;
  final void Function(String reason, [PlacementNoAnswerCause? cause])?
      onNoAnswer;
  final void Function()? onStaleBeforeSend;
  final result = Completer<
      ({
        PlacementBatchEntryV1 entry,
        PlacementDeliveryArtifacts artifacts,
        PlacementRequestContext context
      })?>();
  (Object, StackTrace)? _failure;

  /// Runs one of this mount's callbacks; a throw fails only this mount.
  void tell(void Function(_MountWaiter waiter) callback) {
    if (_failure != null) return;
    try {
      callback(this);
    } on Object catch (error, stack) {
      _failure = (error, stack);
    }
  }

  void finish(
      ({
        PlacementBatchEntryV1 entry,
        PlacementDeliveryArtifacts artifacts,
        PlacementRequestContext context
      })? value) {
    if (result.isCompleted) return;
    if (_failure case (final error, final stack)) {
      result.completeError(error, stack);
    } else {
      result.complete(value);
    }
  }
}

/// A decision a mount accepted, with the content and request it was
/// accepted under.
@internal
typedef PlacementAccepted = ({
  PlacementBatchAvailableV1 decision,
  PlacementDeliveryArtifacts artifacts,
  PlacementRequestContext context,
});

@internal
final class PlacementRequestContext {
  PlacementRequestContext(
      {required this.request,
      required this.lease,
      required this.capturedAt,
      required this.isCurrent,
      bool Function()? capabilityChanged,
      List<String> Function(List<String> consulted)? changedFacts,
      this.pendingFacts = const {},
      bool Function()? superseded})
      : capabilityChanged = capabilityChanged ?? _unchanged,
        changedFacts = changedFacts ?? _unconsulted,
        superseded = superseded ?? _unchanged;
  final PlacementBatchRequestV1 request;
  final SurfaceAssignmentResolutionLease lease;
  final DateTime capturedAt;

  /// Built-in facts the request left out because they were not read yet.
  final Set<String> pendingFacts;

  /// Whether the request's configuration, identity, consent and installed
  /// widgets still hold; device facts are judged per decision.
  final bool Function() isCurrent;

  /// Whether the installed widgets changed since the request was gathered.
  final bool Function() capabilityChanged;

  /// Which of the [consulted] built-in facts changed since the facts an
  /// answer is judged by.
  final List<String> Function(List<String> consulted) changedFacts;

  /// Whether the mount or configuration the request was for is gone.
  final bool Function() superseded;

  static bool _unchanged() => false;

  static List<String> _unconsulted(List<String> consulted) => const [];
}

/// The built-in facts a request's canonical carrier names, by wire name;
/// null when the carrier cannot be read.
@internal
Map<Object?, Object?>? placementBuiltInFacts(String? builtIns) {
  if (builtIns == null) return const {};
  try {
    final decoded = CanonicalJsonCodec.decode(
        base64Url.decode(base64Url.normalize(builtIns)));
    return decoded is Map ? decoded : null;
  } on Object {
    return null;
  }
}

// A stored decision serves only the consulted facts it was decided on, and
// the time zone its local window was set in.
bool _sameConsultedFacts(Map<String, Object?> sidecar,
    PlacementBatchAvailableV1 decision, PlacementBatchRequestV1 request) {
  final validity = decision.publicDelivery.cacheValidity;
  final stored = sidecar['builtIns'];
  if (stored != null && stored is! String) return false;
  final then = placementBuiltInFacts(stored as String?);
  final now = placementBuiltInFacts(request.sdkBuiltInsCanonicalBase64);
  // An unreadable carrier matches nothing.
  if (then == null || now == null) return false;
  if (validity.consultedBuiltIns.any((name) => then[name] != now[name])) {
    return false;
  }
  return (validity.notBeforeLocal == null &&
          validity.expiresBeforeLocal == null) ||
      sidecar['utcOffsetMinutes'] == request.localClock?.utcOffsetMinutes;
}

/// What made [context] stale.
@internal
PlacementNoAnswerStale placementStaleCause(PlacementRequestContext context) =>
    PlacementNoAnswerStale(context.capabilityChanged()
        ? PlacementStaleChange.installedWidgets
        : PlacementStaleChange.configuration);

/// Whether [context]'s answer was served under the key its lease now holds: the
/// key the request carried, or the handle a registering request just had
/// confirmed. An assignment answered under either is kept and shown.
@internal
bool answeredUnderLeaseKey(PlacementRequestContext context) {
  final lease = context.lease;
  final key = lease.assignmentKey;
  if (!lease.assignmentsAllowed || key == null) return false;
  final sent = context.request.assignmentKey;
  return sent == key ||
      (sent == null &&
          context.request.registration != null &&
          lease.sentAssignmentKey == null);
}
