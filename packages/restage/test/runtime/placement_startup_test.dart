import 'dart:async';
import 'dart:convert';
import 'dart:io' show FileSystemException;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/mounted_surface_report.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage/src/delivery/placement_decision_store.dart';
import 'package:restage/src/delivery/surface_delivery_receipt.dart';
import 'package:restage/src/delivery/surface_delivery_receipt_batch.dart';
import 'package:restage/src/metering/metering_token_store.dart';
import 'package:restage/src/resolver/placement_fallback_log.dart'
    show resetPlacementFallbackLog;
import 'package:restage/src/resolver/placement_mount_resolver.dart';
import 'package:restage/src/runtime/first_launch_store.dart';
import 'package:restage/src/resolver/surface_assignment_credential_store.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/early/early_request.dart';
import 'package:restage/src/resolver/surface_canonical_carrier_provider.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';
import 'package:restage/src/resolver/surface_metering_key_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/refresh/surface_refresh_registry.dart';
import 'package:restage/src/runtime/placement_discovery.dart';
import 'package:restage/src/runtime/installed_widget_vocabulary.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/rfw.dart' show RemoteWidget;
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../flow/flow_test_support.dart' as flows;
import '../fixtures/compiled_surfaces/native_flow.dart' as native;
import '../support/placement_delivery_fixture.dart';
import '../surface_screen/surface_screen_test_support.dart';
import '../support/sent_placement_request.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1',
        buildNumber: '42',
        buildSignature: '');
    Restage.debugReset();
    debugResetAppBuildOrdinal();
    debugResetOsVersion();
    sharedSurfaceArtifactStore = MemorySurfaceArtifactStore();
  });
  tearDown(() {
    Restage.debugReset();
    sharedSurfaceArtifactStore = null;
  });

  for (final surfaceExperiment in [false, true]) {
    testWidgets(
        'painted placement exposes its nearest experiment ($surfaceExperiment)',
        (tester) async {
      final placementSelection = PublicExperimentSelectionV1(
        experimentId: ExperimentPublicIdV1('experiment.placement'),
        experimentRevisionId:
            ExperimentPublicRevisionIdV1('revision.placement'),
        experimentEpochId: ExperimentPublicEpochIdV1('epoch.placement'),
        armId: ExperimentPublicArmIdV1('arm.placement'),
      );
      final surfaceSelection = PublicExperimentSelectionV1(
        experimentId: ExperimentPublicIdV1('experiment.surface'),
        experimentRevisionId: ExperimentPublicRevisionIdV1('revision.surface'),
        experimentEpochId: ExperimentPublicEpochIdV1('epoch.surface'),
        armId: ExperimentPublicArmIdV1('arm.surface'),
      );
      final requests = <PlacementBatchRequestV1>[];
      _configure(requests,
          respond: (request) => placementFixtureResponse(
                request,
                placementExperiment: placementSelection,
                surfaceExperiment: surfaceExperiment ? surfaceSelection : null,
              ));
      final host = readPlacementDeliveryFixture()
          .request
          .buildContract
          .contractsByHash
          .values
          .first;
      final definition = _paywallDefinition('original', host);
      final events = <RestageEvent>[];
      expect(Restage.assignmentFor('original', surfaceType: Surface.paywall),
          isNull);
      await tester.pumpWidget(MaterialApp(
          home: RestagePaywall(
        id: 'original',
        placementBinding: PlacementMountBinding(
            definition: () => definition, name: 'home_card'),
        onEvent: events.add,
        fallbackBuilder: (_) => const Text('Original'),
      )));
      await _finish(tester);
      expect(find.text('Welcome'), findsOneWidget);
      final expected =
          surfaceExperiment ? surfaceSelection : placementSelection;
      final assignment =
          Restage.assignmentFor('original', surfaceType: Surface.paywall)!;
      expect(assignment.experimentId, expected.experimentId.value);
      expect(
          assignment.experimentRevisionId, expected.experimentRevisionId.value);
      expect(assignment.experimentEpochId, expected.experimentEpochId.value);
      expect(assignment.variantId, expected.armId.value);
      final viewed = events.whereType<PaywallViewed>().single;
      expect(viewed.assignment, assignment);
      expect(
          viewed.analyticsProperties['restage_variant'], expected.armId.value);
      await tester.pumpWidget(const SizedBox());
      expect(Restage.assignmentFor('original', surfaceType: Surface.paywall),
          assignment);
      Restage.reset();
      expect(Restage.assignmentFor('original', surfaceType: Surface.paywall),
          isNull);
    });
  }

  testWidgets('the first mount in a fresh process is delivered',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final reports = <SurfaceResolutionReport>[];
    _configure(requests,
        installDateAfter: const Duration(milliseconds: 5),
        gatherAfter: const Duration(milliseconds: 10),
        onSurfaceResolution: reports.add);
    final lines = <String>[];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
    addTearDown(() => debugPrint = print);
    final host = readPlacementDeliveryFixture()
        .request
        .buildContract
        .contractsByHash
        .values
        .first;
    final definition = _paywallDefinition('original', host);
    await tester.pumpWidget(MaterialApp(
        home: RestagePaywall(
      id: 'original',
      placementBinding: PlacementMountBinding(
          definition: () => definition, name: 'home_card'),
      fallbackBuilder: (_) => const Text('Original'),
    )));
    await _finish(tester);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    // The gather waits briefly for the install date in flight.
    expect(requests, hasLength(1));
    expect(_builtInsOf(requests.single)['daysSinceInstall'], 0);
    expect(find.text('Welcome'), findsOneWidget);
    expect(reports.map((report) => report.reason), isNot(contains('stale')));
    expect(lines.where((line) => line.contains('(stale)')), isEmpty);
    debugPrint = print;
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a delivered placement mount reports delivered content',
      (tester) async {
    _configure(<PlacementBatchRequestV1>[]);
    final events = <RestageEvent>[];
    final subscription = Restage.events.listen(events.add);
    addTearDown(subscription.cancel);
    final host = readPlacementDeliveryFixture()
        .request
        .buildContract
        .contractsByHash
        .values
        .first;
    final definition = _paywallDefinition('original', host);
    await tester.pumpWidget(MaterialApp(
        home: RestagePaywall(
      id: 'original',
      placementBinding: PlacementMountBinding(
          definition: () => definition, name: 'home_card'),
      fallbackBuilder: (_) => const Text('Original'),
    )));
    await _finish(tester);
    expect(find.text('Welcome'), findsOneWidget);
    final completed = events.whereType<SurfaceLoadCompleted>().single;
    expect(events.whereType<SurfaceLoadStarted>(), hasLength(1));
    expect(completed.source, SurfaceLoadSource.delivered);
    expect(completed.firstLaunchWaitPassed, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  for (final after in [false, true]) {
    testWidgets(
        'the first request names every declared placement '
        '(declared ${after ? 'after' : 'before'} configure)', (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      final host = readPlacementDeliveryFixture()
          .request
          .buildContract
          .contractsByHash
          .values
          .first;
      final declared = [
        _paywallDefinition('original', host),
        _paywallDefinition('later', host),
      ];
      if (!after) Restage.declareSurfaces(declared);
      _configure(requests);
      if (after) Restage.declareSurfaces(declared);
      await tester.pumpWidget(MaterialApp(
          home: RestagePaywall(
        id: 'original',
        placementBinding: PlacementMountBinding(
            definition: () => declared.first, name: 'home_card'),
        fallbackBuilder: (_) => const Text('Original'),
      )));
      await _finish(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(
          requests.first.buildContract.mounts,
          containsAll([
            for (final definition in declared)
              PlacementMountRequestV1(
                  key: definition.key,
                  hostContractHash: definition.hostContract.contentHash,
                  defaultSurface: definition.defaultSurfaceLocator),
          ]));
      await tester.pumpWidget(const SizedBox());
    });
  }

  Future<List<String>> mountPaywall(WidgetTester tester,
      {bool dispose = false,
      Completer<void>? release,
      Duration settle = Duration.zero}) async {
    final host = readPlacementDeliveryFixture()
        .request
        .buildContract
        .contractsByHash
        .values
        .first;
    final definition = _paywallDefinition('original', host);
    final lines = <String>[];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
    try {
      await tester.pumpWidget(MaterialApp(
          home: RestagePaywall(
        id: 'original',
        placementBinding: PlacementMountBinding(
            definition: () => definition, name: 'home_card'),
        fallbackBuilder: (_) => const Text('Original'),
      )));
      await _finish(tester);
      if (dispose) await tester.pumpWidget(const SizedBox());
      release?.complete();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(settle);
      await _finish(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
    } finally {
      debugPrint = print;
    }
    return lines;
  }

  group('a relaunch', () {
    final host = readPlacementDeliveryFixture()
        .request
        .buildContract
        .contractsByHash
        .values
        .first;
    final definition = _paywallDefinition('original', host);
    const slowMount = Duration(milliseconds: 650);

    // A new process over the same storage: nothing held in memory, and a
    // mount's own answer arrives after the render deadline.
    String? declineProof;
    setUp(() => declineProof = null);

    void launch(List<PlacementBatchRequestV1> requests,
        {DateTime? day,
        Duration? installDateAfter,
        Duration? gatherAfter,
        List<String> consulted = const [],
        List<RestageSurfaceRef> surfaces = const [],
        bool keyed = false,
        Duration mountDelay = slowMount,
        Duration prefetchDelay = Duration.zero,
        void Function(PlacementBatchRequestV1 sent)? onSend,
        bool analytics = false,
        int build = 42}) {
      PackageInfo.setMockInitialValues(
          appName: 'test',
          packageName: 'test',
          version: '1',
          buildNumber: '$build',
          buildSignature: '');
      debugResetAppBuildOrdinal();
      debugResetOsVersion();
      // A new process has logged nothing yet.
      resetPlacementFallbackLog();
      // The startup prefetch reads the clock configure was given.
      Restage.debugPlacementNow = () => DateTime.utc(2026, 10, 4, 12);
      _configure(requests,
          surfaces: surfaces,
          analytics: analytics,
          freshWindow: Duration.zero,
          installDateAfter: installDateAfter,
          gatherAfter: gatherAfter, delayEach: () {
        onSend?.call(requests.last);
        return Future<void>.delayed(
            requests.last.mode == PlacementBatchModeV1.mount
                ? mountDelay
                : prefetchDelay);
      }, respond: (request) {
        var answer = placementFixtureResponse(request,
            cacheValidityOverrides: {'consultedBuiltIns': consulted});
        if (declineProof case final proof?) {
          answer = PlacementBatchResolvedV1.fromBuiltRows(
              request: request,
              expectedTarget: readPlacementDeliveryFixture().target,
              decisions: [
                for (final d in answer.decisions)
                  d is PlacementBatchAvailableV1
                      ? PlacementBatchAvailableV1(
                          d.descriptor, d.publicDelivery, d.artifactClosure,
                          watch: d.watch, declineProof: proof)
                      : d
              ]);
        }
        if (request.registration == null) return answer;
        // The service confirms the registration the mount folded in.
        final now = DateTime.now().microsecondsSinceEpoch;
        return PlacementBatchResolvedV1(
            request: request,
            expectedTarget: readPlacementDeliveryFixture().target,
            decisions: answer.decisions,
            registration: SurfaceRegistrationMetadataV1(
                credentialHandle: 'ic1.${'b' * 64}',
                expiresAtMicros: now + Duration.microsecondsPerDay,
                serverNowMicros: now));
      });
      if (keyed) {
        // As configure installs it with measurement on: a credential store
        // over this device's storage.
        final store = SurfaceAssignmentCredentialStore(
          namespace: 'relaunch',
          actor: () async => 'device',
          identityGeneration: () => 0,
          onRetentionRollover:
              SurfaceCanonicalCarrierProvider.clearHeldAssignments,
        );
        SurfaceAssignmentKeyProvider.install(
          key: store.resolve,
          localKey: store.resolveLocal,
          identityGeneration: () => store.generation,
          registration: store.capture,
          confirmedKey: () => store.currentHandle,
          confirmRegistration: (attempt, start, handle, expiry, serverNow) =>
              store.confirm(
            attempt: attempt,
            localRequestStartMicros: start,
            credentialHandle: handle,
            expiresAtMicros: expiry,
            serverNowMicros: serverNow,
          ),
          refuseRegistration: store.refuse,
        );
      }
      if (day != null) {
        debugResetInstallObservations(nowUtc: () => day);
        configureSurfaceDeliveryObservations();
      }
    }

    Widget mount({String? name}) => MaterialApp(
            home: RestagePaywall(
          id: 'original',
          placementBinding:
              PlacementMountBinding(definition: () => definition, name: name),
          fallbackBuilder: (_) => const Text('Original'),
        ));

    // What a mount shows at the render deadline.
    Future<String> atDeadline(WidgetTester tester, {String? name}) async {
      await tester.pumpWidget(mount(name: name));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      final shown = find.text('Welcome').evaluate().isNotEmpty
          ? 'Welcome'
          : find.text('Original').evaluate().isNotEmpty
              ? 'Original'
              : 'nothing';
      await tester.pump(slowMount);
      await _finish(tester);
      await tester.pumpWidget(const SizedBox());
      return shown;
    }

    testWidgets(
        'the platform keeps the next launch request current after every launch',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      final remembered = <PlacementBatchRequestV1>[];
      EarlyRequest.recorder =
          (url, apiKey, request) async => remembered.add(request);
      addTearDown(() => EarlyRequest.recorder = null);
      Restage.declareSurfaces([definition]);
      launch(requests, keyed: true, surfaces: [definition]);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      expect(remembered, isNotEmpty);
      // The saved decisions go away, as when the surfaces they painted are done.
      for (final key in await sharedSurfaceArtifactStore.keys()) {
        if (key.surfaceType == 'placementDecision' ||
            key.surfaceType == 'placementArtifact') {
          await sharedSurfaceArtifactStore.remove(key);
        }
      }
      final before = remembered.length;
      Restage.declareSurfaces([definition]);
      launch(requests, keyed: true, surfaces: [definition]);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      // The relaunch asked for the closure, its answer was accepted, and the
      // copy for the launch after it already says nothing is needed.
      final relaunch = requests.where((r) => r.assignmentKey != null).first;
      expect(relaunch.inlineMounts, isNotEmpty);
      expect(remembered.length, greaterThan(before));
      expect(remembered.last.inlineMounts, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    for (final analytics in [true, false]) {
      final state = analytics ? 'on' : 'off';
      testWidgets(
          'with analytics $state, the second launch adopts the request the '
          'platform sent from the first', (tester) async {
        final requests = <PlacementBatchRequestV1>[];
        final remembered = <PlacementBatchRequestV1>[];
        EarlyRequest.recorder =
            (url, apiKey, request) async => remembered.add(request);
        addTearDown(() => EarlyRequest.recorder = null);
        Future<void> run() async {
          Restage.declareSurfaces([definition]);
          launch(requests,
              keyed: analytics, analytics: analytics, surfaces: [definition]);
          await tester.pumpWidget(const MaterialApp(home: SizedBox()));
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 150)));
          await tester.pump(const Duration(seconds: 1));
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 150)));
        }

        await run();
        expect(remembered, isNotEmpty);
        final next = remembered.last;
        expect(next.analyticsAnonymousId != null, analytics);
        // With analytics on, the kept request carries the confirmed handle.
        expect(next.assignmentKey != null, analytics);
        expect(next.registration, isNull);
        final before = requests.length;
        // A new process: the platform sent the kept request at its start.
        EarlyRequest.debugForget();
        var adopted = false;
        EarlyRequest.debugSent =
            (mine) => next.withBuildContract(carried: false).canonicalBytes;
        EarlyRequest.debugInFlight = ({int timeoutMs = 20000}) async {
          adopted = true;
          return (
            sent: next.withBuildContract(carried: false).canonicalBytes,
            response: EarlyResponse(
                status: 200,
                body: Uint8List.fromList(
                    placementFixtureResponse(next).canonicalBytes),
                headers: const {}),
          );
        };
        addTearDown(() {
          EarlyRequest.debugSent = null;
          EarlyRequest.debugInFlight = null;
        });
        await run();
        expect(adopted, isTrue);
        expect(requests.skip(before).where((r) => r.startup), isEmpty);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets(
        'an answer adopted for a smaller claimed capability is read at the '
        'next launch without a refetch', (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      Restage.declareSurfaces([definition]);
      launch(requests, surfaces: [definition]);
      // As an app that installs more icons than its build claims: the
      // platform's request names a capability the runtime covers.
      PlacementBatchRequestV1? sent;
      String? claimedHash;
      String? runtimeHash;
      EarlyRequest.debugSent = (mine) {
        final build = mine.buildContract;
        final installed = build.installedCapability;
        final vocabulary = installed.vocabulary!;
        final claimed = InstalledCapability(
          builtInCatalogVersion: installed.builtInCatalogVersion,
          installedLibraries: installed.installedLibraries,
          vocabulary: WidgetVocabulary(
            widgetNames: vocabulary.widgetNames
                .difference({vocabulary.widgetNames.last}),
            iconCodePoints: vocabulary.iconCodePoints,
          ),
        );
        final smaller = PlacementBuildContractV1(
            platform: build.platform,
            buildOrdinal: build.buildOrdinal,
            mounts: build.mounts.toList(),
            contractsByHash: build.contractsByHash,
            installedCapability: claimed,
            installedCapabilityHash: claimed.contentHash);
        EarlyRequest.debugTemplate = () async => jsonEncode({
              'url': 'https://example.com/sdk/v1/placements/resolve',
              'authorization': 'Bearer rs_pk_test',
              'contract': utf8.decode(smaller.canonicalBytes),
            });
        claimedHash = claimed.contentHash;
        runtimeHash = installed.contentHash;
        sent = PlacementBatchRequestV1.fromJson(
          {
            ...mine.withBuildContract(carried: false).toJson(),
            'appBuildContractHash': smaller.appBuildContractHash,
          },
          verifiedBuildContract: (_) => smaller,
        );
        return sent!.withBuildContract(carried: false).canonicalBytes;
      };
      EarlyRequest.debugInFlight = ({int timeoutMs = 20000}) async => (
            sent: sent!.withBuildContract(carried: false).canonicalBytes,
            response: EarlyResponse(
                status: 200,
                body: Uint8List.fromList(
                    placementFixtureResponse(sent!).canonicalBytes),
                headers: const {}),
          );
      addTearDown(() {
        EarlyRequest.debugSent = null;
        EarlyRequest.debugInFlight = null;
        EarlyRequest.debugTemplate = null;
      });
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      expect(sent, isNotNull);
      expect(claimedHash, isNot(runtimeHash));
      expect(requests.where((r) => r.startup), isEmpty);
      // The next launch, with no platform request: the saved decision paints
      // before the mount's own answer.
      EarlyRequest.debugSent = null;
      EarlyRequest.debugInFlight = null;
      EarlyRequest.debugTemplate = null;
      EarlyRequest.debugForget();
      launch(requests, surfaces: [definition], prefetchDelay: slowMount);
      expect(await atDeadline(tester), 'Welcome');
      await tester.pump(slowMount);
      await _finish(tester);
    });

    testWidgets(
        'inline bytes the platform asked for are judged by its request, not '
        "Dart's", (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      final remembered = <PlacementBatchRequestV1>[];
      EarlyRequest.recorder =
          (url, apiKey, request) async => remembered.add(request);
      addTearDown(() => EarlyRequest.recorder = null);
      Future<void> run() async {
        Restage.declareSurfaces([definition]);
        launch(requests, keyed: true, surfaces: [definition]);
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 150)));
        await tester.pump(const Duration(seconds: 1));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 150)));
      }

      await run();
      final next = remembered.last;
      // Dart holds the artifact; the platform sent from a template that
      // asks for it inline, as the bundled one does.
      expect(next.inlineMounts, isEmpty);
      final sent = PlacementBatchRequestV1.fromJson({
        ...next.toJson(),
        'inlineMounts': [0],
      });
      final artifact = readPlacementDeliveryFixture().artifacts.single;
      final answer = PlacementBatchResolvedV1.fromBuiltRows(
          request: sent,
          expectedTarget: readPlacementDeliveryFixture().target,
          decisions: placementFixtureResponse(sent).decisions,
          inlineArtifacts: {artifact.identity: artifact.bytes});
      final before = requests.length;
      final printed = <String>[];
      final print = debugPrint;
      debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
      EarlyRequest.debugForget();
      PlacementBatchRequestV1? mine;
      var adopted = false;
      EarlyRequest.debugSent = (request) {
        mine = request;
        return sent.withBuildContract(carried: false).canonicalBytes;
      };
      EarlyRequest.debugInFlight = ({int timeoutMs = 20000}) async {
        adopted = true;
        return (
          sent: sent.withBuildContract(carried: false).canonicalBytes,
          response: EarlyResponse(
              status: 200,
              body: Uint8List.fromList(answer.canonicalBytes),
              headers: const {}),
        );
      };
      try {
        await run();
      } finally {
        debugPrint = print;
        EarlyRequest.debugSent = null;
        EarlyRequest.debugInFlight = null;
      }
      expect(mine?.inlineMounts, isEmpty);
      expect(adopted, isTrue);
      expect(printed.where((line) => line.contains('malformed')), isEmpty);
      expect(requests.skip(before).where((r) => r.startup), isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'a reset reaches the platform and renews the next launch request',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      final remembered = <PlacementBatchRequestV1>[];
      final identities = <(String, String)>[];
      EarlyRequest.recorder =
          (url, apiKey, request) async => remembered.add(request);
      EarlyRequest.identitySetter = (metering, anonymous) async {
        identities.add((metering, anonymous));
        return true;
      };
      addTearDown(() {
        EarlyRequest.recorder = null;
        EarlyRequest.identitySetter = null;
      });
      Restage.declareSurfaces([definition]);
      launch(requests, keyed: true, analytics: true, surfaces: [definition]);
      SurfaceMeteringKeyProvider.install(store: MeteringTokenStore());
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      final before = remembered.length;
      final oldId = remembered.last.analyticsAnonymousId;
      expect(oldId, isNotNull);
      expect(identities, isEmpty);

      Restage.reset();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)));

      // The platform got the new ids, and its copy of the next launch's
      // request carries them and registers again.
      expect(identities, hasLength(1));
      expect(identities.single.$2, isNot(oldId));
      expect(remembered.length, greaterThan(before));
      expect(remembered.last.analyticsAnonymousId, identities.single.$2);
      expect(remembered.last.meteringKey, identities.single.$1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'a platform that refuses the new identity keeps its copy of the request',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      final remembered = <PlacementBatchRequestV1>[];
      final identities = <(String, String)>[];
      EarlyRequest.recorder =
          (url, apiKey, request) async => remembered.add(request);
      EarlyRequest.identitySetter = (metering, anonymous) async {
        identities.add((metering, anonymous));
        return false;
      };
      addTearDown(() {
        EarlyRequest.recorder = null;
        EarlyRequest.identitySetter = null;
      });
      Restage.declareSurfaces([definition]);
      launch(requests, keyed: true, analytics: true, surfaces: [definition]);
      SurfaceMeteringKeyProvider.install(store: MeteringTokenStore());
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      final before = remembered.length;
      final oldId = remembered.last.analyticsAnonymousId;
      expect(oldId, isNotNull);
      expect(identities, isEmpty);

      Restage.reset();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)));

      expect(identities, hasLength(1));
      expect(remembered.length, before);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'backgrounding during the startup batch sends no second request',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      Restage.declareSurfaces([definition]);
      launch(requests,
          surfaces: [definition],
          prefetchDelay: const Duration(milliseconds: 200));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)));
      expect(requests.where((r) => r.mode == PlacementBatchModeV1.prefetch),
          hasLength(1));
      await tester.pump(slowMount);
      await _finish(tester);
      await tester.pumpWidget(const SizedBox());
    });

    Future<void> startup(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
    }

    testWidgets(
        'a painted mount is kept across a kill and reported once the service '
        'answers', (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      MountedSurfaceReport.instance =
          MountedSurfaceReport(mirror: (_, __) async {});
      addTearDown(() => MountedSurfaceReport.instance = MountedSurfaceReport());
      _configure(requests);
      await tester.pumpWidget(MaterialApp(
          home: RestagePaywall(
        id: 'original',
        placementBinding: PlacementMountBinding(
            definition: () => definition, name: 'home_card'),
        fallbackBuilder: (_) => const Text('Original'),
      )));
      await _finish(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(find.text('Welcome'), findsOneWidget);
      // Nothing was mounted before this process, so its requests report none.
      expect(requests.map((r) => r.mountedSince), everyElement(isEmpty));
      final held = (await tester
          .runAsync(() => MountedSurfaceReport.instance.pending()))!;
      // The surface the answer delivered, not the declared default.
      expect(held, hasLength(1));
      expect(held.single.placement, PlacementKeyV1.named(slug: 'home_card'));
      expect(held.single.surfaceType.value, 'general');
      // The default is 'original'; the answer delivered 'welcome', and that is
      // what the report names, for a placement keyed by name alone.
      expect(held.single.slug, 'welcome');
      await tester.pumpWidget(const SizedBox());

      // The app is killed; a new process reads the report from storage.
      MountedSurfaceReport.instance =
          MountedSurfaceReport(mirror: (_, __) async {});
      final launches = requests.length;
      Restage.declareSurfaces([definition]);
      launch(requests, surfaces: [definition]);
      await startup(tester);
      final next = requests
          .skip(launches)
          .firstWhere((r) => r.mode == PlacementBatchModeV1.prefetch);
      expect(next.mountedSince, held);
      // The service answered it, so the next process reports nothing.
      expect(
          await tester.runAsync(() => MountedSurfaceReport.instance.pending()),
          isEmpty);
      await _finish(tester);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'a mount that painted only the compiled fallback reports nothing',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      MountedSurfaceReport.instance =
          MountedSurfaceReport(mirror: (_, __) async {});
      addTearDown(() => MountedSurfaceReport.instance = MountedSurfaceReport());
      Restage.declareSurfaces([definition]);
      // The service answers after the first-launch wait, so the compiled
      // widget is what paints.
      launch(requests, surfaces: [definition]);
      await tester.pumpWidget(MaterialApp(
          home: RestagePaywall(
        id: 'original',
        placementBinding: PlacementMountBinding(
            definition: () => definition, name: 'home_card'),
        fallbackBuilder: (_) => const Text('Original'),
      )));
      await tester.pump(slowMount);
      await _finish(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(find.text('Original'), findsOneWidget);
      expect(
          await tester.runAsync(() => MountedSurfaceReport.instance.pending()),
          isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a declined device presents its proof on the next launch only',
        (tester) async {
      const proof = 'dp1.cGF5bG9hZA.bWFj';
      final requests = <PlacementBatchRequestV1>[];
      Restage.declareSurfaces([definition]);
      declineProof = proof;
      launch(requests, keyed: true, surfaces: [definition]);
      SurfaceCanonicalCarrierProvider.enableAssignmentRetention('test_scope');
      await startup(tester);
      // The registering launch holds nothing to present.
      expect(requests.first.registration, isNotNull);
      expect(requests.first.heldDeclines, isEmpty);

      final launches = requests.length;
      Restage.declareSurfaces([definition]);
      launch(requests, keyed: true, surfaces: [definition]);
      SurfaceCanonicalCarrierProvider.enableAssignmentRetention('test_scope');
      await startup(tester);
      final second = requests
          .skip(launches)
          .firstWhere((r) => r.mode == PlacementBatchModeV1.prefetch);
      expect(second.assignmentKey, isNotNull);
      expect(second.registration, isNull);
      expect(second.heldDeclines.map((d) => d.proof), everyElement(proof));
      expect(second.heldDeclines, isNotEmpty);

      // An answer without a proof drops it.
      declineProof = null;
      final before = requests.length;
      Restage.declareSurfaces([definition]);
      launch(requests, keyed: true, surfaces: [definition]);
      SurfaceCanonicalCarrierProvider.enableAssignmentRetention('test_scope');
      await startup(tester);
      expect(requests.skip(before).first.heldDeclines, isNotEmpty);
      final after = requests.length;
      Restage.declareSurfaces([definition]);
      launch(requests, keyed: true, surfaces: [definition]);
      SurfaceCanonicalCarrierProvider.enableAssignmentRetention('test_scope');
      await startup(tester);
      expect(requests.skip(after).first.heldDeclines, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('only the startup batch carries the startup mark',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      Restage.declareSurfaces([definition]);
      launch(requests, keyed: true, surfaces: [definition]);
      await startup(tester);
      final first =
          requests.where((r) => r.mode == PlacementBatchModeV1.prefetch);
      expect(first, hasLength(1));
      expect(first.single.startup, isTrue);

      // A refresh of what the device holds is a prefetch of its own.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)));
      final prefetches =
          requests.where((r) => r.mode == PlacementBatchModeV1.prefetch);
      expect(prefetches, hasLength(2));
      expect(prefetches.last.startup, isFalse);
      // Mounts never carry it.
      expect(
          requests
              .where((r) => r.mode != PlacementBatchModeV1.prefetch)
              .any((r) => r.startup),
          isFalse);
      await tester.pump(slowMount);
      await _finish(tester);
      await tester.pumpWidget(const SizedBox());
    });

    Future<void> accept(WidgetTester tester,
        {String shown = 'Original'}) async {
      await tester.pumpWidget(mount(name: 'home_card'));
      await tester.pump(slowMount);
      await _finish(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      // The answer came after the deadline and is kept for the next mount.
      expect(find.text(shown), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }

    testWidgets('paints the stored decision before the deadline',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      // The install date lands after each launch's first request is gathered.
      const install = Duration(milliseconds: 20);
      const gather = Duration(milliseconds: 5);
      launch(requests, installDateAfter: install, gatherAfter: gather);
      await accept(tester);
      launch(requests, installDateAfter: install, gatherAfter: gather);
      expect(await atDeadline(tester, name: 'home_card'), 'Welcome');
    });

    testWidgets('a cold relaunch paints the decision saved before its mount',
        (tester) async {
      final store = _SlowWriteStore(Duration.zero);
      sharedSurfaceArtifactStore = store;
      final requests = <PlacementBatchRequestV1>[];
      launch(requests);
      await accept(tester);
      // Storage answers slowly while the first frame builds, and the
      // startup batch is still in flight when the screen mounts.
      store.keysDelay = const Duration(milliseconds: 600);
      launch(requests, prefetchDelay: const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(await atDeadline(tester, name: 'home_card'), 'Welcome');
      await tester.pump(const Duration(seconds: 2));
      await _finish(tester);
    });

    testWidgets('a remount reads the decision this process just accepted',
        (tester) async {
      final store = _SlowWriteStore(Duration.zero);
      sharedSurfaceArtifactStore = store;
      final requests = <PlacementBatchRequestV1>[];
      launch(requests);
      await accept(tester);
      // Storage now answers after the deadline; memory does not.
      store.readDelay = const Duration(milliseconds: 600);
      store.keysDelay = const Duration(milliseconds: 600);
      expect(await atDeadline(tester, name: 'home_card'), 'Welcome');
      // The mount's own answer is still being saved.
      store.readDelay = store.keysDelay = Duration.zero;
      await tester.pump(const Duration(seconds: 2));
      await _finish(tester);
    });

    testWidgets(
        'a relaunch paints a remembered mount when the fresh window passes',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      launch(requests);
      await accept(tester);
      launch(requests);
      // The read ahead and the warm-up finish before the screen mounts.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpWidget(mount(name: 'home_card'));
      // The fresh window is zero here, so saved content shows once it settles.
      await tester.pump();
      expect(find.text('Welcome'), findsOneWidget);
      await tester.pump(slowMount);
      await _finish(tester);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the warm-up asks the platform for nothing before the mount',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      launch(requests);
      await accept(tester);
      final before = debugPlatformReadsStarted;
      launch(requests);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(debugPlatformReadsStarted, before);
      await tester.pumpWidget(mount(name: 'home_card'));
      // The fresh window is zero here, so saved content shows once it settles.
      await tester.pump();
      expect(find.text('Welcome'), findsOneWidget);
      await tester.pump(slowMount);
      expect(debugPlatformReadsStarted, greaterThan(before));
      await _finish(tester);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a relaunch knows it holds the declared decisions',
        (tester) async {
      PlacementMountRequestV1 mountOf(String name) =>
          PlacementMountBinding(definition: () => definition, name: name)
              .capture()
              .mount;
      final requests = <PlacementBatchRequestV1>[];
      // The mount [accept] saves a decision for.
      final declared = [mountOf('home_card')];
      Future<bool> holds() async {
        await tester.runAsync(() => Restage.placementRegistry!.readAhead());
        return Restage.placementRegistry!.holdsDecisionsFor(declared);
      }

      launch(requests);
      expect(Restage.placementRegistry!.holdsDecisionsFor(declared), isFalse);
      expect(await holds(), isFalse);
      await accept(tester);
      launch(requests);
      expect(Restage.placementRegistry!.holdsDecisionsFor(declared), isFalse);
      expect(await holds(), isTrue);
      expect(
          Restage.placementRegistry!
              .holdsDecisionsFor([...declared, mountOf('elsewhere')]),
          isFalse);
      expect(Restage.placementRegistry!.holdsDecisionsFor(const []), isFalse);
      await tester.pump(const Duration(seconds: 10));
      await _finish(tester);
    });

    testWidgets('a relaunch under another capability holds no decisions',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      final declared = [
        PlacementMountBinding(definition: () => definition, name: 'home_card')
            .capture()
            .mount,
      ];
      launch(requests);
      await accept(tester);
      launch(requests);
      await tester.runAsync(() => Restage.placementRegistry!.readAhead());
      expect(Restage.placementRegistry!.holdsDecisionsFor(declared), isTrue);
      const SurfaceVocabulary(libraries: [
        RestageWidgetLibraryRegistration.constant(
            library: WidgetLibrary.custom('acme.ui'),
            capabilityVersion: 1,
            generatedVersion: 1,
            widgets: []),
      ]).addToInstalled();
      launch(requests);
      await tester.runAsync(() => Restage.placementRegistry!.readAhead());
      expect(Restage.placementRegistry!.holdsDecisionsFor(declared), isFalse);
      await tester.pump(const Duration(seconds: 10));
      await _finish(tester);
    });

    testWidgets(
        'a relaunch holding its decisions sends the startup batch without '
        'waiting for the first frame', (tester) async {
      sharedSurfaceArtifactStore = _OffIsolateStore();
      // Frames drawn when each startup batch left.
      var frames = 0;
      final sentAfter = <int>[];
      Future<void> start() async {
        frames = 0;
        SchedulerBinding.instance.addPostFrameCallback((_) => frames += 1);
        Restage.declareSurfaces([definition]);
        launch(<PlacementBatchRequestV1>[], onSend: (sent) {
          if (sent.mode == PlacementBatchModeV1.prefetch) sentAfter.add(frames);
        });
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 50));
      }

      await start();
      expect(sentAfter, [0]);
      await accept(tester);
      sentAfter.clear();
      await start();
      // Nothing waits for a frame, so the batch is out before the first.
      expect(sentAfter.first, 0);
      await _finish(tester);
    });

    testWidgets('a hidden relaunch sends its startup batch without a frame',
        (tester) async {
      sharedSurfaceArtifactStore = _OffIsolateStore();
      Restage.declareSurfaces([definition]);
      launch(<PlacementBatchRequestV1>[]);
      await accept(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      addTearDown(() => tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      final sent = <PlacementBatchModeV1>[];
      Restage.declareSurfaces([definition]);
      launch(<PlacementBatchRequestV1>[], onSend: (request) {
        sent.add(request.mode);
      });
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      expect(sent, contains(PlacementBatchModeV1.prefetch));
      await _finish(tester);
    });

    testWidgets('a held decision paints before the deadline', (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      launch(requests);
      await accept(tester);
      await tester.pumpWidget(mount(name: 'home_card'));
      // Well inside the 300 ms deadline, with the mount's answer still out.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text('Welcome'), findsOneWidget);
      await tester.pump(slowMount);
      await _finish(tester);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('each placement mount reports where its first paint came from',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      launch(requests);
      final events = <RestageEvent>[];
      final subscription = Restage.events.listen(events.add);
      addTearDown(subscription.cancel);
      // The answer misses the wait, so the original paints and it is kept.
      await accept(tester);
      // The next mount paints the decision it kept.
      await tester.pumpWidget(mount(name: 'home_card'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text('Welcome'), findsOneWidget);
      await tester.pump(slowMount);
      await _finish(tester);
      await tester.pumpWidget(const SizedBox());
      final loads = [
        for (final event in events)
          if (event is SurfaceLoadStarted ||
              event is SurfaceLoadCompleted ||
              event is SurfaceLoadFailed)
            event,
      ];
      expect(loads.map((event) => event.runtimeType), [
        SurfaceLoadStarted,
        SurfaceLoadCompleted,
        SurfaceLoadStarted,
        SurfaceLoadCompleted,
      ]);
      final [first, second] = loads.whereType<SurfaceLoadCompleted>().toList();
      expect((first.surfaceId, first.surface), ('original', Surface.paywall));
      expect(first.source, SurfaceLoadSource.original);
      expect(first.firstLaunchWaitPassed, isTrue);
      expect(second.source, SurfaceLoadSource.saved);
      expect(second.firstLaunchWaitPassed, isFalse);
    });

    testWidgets('a mount right after configure waits for the saved decisions',
        (tester) async {
      final store = _SlowWriteStore(Duration.zero);
      sharedSurfaceArtifactStore = store;
      final requests = <PlacementBatchRequestV1>[];
      launch(requests);
      await accept(tester);
      // The read ahead is still in flight when the screen mounts.
      store.keysDelay = const Duration(milliseconds: 250);
      launch(requests,
          gatherAfter: const Duration(milliseconds: 100),
          prefetchDelay: const Duration(seconds: 2));
      expect(await atDeadline(tester, name: 'home_card'), 'Welcome');
      await tester.pump(const Duration(seconds: 2));
      await _finish(tester);
    });

    Future<List<SurfaceStoreKey>> storedKeys(String type) async => [
          for (final key in await sharedSurfaceArtifactStore.keys())
            if (key.surfaceType == type) key,
        ];

    testWidgets('a new build reuses a saved decision that read no build fact',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      launch(requests, build: 42);
      await accept(tester);
      for (final build in [43, 44, 45]) {
        launch(requests, build: build);
        await accept(tester, shown: 'Welcome');
      }
      expect(await storedKeys('placementDecision'), hasLength(1));
      expect(await storedKeys('placementArtifact'), hasLength(1));
      // A row an older version left is neither read ahead nor kept.
      final scope = (await storedKeys('placementDecision')).single.scope;
      await sharedSurfaceArtifactStore.write(
          SurfaceStoreKey(
              scope: scope,
              surfaceType: 'placementDecision',
              slug: 'older',
              contractVersion: 1),
          StoredSurface(
              descriptorJson: Uint8List(0), artifactBytes: Uint8List(0)));
      // The read ahead at build 45 holds that one decision and its frame.
      launch(requests, build: 45);
      final rows = await Restage.placementRegistry!.decisions.saved!.rows;
      expect(rows.keys.map((key) => key.surfaceType),
          unorderedEquals(['placementDecision', 'placementArtifact']));
      expect(await atDeadline(tester, name: 'home_card'), 'Welcome');
      expect(await storedKeys('placementDecision'), hasLength(1));
    });

    testWidgets('a decision that cannot be saved keeps the earlier one',
        (tester) async {
      final store = _FailingRowStore();
      sharedSurfaceArtifactStore = store;
      final requests = <PlacementBatchRequestV1>[];
      launch(requests, build: 42);
      await accept(tester);
      final earlier = await storedKeys('placementDecision');
      expect(earlier, hasLength(1));
      store.failRows = true;
      final lines = <String>[];
      final print = debugPrint;
      debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
      try {
        launch(requests, build: 43);
        await accept(tester, shown: 'Welcome');
      } finally {
        debugPrint = print;
      }
      // The new row was never written, so nothing it replaces is evicted.
      expect(await storedKeys('placementDecision'), earlier);
      expect(
          lines,
          contains(startsWith("[restage] This device couldn't save a "
              'placement decision')));
    });

    testWidgets(
        'a remount paints what this process accepted when the fresh window passes',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      // Every gather takes longer than a frame.
      launch(requests, gatherAfter: const Duration(milliseconds: 200));
      await tester.pumpWidget(mount(name: 'home_card'));
      await tester.pump(const Duration(seconds: 1));
      await _finish(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(mount(name: 'home_card'));
      // The fresh window is zero here, so saved content shows once it settles.
      await tester.pump();
      expect(find.text('Welcome'), findsOneWidget);
      await tester.pump(slowMount);
      await _finish(tester);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a remount of a decision that read a device fact waits for it',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      const install = Duration(milliseconds: 20);
      launch(requests,
          installDateAfter: install,
          consulted: ['daysSinceInstall'],
          gatherAfter: const Duration(milliseconds: 200));
      await tester.pumpWidget(mount(name: 'home_card'));
      await tester.pump(const Duration(seconds: 1));
      await _finish(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(mount(name: 'home_card'));
      expect(find.text('Welcome'), findsNothing);
      expect(await atDeadline(tester, name: 'home_card'), 'Welcome');
      await tester.pump(slowMount);
      await _finish(tester);
    });

    testWidgets(
        'a saved decision is found after another placement first mounts',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      launch(requests);
      await accept(tester);
      // A placement first seen after the decision was saved.
      await tester.pumpWidget(mount(name: 'other_card'));
      await tester.pump(slowMount);
      await _finish(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpWidget(const SizedBox());
      launch(requests);
      expect(await atDeadline(tester, name: 'home_card'), 'Welcome');
      await tester.pump(slowMount);
      await _finish(tester);
    });

    testWidgets('a reset before the first mount shows the original',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      launch(requests);
      await accept(tester);
      launch(requests);
      await tester
          .runAsync(() => Restage.placementRegistry!.decisions.saved!.rows);
      Restage.reset();
      expect(await atDeadline(tester, name: 'home_card'), 'Original');
    });

    testWidgets('a keyed relaunch keeps its saved decision decoded',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      launch(requests, keyed: true);
      await accept(tester);
      launch(requests, keyed: true);
      final saved = Restage.placementRegistry!.decisions.saved!;
      Future<SavedRow> decision() async =>
          (await tester.runAsync(() => saved.rows))!
              .entries
              .singleWhere((MapEntry<SurfaceStoreKey, SavedRow> row) =>
                  row.key.surfaceType == 'placementDecision')
              .value;
      final before = await decision();
      expect(before.decision, isNotNull);
      // The keyless startup batch answers; the device's keyed row stays.
      await tester.pump(const Duration(seconds: 2));
      await _finish(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(seconds: 1));
      expect(requests.map((request) => request.mode),
          contains(PlacementBatchModeV1.prefetch));
      final after = await decision();
      expect(after.decision, isNotNull);
      expect(identical(after.stored, before.stored), isTrue);
    });

    testWidgets('a reset while an answer is being saved holds', (tester) async {
      sharedSurfaceArtifactStore =
          _SlowWriteStore(const Duration(milliseconds: 500));
      final requests = <PlacementBatchRequestV1>[];
      launch(requests);
      await tester.pumpWidget(mount(name: 'home_card'));
      // The answer is shown; its save is still running.
      await tester.pump(slowMount);
      Restage.reset();
      await tester.pump(const Duration(seconds: 2));
      await _finish(tester);
      await tester.pumpWidget(const SizedBox());
      launch(requests);
      expect(await atDeadline(tester, name: 'home_card'), 'Original');
      await tester.pump(const Duration(seconds: 2));
      await _finish(tester);
    });

    testWidgets('a read sees a change made while it runs', (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      launch(requests);
      await accept(tester);
      launch(requests);
      final registry = Restage.placementRegistry!;
      final decisions = registry.decisions;
      await tester.runAsync(() => decisions.saved!.rows);
      final request = requests.last;
      final found = await tester.runAsync(() => decisions.read(
          request: request,
          configurationFingerprint: registry.configurationFingerprint,
          acceptsStored: (stored, decision) async {
            // Another mount drops the row mid-read.
            for (final key in await storedKeys('placementDecision')) {
              await registry.decisions.remove(key);
            }
            return true;
          }));
      expect(found, isNull);
      await tester.pump(const Duration(seconds: 1));
      await _finish(tester);
    });

    testWidgets('a keyed device paints its stored decision before the deadline',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      launch(requests, keyed: true);
      await accept(tester);
      expect(requests.last.registration, isNotNull);
      launch(requests, keyed: true);
      expect(await atDeadline(tester, name: 'home_card'), 'Welcome');
      // The relaunch read its confirmed handle back from storage.
      final mounted = requests
          .lastWhere((request) => request.mode == PlacementBatchModeV1.mount);
      expect(mounted.assignmentKey, 'ic1.${'b' * 64}');
    });

    testWidgets('a decision stored warm serves a cold gather', (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      launch(requests, day: DateTime.utc(2026, 10, 4, 12));
      await accept(tester);
      expect(
          _builtInsOf(requests.last).containsKey('daysSinceInstall'), isTrue);
      // The install date lands after this launch's first request is gathered.
      launch(requests,
          installDateAfter: const Duration(milliseconds: 200),
          gatherAfter: const Duration(milliseconds: 5));
      expect(await atDeadline(tester, name: 'home_card'), 'Welcome');
    });

    testWidgets('reuses a decision routed on install age the same day',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      const install = Duration(milliseconds: 20);
      launch(requests,
          installDateAfter: install, consulted: ['daysSinceInstall']);
      await accept(tester);
      launch(requests,
          installDateAfter: install, consulted: ['daysSinceInstall']);
      expect(await atDeadline(tester, name: 'home_card'), 'Welcome');
    });

    testWidgets('refuses an install-age decision when the gather lacks the age',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      launch(requests,
          day: DateTime.utc(2026, 10, 4, 12), consulted: ['daysSinceInstall']);
      await accept(tester);
      launch(requests,
          installDateAfter: const Duration(milliseconds: 200),
          consulted: ['daysSinceInstall']);
      expect(await atDeadline(tester, name: 'home_card'), 'Original');
    });

    // Launch 1 stores a decision routed on an install age it did not send.
    Future<_SlowWriteStore> storeAgeDecision(
        WidgetTester tester, List<PlacementBatchRequestV1> requests) async {
      final store = _SlowWriteStore(Duration.zero);
      sharedSurfaceArtifactStore = store;
      const install = Duration(milliseconds: 150);
      launch(requests,
          installDateAfter: install, consulted: ['daysSinceInstall']);
      // The send waits for the install date; the mount stays up until its
      // answer is stored.
      await tester.pumpWidget(mount(name: 'home_card'));
      await tester.pump(slowMount + install);
      await _finish(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await _finish(tester);
      await tester.pumpWidget(const SizedBox());
      expect(_builtInsOf(requests.last), isNot(contains('daysSinceInstall')));
      // Slow storage lets the install date land before the stored row is shown.
      store.keysDelay = const Duration(milliseconds: 200);
      return store;
    }

    // What a relaunch shows at the deadline, and the lines it logged.
    Future<(String, List<String>)> relaunch(WidgetTester tester,
        List<PlacementBatchRequestV1> requests, Duration mountDelay) async {
      final lines = <String>[];
      final previous = debugPrint;
      debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
      // This launch's own answer reads no fact. Only the saved one is refused.
      launch(requests,
          installDateAfter: const Duration(milliseconds: 150),
          mountDelay: mountDelay);
      final shown = await atDeadline(tester, name: 'home_card');
      debugPrint = previous;
      return (shown, lines);
    }

    testWidgets('refuses a stored decision whose routed-on fact lands late',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      await storeAgeDecision(tester, requests);
      final (shown, lines) = await relaunch(tester, requests, slowMount);
      expect(shown, 'Original');
      expect(lines, [
        '[restage] placement named:home_card shows its fallback (stale): '
            "the device's install age changed after this decision was made. "
            "The decision wasn't shown. It's retried on the next mount."
      ]);
    });

    testWidgets('a refused stored decision is not logged when fresh shows',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      await storeAgeDecision(tester, requests);
      // The fresh answer lands after the saved one is refused, before the
      // deadline.
      final (shown, lines) =
          await relaunch(tester, requests, const Duration(milliseconds: 100));
      expect(shown, 'Welcome');
      expect(lines, isEmpty);
    });

    testWidgets('reuses a decision across a day that it did not route on',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      final today = DateTime.utc(2026, 10, 4, 12);
      launch(requests, day: today);
      await accept(tester);
      launch(requests, day: today.add(const Duration(days: 1)));
      expect(await atDeadline(tester, name: 'home_card'), 'Welcome');
    });

    testWidgets('asks again when the install age it routed on moves',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      final today = DateTime.utc(2026, 10, 4, 12);
      launch(requests, day: today, consulted: ['daysSinceInstall']);
      await accept(tester);
      // The same day keeps it; the next day's age does not.
      launch(requests, day: today, consulted: ['daysSinceInstall']);
      expect(await atDeadline(tester, name: 'home_card'), 'Welcome');
      launch(requests,
          day: today.add(const Duration(days: 1)),
          consulted: ['daysSinceInstall']);
      expect(await atDeadline(tester, name: 'home_card'), 'Original');
    });

    testWidgets(
        'a first launch paints its declared placement from the startup batch',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      Restage.declareSurfaces([definition]);
      launch(requests, keyed: true);
      // Sent before any frame, so the first mount can paint its answer.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(requests.map((request) => request.mode),
          [PlacementBatchModeV1.prefetch]);
      expect(await atDeadline(tester), 'Welcome');
      // The startup batch registers, and the mount takes its answer.
      final startup = requests.first;
      expect(startup.registration, isNotNull);
      expect(startup.assignmentKey, isNull);
      expect(
          requests
              .where((request) => request.mode == PlacementBatchModeV1.mount),
          isEmpty);
    });

    testWidgets(
        'a declared mount sends no request of its own when the startup '
        'answer covers it', (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      Restage.declareSurfaces([definition]);
      // The first launch registers, so the next one holds a key to send.
      launch(requests, keyed: true);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await atDeadline(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      requests.clear();
      Restage.declareSurfaces([definition]);
      launch(requests, keyed: true);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(await atDeadline(tester), 'Welcome');
      expect(requests.first.mode, PlacementBatchModeV1.prefetch);
      expect(requests.first.assignmentKey, isNotNull);
      expect(
          requests
              .where((request) => request.mode == PlacementBatchModeV1.mount),
          isEmpty);
    });

    testWidgets(
        'a mount built before the startup batch waits for it instead of sending',
        (tester) async {
      final store = _OffIsolateStore()..readAheadGate = Completer<void>();
      sharedSurfaceArtifactStore = store;
      final requests = <PlacementBatchRequestV1>[];
      Restage.declareSurfaces([definition]);
      launch(requests, keyed: true, surfaces: [definition]);
      // The first frame builds the mount while the read ahead is still out.
      await tester.pumpWidget(mount());
      await tester.pump(const Duration(milliseconds: 100));
      expect(requests, isEmpty);
      store.readAheadGate!.complete();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(seconds: 2));
      await _finish(tester);
      expect(requests.map((request) => request.mode),
          [PlacementBatchModeV1.prefetch]);
      expect(find.text('Welcome'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a slow store does not hold back the startup answer',
        (tester) async {
      final store = _SlowWriteStore(const Duration(milliseconds: 600));
      sharedSurfaceArtifactStore = store;
      final requests = <PlacementBatchRequestV1>[];
      Restage.declareSurfaces([definition]);
      launch(requests);
      // The read ahead runs off the frame isolate, in real time.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(await atDeadline(tester), 'Welcome');
      await tester.pump(const Duration(seconds: 2));
      await _finish(tester);
    });

    for (final valid in [true, false]) {
      testWidgets(
          'a first launch paints from bytes sent with its answer '
          '(valid $valid)', (tester) async {
        final requests = <PlacementBatchRequestV1>[];
        Restage.declareSurfaces([definition]);
        // The mount's own answer lands after the deadline.
        _configure(requests,
            delayEach: () => Future<void>.delayed(
                requests.last.mode == PlacementBatchModeV1.mount
                    ? slowMount
                    : Duration.zero),
            respond: (request) {
              final base = placementFixtureResponse(request);
              if (!request.inlineMounts.isNotEmpty) return base;
              final inline = <ArtifactIdentityV1, List<int>>{
                for (final row
                    in base.decisions.whereType<PlacementBatchAvailableV1>())
                  for (final reference in row.artifactClosure)
                    reference.identity: valid
                        ? placementFixtureFrames
                            .remove(reference.descriptor.artifactUrl)!
                        : [0, 1, 2],
              };
              return PlacementBatchResolvedV1.fromBuiltRows(
                  request: request,
                  expectedTarget: readPlacementDeliveryFixture().target,
                  decisions: base.decisions,
                  inlineArtifacts: inline);
            });
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        expect(requests.single.inlineMounts, isNotEmpty);
        // Bytes that fail their check have no pass to fetch with.
        expect(await atDeadline(tester), valid ? 'Welcome' : 'Original');
      });
    }

    testWidgets('a launch that holds artifacts does not ask for them',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      launch(requests);
      await accept(tester);
      Restage.declareSurfaces([definition]);
      launch(requests);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(requests.last.mode, PlacementBatchModeV1.prefetch);
      expect(requests.last.inlineMounts, isEmpty);
      await tester.pump(const Duration(seconds: 2));
      await _finish(tester);
    });

    testWidgets('a startup answer on a fact it sent is kept', (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      Restage.declareSurfaces([definition]);
      launch(requests,
          day: DateTime.utc(2026, 10, 4, 12), consulted: ['daysSinceInstall']);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(requests.single.mode, PlacementBatchModeV1.prefetch);
      expect(_builtInsOf(requests.single), contains('daysSinceInstall'));
      expect(await atDeadline(tester), 'Welcome');
    });

    testWidgets('a prefetched decision serves the first mount', (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      launch(requests, surfaces: [definition]);
      await tester.pumpWidget(const SizedBox());
      await _finish(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(requests.map((request) => request.mode),
          [PlacementBatchModeV1.prefetch]);
      expect(await atDeadline(tester), 'Welcome');
      // The startup batch carries the device's full facts.
      expect(_builtInsOf(requests.first).keys, contains('appBuildOrdinal'));
    });
  });

  testWidgets('an install date that lands after the send keeps the answer',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final reports = <SurfaceResolutionReport>[];
    // An install date slower than the gather's wait lands after the send.
    _configure(requests,
        installDateAfter: const Duration(milliseconds: 150),
        gatherAfter: const Duration(milliseconds: 5),
        delayEach: () => Future<void>.delayed(const Duration(milliseconds: 40)),
        onSurfaceResolution: reports.add);
    final lines = await mountPaywall(tester);
    expect(requests, hasLength(1));
    expect(_builtInsOf(requests.single), isNot(contains('daysSinceInstall')));
    expect(find.text('Welcome'), findsOneWidget);
    expect(reports.map((report) => report.reason), isNot(contains('stale')));
    expect(lines.where((line) => line.contains('(stale)')), isEmpty);
    await tester.pumpWidget(const SizedBox());
    // The answer is stored under the facts it was sent with, so the next
    // mount asks again with the install age.
    await mountPaywall(tester);
    expect(requests, hasLength(2));
    expect(_builtInsOf(requests.last)['daysSinceInstall'], 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an answer shows before it is saved', (tester) async {
    // Saving takes longer than the deadline; the answer does not wait for it.
    sharedSurfaceArtifactStore =
        _SlowWriteStore(const Duration(milliseconds: 600));
    final requests = <PlacementBatchRequestV1>[];
    final reports = <SurfaceResolutionReport>[];
    _configure(requests, onSurfaceResolution: reports.add);
    await mountPaywall(tester);
    expect(find.text('Welcome'), findsOneWidget);
    expect(reports.first.source, SurfaceResolutionSource.fresh);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    await _finish(tester);
  });

  testWidgets('an install date that lands while the answer is stored keeps it',
      (tester) async {
    sharedSurfaceArtifactStore =
        _SlowWriteStore(const Duration(milliseconds: 40));
    final requests = <PlacementBatchRequestV1>[];
    final reports = <SurfaceResolutionReport>[];
    _configure(requests,
        installDateAfter: const Duration(milliseconds: 20),
        gatherAfter: const Duration(milliseconds: 5),
        onSurfaceResolution: reports.add);
    final lines = await mountPaywall(tester);
    expect(requests, hasLength(1));
    expect(find.text('Welcome'), findsOneWidget);
    expect(reports.map((report) => report.reason),
        everyElement(isNot(anyOf('unsupported', 'stale'))));
    expect(lines.where((line) => line.contains('shows its fallback')), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a time zone that changes after the send names it',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final reports = <SurfaceResolutionReport>[];
    final utc = DateTime.utc(2026, 10, 4, 12);
    var moved = false;
    _configure(requests,
        now: () => moved ? _ZonedTime(utc, const Duration(hours: 9)) : utc,
        delayEach: () async => moved = true,
        cacheValidityOverrides: {
          'expiresBeforeLocal':
              LocalCivilDateTimeV1.parse('2026-10-05T00:00:00').toJson(),
        },
        onSurfaceResolution: reports.add);
    final lines = await mountPaywall(tester);
    expect(requests, hasLength(1));
    expect(find.text('Original'), findsOneWidget);
    expect(
        reports.map((report) => report.reason), isNot(contains('unsupported')));
    expect(
        lines,
        contains(endsWith("shows its fallback (stale): the device's time zone "
            "changed after the request was sent. The delivered version's time "
            'window is set in the old time zone. The answer was dropped. '
            "It's retried on the next mount.")));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('content that cannot be downloaded names it', (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final reports = <SurfaceResolutionReport>[];
    _configure(requests,
        contentUnavailable: true, onSurfaceResolution: reports.add);
    final lines = await mountPaywall(tester);
    expect(requests, hasLength(1));
    expect(find.text('Original'), findsOneWidget);
    expect(
        reports.map((report) => report.reason), isNot(contains('unsupported')));
    expect(
        lines,
        contains(endsWith('shows its fallback (artifactUnavailable): the '
            "delivered version's content couldn't be downloaded or verified. "
            "It's retried on the next mount.")),
        reason: lines.join('\n'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a version that expires before it is shown names it',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final reports = <SurfaceResolutionReport>[];
    var now = DateTime.utc(2026, 10, 4, 12);
    _configure(requests,
        now: () => now,
        delayEach: () async => now = now.add(const Duration(seconds: 1)),
        cacheValidityOverrides: {
          'contentExpiresAtMicros':
              now.add(const Duration(seconds: 1)).microsecondsSinceEpoch
        },
        onSurfaceResolution: reports.add);
    final lines = await mountPaywall(tester);
    expect(requests, hasLength(1));
    expect(find.text('Original'), findsOneWidget);
    expect(
        reports.map((report) => report.reason), isNot(contains('unsupported')));
    expect(
        lines,
        contains(endsWith("shows its fallback (stale): the delivered version's "
            'time window or experiment assignment ended before it could be '
            "shown. The answer was dropped. It's retried on the next mount.")));
    await tester.pumpWidget(const SizedBox());
  });

  for (final (label, overrides, move, sentence) in [
    (
      'a local window that ends in flight',
      {
        'expiresBeforeLocal':
            LocalCivilDateTimeV1.parse('2026-10-04T12:00:01').toJson(),
      },
      const Duration(seconds: 1),
      "the delivered version's time window or experiment assignment ended "
          "before it could be shown. The answer was dropped. It's retried on "
          'the next mount.',
    ),
    (
      'a local window not started by the device clock',
      {
        'notBeforeLocal':
            LocalCivilDateTimeV1.parse('2026-10-04T13:00:00').toJson(),
      },
      Duration.zero,
      "the delivered version's time window hasn't started by this device's "
          "clock. The answer was dropped. It's retried on the next mount.",
    ),
    (
      'a clock that moves back in flight',
      const <String, Object?>{},
      const Duration(seconds: -1),
      'the device clock moved back while the request was in flight. The '
          "answer was dropped. It's retried on the next mount.",
    ),
  ]) {
    testWidgets('$label names why the answer lapsed', (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      final reports = <SurfaceResolutionReport>[];
      var now = DateTime.utc(2026, 10, 4, 12);
      _configure(requests,
          now: () => now,
          delayEach: () async => now = now.add(move),
          cacheValidityOverrides: overrides,
          onSurfaceResolution: reports.add);
      final lines = await mountPaywall(tester);
      expect(requests, hasLength(1));
      expect(find.text('Original'), findsOneWidget);
      expect(reports.map((report) => report.reason),
          isNot(contains('unsupported')));
      expect(
          lines, contains(endsWith('shows its fallback (stale): $sentence')));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('an answer routed on a fact that landed in flight is refused',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final reports = <SurfaceResolutionReport>[];
    _configure(requests,
        installDateAfter: const Duration(milliseconds: 150),
        gatherAfter: const Duration(milliseconds: 5),
        delayEach: () =>
            Future<void>.delayed(const Duration(milliseconds: 200)),
        cacheValidityOverrides: const {
          'consultedBuiltIns': ['daysSinceInstall']
        },
        onSurfaceResolution: reports.add);
    final lines =
        await mountPaywall(tester, settle: const Duration(milliseconds: 300));
    expect(requests, hasLength(1));
    expect(_builtInsOf(requests.single), isNot(contains('daysSinceInstall')));
    expect(find.text('Original'), findsOneWidget);
    expect(
        lines,
        contains(endsWith("shows its fallback (stale): the device's install "
            "age changed after this decision was made. The decision wasn't "
            "shown. It's retried on the next mount.")));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a day that turns after the send keeps the answer',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    var day = DateTime.utc(2026, 10, 4, 12);
    _configure(requests, delayEach: () async {
      day = day.add(const Duration(days: 1));
    });
    debugResetInstallObservations(nowUtc: () => day);
    configureSurfaceDeliveryObservations();
    final lines = await mountPaywall(tester);
    expect(requests, hasLength(1));
    expect(find.text('Welcome'), findsOneWidget);
    expect(lines.where((line) => line.contains('(stale)')), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an identity reset during the gather gathers it again',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    _configure(requests);
    var generation = 0;
    var reset = false;
    // The first key read lands during an identity reset.
    SurfaceAssignmentKeyProvider.install(
        key: () {
          if (!reset) {
            reset = true;
            generation++;
          }
          return null;
        },
        identityGeneration: () => generation);
    final lines = await mountPaywall(tester);
    expect(requests, hasLength(1));
    expect(find.text('Welcome'), findsOneWidget);
    expect(lines.where((line) => line.contains('(stale)')), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'an assignment answered to a registering request is kept and sent back',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final assignment = PresentationAssignmentCarrierV2(
        owner: PresentationAssignmentOwnerV2.path,
        outcomeLinkCarrier:
            base64UrlEncode(List.filled(32, 7)).replaceAll('=', ''));
    final handle = 'ic1.${'c' * 64}';
    _configure(requests, respond: (request) {
      final base = placementFixtureResponse(request, assignment: assignment);
      final answer = PlacementBatchResolvedV1(
          request: request,
          expectedTarget: readPlacementDeliveryFixture().target,
          decisions: [
            for (final row in base.decisions.cast<PlacementBatchAvailableV1>())
              PlacementBatchAvailableV1(
                  row.descriptor, row.publicDelivery, row.artifactClosure,
                  heldProof: 'proof.abc-1')
          ]);
      if (request.registration == null) return answer;
      final now = DateTime.now().microsecondsSinceEpoch;
      return PlacementBatchResolvedV1(
          request: request,
          expectedTarget: readPlacementDeliveryFixture().target,
          decisions: answer.decisions,
          registration: SurfaceRegistrationMetadataV1(
              credentialHandle: handle,
              expiresAtMicros: now + Duration.microsecondsPerDay,
              serverNowMicros: now));
    });
    SurfaceCanonicalCarrierProvider.enableAssignmentRetention('test_scope');
    final store = SurfaceAssignmentCredentialStore(
      namespace: 'placements',
      actor: () async => 'actor',
      identityGeneration: () => 0,
      onRetentionRollover: SurfaceCanonicalCarrierProvider.clearHeldAssignments,
    );
    SurfaceAssignmentKeyProvider.install(
      key: store.resolve,
      localKey: store.resolveLocal,
      identityGeneration: () => store.generation,
      registration: store.capture,
      confirmedKey: () => store.currentHandle,
      confirmRegistration: (attempt, start, confirmed, expiry, serverNow) =>
          store.confirm(
        attempt: attempt,
        localRequestStartMicros: start,
        credentialHandle: confirmed,
        expiresAtMicros: expiry,
        serverNowMicros: serverNow,
      ),
      refuseRegistration: store.refuse,
    );
    // The first request registers; its answer is assigned and confirmed.
    await mountPaywall(tester);
    expect(requests.first.registration, isNotNull);
    expect(requests.first.assignmentKey, isNull);
    await tester.pumpWidget(const SizedBox());
    await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
    // The next request carries the handle and the path it was assigned.
    await mountPaywall(tester);
    expect(requests.length, greaterThan(1));
    expect(requests.last.assignmentKey, handle);
    expect(requests.last.heldAssignments.single.retainedPathHandle,
        assignment.outcomeLinkCarrier);
    expect(requests.last.heldAssignments.single.proof, 'proof.abc-1');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an assignment replaces a held decline proof', (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final assignment = PresentationAssignmentCarrierV2(
        owner: PresentationAssignmentOwnerV2.path,
        outcomeLinkCarrier:
            base64UrlEncode(List.filled(32, 7)).replaceAll('=', ''));
    final handle = 'ic1.${'d' * 64}';
    var assigned = false;
    _configure(requests, respond: (request) {
      final base = placementFixtureResponse(request,
          assignment: assigned ? assignment : null);
      final answer = PlacementBatchResolvedV1(
          request: request,
          expectedTarget: readPlacementDeliveryFixture().target,
          decisions: [
            for (final row in base.decisions.cast<PlacementBatchAvailableV1>())
              assigned
                  ? PlacementBatchAvailableV1(
                      row.descriptor, row.publicDelivery, row.artifactClosure,
                      heldProof: 'proof.abc-1')
                  : PlacementBatchAvailableV1(
                      row.descriptor, row.publicDelivery, row.artifactClosure,
                      declineProof: 'dp1.cGF5bG9hZA.bWFj')
          ]);
      if (request.registration == null) return answer;
      final now = DateTime.now().microsecondsSinceEpoch;
      return PlacementBatchResolvedV1(
          request: request,
          expectedTarget: readPlacementDeliveryFixture().target,
          decisions: answer.decisions,
          registration: SurfaceRegistrationMetadataV1(
              credentialHandle: handle,
              expiresAtMicros: now + Duration.microsecondsPerDay,
              serverNowMicros: now));
    });
    SurfaceCanonicalCarrierProvider.enableAssignmentRetention('test_scope');
    final store = SurfaceAssignmentCredentialStore(
      namespace: 'placements',
      actor: () async => 'actor',
      identityGeneration: () => 0,
      onRetentionRollover: SurfaceCanonicalCarrierProvider.clearHeldAssignments,
    );
    SurfaceAssignmentKeyProvider.install(
      key: store.resolve,
      localKey: store.resolveLocal,
      identityGeneration: () => store.generation,
      registration: store.capture,
      confirmedKey: () => store.currentHandle,
      confirmRegistration: (attempt, start, confirmed, expiry, serverNow) =>
          store.confirm(
        attempt: attempt,
        localRequestStartMicros: start,
        credentialHandle: confirmed,
        expiresAtMicros: expiry,
        serverNowMicros: serverNow,
      ),
      refuseRegistration: store.refuse,
    );
    await mountPaywall(tester);
    await tester.pumpWidget(const SizedBox());
    await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
    // The declined device presents its proof; the answer now assigns an arm.
    assigned = true;
    await mountPaywall(tester);
    expect(requests.last.heldDeclines.single.proof, 'dp1.cGF5bG9hZA.bWFj');
    await tester.pumpWidget(const SizedBox());
    await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
    await mountPaywall(tester);
    expect(requests.last.heldDeclines, isEmpty);
    expect(requests.last.heldAssignments, isNotEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'a registering startup answer leaves the platform the next launch request',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final remembered = <PlacementBatchRequestV1>[];
    EarlyRequest.recorder =
        (url, apiKey, request) async => remembered.add(request);
    addTearDown(() => EarlyRequest.recorder = null);
    final assignment = PresentationAssignmentCarrierV2(
        owner: PresentationAssignmentOwnerV2.path,
        outcomeLinkCarrier:
            base64UrlEncode(List.filled(32, 9)).replaceAll('=', ''));
    final handle = 'ic1.${'d' * 64}';
    final host = readPlacementDeliveryFixture()
        .request
        .buildContract
        .contractsByHash
        .values
        .first;
    final definition = _paywallDefinition('original', host);
    Restage.declareSurfaces([definition]);
    _configure(requests, surfaces: [definition], respond: (request) {
      final answer = placementFixtureResponse(request, assignment: assignment);
      if (request.registration == null) return answer;
      final now = DateTime.now().microsecondsSinceEpoch;
      return PlacementBatchResolvedV1(
          request: request,
          expectedTarget: readPlacementDeliveryFixture().target,
          decisions: answer.decisions,
          registration: SurfaceRegistrationMetadataV1(
              credentialHandle: handle,
              expiresAtMicros: now + Duration.microsecondsPerDay,
              serverNowMicros: now));
    });
    SurfaceCanonicalCarrierProvider.enableAssignmentRetention('test_scope');
    final store = SurfaceAssignmentCredentialStore(
      namespace: 'placements',
      actor: () async => 'actor',
      identityGeneration: () => 0,
      onRetentionRollover: SurfaceCanonicalCarrierProvider.clearHeldAssignments,
    );
    SurfaceAssignmentKeyProvider.install(
      key: store.resolve,
      localKey: store.resolveLocal,
      identityGeneration: () => store.generation,
      registration: store.capture,
      confirmedKey: () => store.currentHandle,
      confirmRegistration: (attempt, start, confirmed, expiry, serverNow) =>
          store.confirm(
        attempt: attempt,
        localRequestStartMicros: start,
        credentialHandle: confirmed,
        expiresAtMicros: expiry,
        serverNowMicros: serverNow,
      ),
      refuseRegistration: store.refuse,
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    expect(requests.first.registration, isNotNull);
    expect(remembered, isNotEmpty);
    final next = remembered.last;
    expect(next.registration, isNull);
    expect(next.assignmentKey, handle);
    expect(next.heldAssignments.single.retainedPathHandle,
        assignment.outcomeLinkCarrier);
    expect(next.inlineMounts, isEmpty);
    // A painted assigned decision is not reused, so the next launch asks for
    // its closure and the platform's copy follows.
    final before = remembered.length;
    final registry = Restage.placementRegistry!;
    final saved = await registry.decisions.saved!.rows;
    for (final key in saved.entries
        .where((entry) => entry.value.decision != null)
        .map((entry) => entry.key)
        .toList()) {
      await registry.decisions.remove(key);
    }
    registry.savedChanged();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    expect(remembered.length, greaterThan(before));
    expect(remembered.last.inlineMounts, isNotEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  SurfaceAssignmentCredentialStore installCredentialStore() {
    final store = SurfaceAssignmentCredentialStore(
      namespace: 'placements',
      actor: () async => 'actor',
      identityGeneration: () => 0,
      onRetentionRollover: SurfaceCanonicalCarrierProvider.clearHeldAssignments,
    );
    SurfaceAssignmentKeyProvider.install(
      key: store.resolve,
      localKey: store.resolveLocal,
      identityGeneration: () => store.generation,
      registration: store.capture,
      confirmedKey: () => store.currentHandle,
      confirmRegistration: (attempt, start, confirmed, expiry, serverNow) =>
          store.confirm(
        attempt: attempt,
        localRequestStartMicros: start,
        credentialHandle: confirmed,
        expiresAtMicros: expiry,
        serverNowMicros: serverNow,
      ),
      refuseRegistration: store.refuse,
    );
    return store;
  }

  PlacementBatchResolvedV1 confirming(
      PlacementBatchRequestV1 request, String handle) {
    final now = DateTime.now().microsecondsSinceEpoch;
    return PlacementBatchResolvedV1(
        request: request,
        expectedTarget: readPlacementDeliveryFixture().target,
        decisions: placementFixtureResponse(request).decisions,
        registration: SurfaceRegistrationMetadataV1(
            credentialHandle: handle,
            expiresAtMicros: now + Duration.microsecondsPerDay,
            serverNowMicros: now));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
  }

  testWidgets(
      'the platform request that means the same is adopted, not sent again',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final handle = 'ic1.${'e' * 64}';
    final host = readPlacementDeliveryFixture()
        .request
        .buildContract
        .contractsByHash
        .values
        .first;
    final definition = _paywallDefinition('original', host);
    Restage.declareSurfaces([definition]);
    _configure(requests, surfaces: [definition]);
    final store = installCredentialStore();
    PlacementBatchRequestV1? sent;
    // The platform went by hash and reported no mounted surfaces: the same
    // request in meaning, not in bytes.
    EarlyRequest.debugSent = (mine) {
      sent = mine.withMountedSince(const []);
      return sent!.withBuildContract(carried: false).canonicalBytes;
    };
    addTearDown(() => EarlyRequest.debugSent = null);
    EarlyRequest.debugInFlight = ({int timeoutMs = 20000}) async => (
          sent: sent!.withBuildContract(carried: false).canonicalBytes,
          response: EarlyResponse(
              status: 200,
              body:
                  Uint8List.fromList(confirming(sent!, handle).canonicalBytes),
              headers: const {}),
        );
    addTearDown(() => EarlyRequest.debugInFlight = null);
    await settle(tester);
    expect(sent?.registration, isNotNull);
    // No startup request left from Dart, and the platform's answer confirmed
    // the handle.
    expect(requests.where((request) => request.startup), isEmpty);
    expect(store.currentHandle, handle);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'a platform answer that cannot be decoded is replaced by one fetched from Dart',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final handle = 'ic1.${'e' * 64}';
    final host = readPlacementDeliveryFixture()
        .request
        .buildContract
        .contractsByHash
        .values
        .first;
    final definition = _paywallDefinition('original', host);
    Restage.declareSurfaces([definition]);
    _configure(requests,
        surfaces: [definition],
        respond: (request) => request.registration == null
            ? placementFixtureResponse(request)
            : confirming(request, handle));
    final store = installCredentialStore();
    EarlyRequest.debugSent = (mine) => mine.canonicalBytes;
    addTearDown(() => EarlyRequest.debugSent = null);
    EarlyRequest.debugInFlight = ({int timeoutMs = 20000}) async => (
          sent: Uint8List(0),
          response: EarlyResponse(
              status: 200,
              body: Uint8List.fromList([1, 2, 3]),
              headers: const {}),
        );
    addTearDown(() => EarlyRequest.debugInFlight = null);
    await settle(tester);
    // The platform's answer was refused, so Dart sent its own request and its
    // answer confirmed the handle.
    expect(requests.where((request) => request.registration != null),
        hasLength(1));
    expect(store.currentHandle, handle);
    await tester.pumpWidget(const SizedBox());
  });

  group('a platform request that means something else is not adopted', () {
    const otherUuid = '0b8e7a52-6f2d-4c3a-9e1f-7d4b2a6c8e10';
    final cases = <StartupAnswerMismatch,
        Map<String, Object?> Function(PlacementBatchRequestV1 mine)>{
      StartupAnswerMismatch.build: (mine) => {
            ...mine.withBuildContract(carried: false).toJson(),
            'appBuildContractHash': 'sha256:${'f' * 64}',
          },
      StartupAnswerMismatch.capability: (mine) {
        final build = mine.buildContract;
        final installed = build.installedCapability;
        final claimed = InstalledCapability(
          builtInCatalogVersion: installed.builtInCatalogVersion,
          installedLibraries: installed.installedLibraries,
          vocabulary: WidgetVocabulary(
            widgetNames: {
              ...?installed.vocabulary?.widgetNames,
              'restage.core:NotInstalled',
            },
            iconCodePoints: installed.vocabulary?.iconCodePoints ?? const {},
          ),
        );
        final larger = PlacementBuildContractV1(
            platform: build.platform,
            buildOrdinal: build.buildOrdinal,
            mounts: build.mounts.toList(),
            contractsByHash: build.contractsByHash,
            installedCapability: claimed,
            installedCapabilityHash: claimed.contentHash);
        // The template the platform sent from spells that build.
        EarlyRequest.debugTemplate = () async => jsonEncode({
              'url': 'https://example.com/sdk/v1/placements/resolve',
              'authorization': 'Bearer rs_pk_test',
              'contract': utf8.decode(larger.canonicalBytes),
            });
        return {
          ...mine.withBuildContract(carried: false).toJson(),
          'appBuildContractHash': larger.appBuildContractHash,
        };
      },
      StartupAnswerMismatch.analytics: (mine) =>
          {...mine.toJson(), 'analyticsAnonymousId': otherUuid},
      StartupAnswerMismatch.measurement: (mine) => {
            ...mine.toJson(),
            'registrationNonce': 'A' * 43,
            'registrationCreatedAtMicros': 1,
          },
      StartupAnswerMismatch.assignment: (mine) =>
          {...mine.toJson(), 'meteringKey': otherUuid},
    };
    for (final MapEntry(key: reason, value: edit) in cases.entries) {
      testWidgets('${reason.name}: Dart sends its own and says why',
          (tester) async {
        final requests = <PlacementBatchRequestV1>[];
        final host = readPlacementDeliveryFixture()
            .request
            .buildContract
            .contractsByHash
            .values
            .first;
        final definition = _paywallDefinition('original', host);
        Restage.declareSurfaces([definition]);
        _configure(requests, surfaces: [definition]);
        final printed = <String>[];
        final reported = <String>[];
        final print = debugPrint;
        final onError = FlutterError.onError;
        debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
        FlutterError.onError =
            (details) => reported.add('${details.exception}');
        var consulted = false;
        EarlyRequest.debugSent =
            (mine) => CanonicalJsonCodec.encode(edit(mine));
        EarlyRequest.debugInFlight = ({int timeoutMs = 20000}) async {
          consulted = true;
          return null;
        };
        try {
          await settle(tester);
        } finally {
          debugPrint = print;
          FlutterError.onError = onError;
          EarlyRequest.debugSent = null;
          EarlyRequest.debugInFlight = null;
          EarlyRequest.debugTemplate = null;
        }
        final message = unadoptedStartupMessage(reason);
        expect(printed, contains('[restage] $message'));
        // A choice that changed this launch is followed from the next one;
        // the others are reported as errors to fix.
        final followed = reason == StartupAnswerMismatch.analytics ||
            reason == StartupAnswerMismatch.assignment;
        expect(reported.where((r) => r.contains(message)),
            followed ? isEmpty : hasLength(1));
        expect(consulted, isFalse);
        expect(requests.where((request) => request.startup), hasLength(1));
        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  testWidgets('a credential the service no longer holds registers again',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    _configure(requests,
        respond: (request) => request.assignmentKey == null
            ? placementFixtureResponse(request)
            : PlacementBatchResolvedV1(
                request: request,
                expectedTarget: readPlacementDeliveryFixture().target,
                decisions: placementFixtureResponse(request).decisions,
                registrationRefused: true,
              ));
    final store = SurfaceAssignmentCredentialStore(
      namespace: 'placements',
      actor: () async => 'actor',
      identityGeneration: () => 0,
      onRetentionRollover: () {},
    );
    SurfaceAssignmentKeyProvider.install(
      key: store.resolve,
      identityGeneration: () => store.generation,
      registration: store.capture,
      confirmedKey: () => store.currentHandle,
      refuseRegistration: store.refuse,
    );
    // A handle confirmed before the service lost it.
    final handle = 'ic1.${'a' * 64}';
    final attempt = (await store.capture())!;
    final now = DateTime.now().microsecondsSinceEpoch;
    expect(
        await store.confirm(
            attempt: attempt,
            localRequestStartMicros: now,
            credentialHandle: handle,
            expiresAtMicros: now + Duration.microsecondsPerDay,
            serverNowMicros: now),
        isTrue);
    final lines = await mountPaywall(tester);
    expect(requests.single.assignmentKey, handle);
    expect(requests.single.registration, isNull);
    expect(
        lines,
        contains(endsWith("shows its fallback (stale): the service no longer "
            "holds this device's experiment registration. The answer was "
            'dropped. The next mount registers this device again.')));
    await tester.pumpWidget(const SizedBox());
    await mountPaywall(tester);
    expect(requests, hasLength(2));
    expect(requests.last.assignmentKey, isNull);
    expect(requests.last.registration, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a mount disposed while its request is out stays silent',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final release = Completer<void>();
    _configure(requests, delay: release.future);
    final lines = await mountPaywall(tester, dispose: true, release: release);
    expect(requests, hasLength(1));
    expect(lines.where((line) => line.contains('shows its fallback')), isEmpty);
  });

  testWidgets(
      'configure sends generated mounts at once and remembered ones after',
      (tester) async {
    final fixture = readPlacementDeliveryFixture();
    final host = fixture.request.buildContract.contractsByHash.values.first;
    final definitions = <GeneratedPlacementDefinition>[
      for (final name in ['one', 'two']) _paywallDefinition(name, host),
    ];
    final requests = <PlacementBatchRequestV1>[];
    final dynamicMount = PlacementMountBinding(
            definition: () => definitions.first, name: 'seen_card')
        .capture();
    await PlacementDecisionStore(
            scope: SurfaceStoreKey.scopeFor(
                apiKey: 'rs_pk_test',
                environment: 'production',
                baseUrl: 'https://example.com'),
            store: sharedSurfaceArtifactStore)
        .remember(dynamicMount.mount, dynamicMount.host, () => true);
    _configure(requests, surfaces: definitions);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await _finish(tester);
    await tester.pumpWidget(const SizedBox());
    expect(
        requests.map((request) => (
              request.mode,
              request.assignmentKey,
              request.registration,
              request.heldAssignments.length,
              [for (final mount in request.mounts) mount.key.slug].join(','),
            )),
        [
          (PlacementBatchModeV1.prefetch, null, null, 0, 'one,two'),
          (PlacementBatchModeV1.prefetch, null, null, 0, 'seen_card'),
        ]);
    expect(requests.last.buildContract.mounts, hasLength(3));
    expect(requests.last.buildContract.contractsByHash, hasLength(1));
  });

  testWidgets('configure forgets remembered generated mounts it no longer has',
      (tester) async {
    final fixture = readPlacementDeliveryFixture();
    final host = fixture.request.buildContract.contractsByHash.values.first;
    final kept = _paywallDefinition('kept', host);
    final removed = _paywallDefinition('removed', host);
    final store = PlacementDecisionStore(
        scope: SurfaceStoreKey.scopeFor(
            apiKey: 'rs_pk_test',
            environment: 'production',
            baseUrl: 'https://example.com'),
        store: sharedSurfaceArtifactStore);
    for (final binding in [
      PlacementMountBinding(definition: () => removed),
      PlacementMountBinding(definition: () => removed, name: 'seen_card'),
    ]) {
      final captured = binding.capture();
      await store.remember(captured.mount, captured.host, () => true);
    }
    final requests = <PlacementBatchRequestV1>[];
    _configure(requests, surfaces: [kept]);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await _finish(tester);
    await tester.pumpWidget(const SizedBox());
    // A named mount is not the build's to declare, so it stays.
    expect(requests.expand((request) => request.mounts).map((m) => m.key.slug),
        ['kept', 'seen_card']);
    expect(requests.last.buildContract.mounts, hasLength(2));
    expect(
        (await store.readAhead())
            .mounts
            .where((known) => known.mount.key.isGeneratedDefault)
            .map((known) => known.mount.key.slug),
        isNot(contains('removed')));
  });

  testWidgets(
      'prefetch reports the app widgets a listed flow installs, before any '
      'step builds', (tester) async {
    final document = flows.childScreenFlow(text: 'Journey').document;
    final flow = SurfaceFlowRef<Map<String, Object?>>(
        id: document.flow,
        version: document.version,
        minClient: 1,
        surface: Surface.onboarding,
        decodeResult: (value) => value,
        vocabulary: const SurfaceVocabulary(libraries: [
          RestageWidgetLibraryRegistration.constant(
              library: WidgetLibrary.custom('acme.ui'),
              capabilityVersion: 1,
              generatedVersion: 2,
              widgets: []),
        ]));
    final definition = GeneratedPlacementDefinition(
        defaultSurface: flow,
        defaultSurfaceLocator: DeliverySurfaceLocatorV1(
            surfaceType: DeliverySurfaceTypeId('onboarding'),
            slug: document.flow,
            family: const DeliveryFamilySelectorV1.general()),
        key: PlacementKeyV1.generatedDefault(
            surfaceType: DeliverySurfaceTypeId('onboarding'),
            slug: document.flow),
        hostContract: _flowHost(document).host,
        vocabulary: SurfaceVocabulary.none);
    final requests = <PlacementBatchRequestV1>[];
    _configure(requests, surfaces: [definition]);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await _finish(tester);
    await tester.pumpWidget(const SizedBox());
    expect(requests.single.mode, PlacementBatchModeV1.prefetch);
    expect(
        requests.single.buildContract.installedCapability.installedLibraries
            .map((library) => (library.namespace, library.generated)),
        contains(('acme.ui', 2)));
  });

  testWidgets(
      'dynamic paywall mount posts its named binding and renders selected content',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    _configure(requests);
    final host = readPlacementDeliveryFixture()
        .request
        .buildContract
        .contractsByHash
        .values
        .first;
    final definition = _paywallDefinition('original', host);
    await tester.pumpWidget(MaterialApp(
        home: RestagePaywall(
            id: 'original',
            placementBinding: PlacementMountBinding(
                definition: () => definition, name: 'home_card'),
            fallbackBuilder: (_) => const Text('Original'))));
    await _finish(tester);
    final rendered = find.text('Welcome').evaluate().length;
    final originals = find.text('Original').evaluate().length;
    await tester.pumpWidget(const SizedBox());
    expect(rendered, 1,
        reason: 'requests: ${requests.length}, originals: $originals');
    expect(requests, hasLength(1));
    expect(requests.single.mounts.single.key.slug, 'home_card');
    expect(requests.single.mode, PlacementBatchModeV1.mount);
    expect(originals, 0);
    final keys = await sharedSurfaceArtifactStore.keys();
    expect(
        keys.where((key) => key.surfaceType == 'placementMount'), hasLength(1));
  });

  testWidgets('an unhosted paywall default adopts a pushed publication',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final channel = _PlacementPushChannel();
    var hosted = false;
    _configure(requests,
        liveRefresh: {SurfaceRefreshTrigger.updateChannel},
        updateChannel: channel,
        respond: (request) => hosted
            ? placementFixtureResponse(request)
            : _watchedFallback(request));
    final host = readPlacementDeliveryFixture()
        .request
        .buildContract
        .contractsByHash
        .values
        .first;
    final definition = _paywallDefinition('original', host);
    try {
      await tester.pumpWidget(MaterialApp(
          home: RestagePaywall(
              id: 'original',
              placementBinding:
                  PlacementMountBinding(definition: () => definition),
              fallbackBuilder: (_) => const Text('Original'))));
      await _finish(tester);
      expect(find.text('Welcome'), findsNothing);
      expect(requests, hasLength(1));
      final scope = channel.controllers.keys.single;
      expect(scope.root.placement!.key, definition.key);
      hosted = true;
      channel.controllers[scope]!.add(scope);
      await _finish(tester);
      expect(requests, hasLength(2));
      expect(find.text('Welcome'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  SurfaceFitRequirementV1 screenRequirement() =>
      SurfaceFitRequirementV1.fromJson({
        ...readPlacementDeliveryFixture()
            .response
            .decisions
            .whereType<PlacementBatchAvailableV1>()
            .first
            .publicDelivery
            .fitRequirement
            .toJson(),
        'hosting': {
          'contentKind': 'single',
          'allowedPresentations': ['inline', 'presented']
        }
      });

  testWidgets('a screen adopts a pushed publication from its compiled fallback',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final channel = _PlacementPushChannel();
    final resolutions = <SurfaceResolutionReport>[];
    var hosted = false;
    _configure(requests,
        liveRefresh: {SurfaceRefreshTrigger.updateChannel},
        updateChannel: channel,
        onSurfaceResolution: resolutions.add,
        respond: (request) => hosted
            ? placementFixtureResponse(request,
                requirement: screenRequirement(),
                family:
                    DeliveryFamilySelectorV1.screenContract(contractVersion: 1))
            : _watchedFallback(request));
    try {
      await tester.pumpWidget(const MaterialApp(
          home: native.NativeNoticeSurface.atPlacement(
              'notice_slot', 'Notice original', 3)));
      await _finish(tester);
      expect(find.text('Notice original'), findsOneWidget);
      expect(requests, hasLength(1));
      expect(resolutions.single.source, SurfaceResolutionSource.bundled);
      expect(resolutions.single.reason, 'unavailable');
      final scope = channel.controllers.keys.single;
      expect(scope.root.placement!.key.slug, 'notice_slot');
      hosted = true;
      channel.controllers[scope]!.add(scope);
      await _finish(tester);
      await tester.pumpAndSettle();
      expect(requests, hasLength(2));
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('Notice original'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('an empty screen fallback still reports its placement',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    _configure(requests, respond: _watchedFallback);
    final reports = <PlacementDiscoveryReportV1>[];
    PlacementDiscovery.instance.configure(
        installedCapability: currentInstalledCapability,
        platform: 'android',
        report: (report) async {
          reports.add(report);
          return true;
        });
    try {
      await tester.pumpWidget(MaterialApp(
          home: native.NativeNoticeSurface.atPlacement(
              'notice_slot',
              'Notice original',
              3,
              null,
              null,
              null,
              null,
              null,
              (_) => const SizedBox.shrink())));
      await _finish(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Notice original'), findsNothing);
      expect(reports.last.mounts.single.key.slug, 'notice_slot');
      // The empty fallback is shown content, so it reports bounds.
      expect(reports.last.bounds, hasLength(1));
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
    }
  });

  testWidgets('forty mounts built in one frame send one request',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    _configure(requests,
        respond: (request) => placementFixtureResponse(request,
            requirement: screenRequirement(),
            family:
                DeliveryFamilySelectorV1.screenContract(contractVersion: 1)));
    try {
      await tester.pumpWidget(MaterialApp(
          home: SingleChildScrollView(
              child: Column(children: [
        for (var i = 0; i < 40; i++)
          native.NativeNoticeSurface.atPlacement(
              'notice_slot_$i', 'Notice original $i', 3),
      ]))));
      await _finish(tester);
      final mounts =
          requests.where((sent) => sent.mode == PlacementBatchModeV1.mount);
      expect(mounts, hasLength(1));
      expect(mounts.single.mounts, hasLength(40));
      expect(find.text('Welcome'), findsNWidgets(40));
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a mount whose callback throws fails alone in its batch',
      (tester) async {
    _configure([]);
    final refusing = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient((_) async => http.Response.bytes(
            PlacementBatchRefusedV1(
                    reason: PlacementBatchRefusalReasonV1.invalidAuthority)
                .canonicalBytes,
            400)));
    Restage.debugRestageRpcClient = refusing;
    addTearDown(refusing.close);
    final fixture = readPlacementDeliveryFixture().request;
    final registry = Restage.placementRegistry!;
    for (final mount in fixture.mounts) {
      registry.remember((
        mount: mount,
        host: fixture.buildContract.contractsByHash[mount.hostContractHash]!
      ));
    }
    final refused = <PlacementBatchRefusalReasonV1>[];
    await tester.runAsync(() async {
      final failing = registry.fetchMount(fixture.mounts.first,
          sendAssignmentKey: false,
          publicationGuard: () => true,
          onRefused: (_) => throw StateError('host callback'));
      final other = registry.fetchMount(fixture.mounts.last,
          sendAssignmentKey: false,
          publicationGuard: () => true,
          onRefused: refused.add);
      await expectLater(failing, throwsA(isA<StateError>()));
      expect(await other, isNull);
    });
    expect(refused, [PlacementBatchRefusalReasonV1.invalidAuthority]);
  });

  testWidgets('a late server fallback reason still reaches the host',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final resolutions = <SurfaceResolutionReport>[];
    final response = Completer<void>();
    _configure(requests,
        delay: response.future,
        onSurfaceResolution: resolutions.add,
        respond: _watchedFallback);
    try {
      await tester.pumpWidget(const MaterialApp(
          home: native.NativeNoticeSurface.atPlacement(
              'notice_slot', 'Notice original', 3)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Notice original'), findsOneWidget);
      expect(resolutions, isEmpty);
      response.complete();
      await _finish(tester);
      expect(resolutions.single.source, SurfaceResolutionSource.bundled);
      expect(resolutions.single.surface, 'native_notice');
      expect(resolutions.single.reason, 'unavailable');
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a late server fallback after held content reports it as held',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final resolutions = <SurfaceResolutionReport>[];
    var hosted = true;
    Completer<void>? response;
    _configure(requests,
        delayEach: () => response?.future ?? Future<void>.value(),
        onSurfaceResolution: resolutions.add,
        respond: (request) => hosted
            ? placementFixtureResponse(request,
                requirement: screenRequirement(),
                family:
                    DeliveryFamilySelectorV1.screenContract(contractVersion: 1))
            : _watchedFallback(request));
    try {
      await tester.pumpWidget(const MaterialApp(
          home: native.NativeNoticeSurface.atPlacement(
              'notice_slot', 'Notice original', 3)));
      await _finish(tester);
      await tester.pumpAndSettle();
      expect(find.text('Welcome'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      resolutions.clear();

      hosted = false;
      response = Completer<void>();
      await tester.pumpWidget(const MaterialApp(
          home: native.NativeNoticeSurface.atPlacement(
              'notice_slot', 'Notice original', 3)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('Welcome'), findsOneWidget);
      expect(resolutions.single.source, SurfaceResolutionSource.holdLastGood);
      expect(resolutions.single.reason, isNull);
      response.complete();
      await _finish(tester);
      expect(resolutions, hasLength(2));
      expect(resolutions.last.source, SurfaceResolutionSource.holdLastGood);
      expect(resolutions.last.reason, 'unavailable');
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  group('a paint receipt', () {
    void enableReceipts() => SurfaceDeliveryReceiptBatch.instance
      ..enabled = true
      ..deviceSource = () async => (platform: 'android', appBuild: 42);

    Widget paywall() {
      final host = readPlacementDeliveryFixture()
          .request
          .buildContract
          .contractsByHash
          .values
          .first;
      final definition = _paywallDefinition('original', host);
      return MaterialApp(
          home: RestagePaywall(
        id: 'original',
        placementBinding: PlacementMountBinding(
            definition: () => definition, name: 'home_card'),
        fallbackBuilder: (_) => const Text('Original'),
      ));
    }

    testWidgets('content swapped in after the deadline counts for its spot',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      final response = Completer<void>();
      _configure(requests,
          delay: response.future,
          liveRefresh: const {SurfaceRefreshTrigger.appResume});
      enableReceipts();
      try {
        await tester.pumpWidget(paywall());
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Original'), findsOneWidget);
        response.complete();
        await _finish(tester);
        expect(find.text('Welcome'), findsOneWidget);
        final receipt = (await SurfaceDeliveryReceiptBatch.instance.drain())
            .entries()
            .single
            .receipt;
        expect(receipt.source, SurfaceResolutionSource.fresh);
        expect(receipt.outcome, SurfaceDeliveryReceiptOutcome.painted);
        expect(receipt.attribution?.placementKey?.slug, 'home_card');
        expect(
            receipt.attribution?.resolutionKind, MountResolutionKindV1.hosted);
      } finally {
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a flow swapped in after the deadline counts for its spot',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      final response = Completer<void>();
      final selected = flows.childScreenFlow(text: 'Hosted generated flow');
      final document = selected.document
          .copyWith(flow: 'selected_generated_journey', version: 9);
      _configure(requests,
          delay: response.future,
          liveRefresh: const {SurfaceRefreshTrigger.appResume},
          payload: FlowSurfacePayload(
              flowDocument: document,
              screenBlobs: selected.screenBlobs,
              requiredLibraries: []),
          requirement: SurfaceFitRequirementV1(
              hosting: SurfaceHostingRequirementV1(
                  contentKind: SurfaceContentKindV1.flow,
                  allowedPresentations: {SurfacePresentationV1.inline}),
              requiredContext: const SurfaceScreenHostDataSchema.empty(),
              emittedEvents: SurfaceScreenEventSchema(events: []),
              capabilities:
                  CapabilityManifest(builtInFloor: 3, requiredLibraries: []),
              requiredVocabulary: WidgetVocabulary(widgetNames: {
                'restage.core:Text',
                'restage.core:GestureDetector'
              }),
              flowBoundary:
                  FlowHostBoundaryV1.fromDocument(document, signals: {})),
          family: const DeliveryFamilySelectorV1.general());
      enableReceipts();
      try {
        await tester.pumpWidget(const MaterialApp(
            home: native.NativeClassFlowSurface.atPlacement('journey_slot')));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(find.text('Preferences original'), findsOneWidget);
        response.complete();
        await _finish(tester);
        expect(find.text('Hosted generated flow'), findsOneWidget);
        final receipt = (await SurfaceDeliveryReceiptBatch.instance.drain())
            .entries()
            .where((entry) =>
                entry.receipt.source == SurfaceResolutionSource.fresh)
            .single
            .receipt;
        expect(receipt.outcome, SurfaceDeliveryReceiptOutcome.painted);
        expect(receipt.attribution?.placementKey?.slug, 'journey_slot');
      } finally {
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('held content shown before the answer says it was pending',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      Completer<void>? held;
      _configure(requests, delayEach: () async => held?.future);
      enableReceipts();
      try {
        await tester.pumpWidget(paywall());
        await _finish(tester);
        await SurfaceDeliveryReceiptBatch.instance.drain();
        await tester.pumpWidget(const SizedBox());
        held = Completer<void>();
        await tester.pumpWidget(paywall());
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Welcome'), findsOneWidget);
        final receipt = (await SurfaceDeliveryReceiptBatch.instance.drain())
            .entries()
            .single
            .receipt;
        expect(receipt.source, SurfaceResolutionSource.holdLastGood);
        expect(receipt.reason, SurfaceDeliveryReceiptReason.pending);
        expect(receipt.attribution?.placementKey?.slug, 'home_card');
        held.complete();
        await _finish(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('a fallback the service decided', () {
    Future<List<SurfaceDeliveryReceipt>> fallbacks() async => [
          for (final entry
              in (await SurfaceDeliveryReceiptBatch.instance.drain())
                  .counts
                  .keys)
            if (entry.outcome == SurfaceDeliveryReceiptOutcome.fallback) entry,
        ];

    void enableReceipts() => SurfaceDeliveryReceiptBatch.instance
      ..enabled = true
      ..deviceSource = () async => (platform: 'android', appBuild: 42);

    Widget slot() => MaterialApp(
        home: RestagePlacement(
            id: 'slow_card', fallbackBuilder: (_) => const Text('Original')));

    testWidgets('counts one view with the signed decision', (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      _configure(requests,
          respond: (request) => _watchedFallback(request,
              fallbackReceipt: 'rpf1.k.claims.mac',
              selectedSurface: DeliverySurfaceLocatorV1(
                  surfaceType: DeliverySurfaceTypeId('paywall'),
                  slug: 'promo',
                  family: const DeliveryFamilySelectorV1.general())));
      enableReceipts();
      try {
        await tester.pumpWidget(MaterialApp(
            home: RestagePlacement.forSurface(
                surfaceType: Surface.paywall,
                surfaceId: 'promo',
                fallbackBuilder: (_) => const Text('Original'))));
        await _finish(tester);
        expect(find.text('Original'), findsOneWidget);
        final receipts = await fallbacks();
        expect(receipts, hasLength(1));
        expect(receipts.single.routingSelectionReceipt, 'rpf1.k.claims.mac');
        expect(receipts.single.publishedVersion, 0);
        expect(receipts.single.surfaceType, Surface.paywall);
        expect(receipts.single.surfaceSlug, 'promo');
        expect(receipts.single.source, SurfaceResolutionSource.bundled);
        expect(receipts.single.routeId, '');
      } finally {
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a spot names the surface its build cannot show',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      _configure(requests,
          respond: (request) => _watchedFallback(request,
              fallbackReceipt: 'rpf1.k.claims.mac',
              selectedSurface: DeliverySurfaceLocatorV1(
                  surfaceType: DeliverySurfaceTypeId('paywall'),
                  slug: 'annual-upgrade',
                  family: const DeliveryFamilySelectorV1.general()),
              routeId: 'annual-push',
              reason: PlacementBatchRefusalReasonV1.incompatible));
      enableReceipts();
      try {
        await tester.pumpWidget(slot());
        await _finish(tester);
        final receipt = (await fallbacks()).single;
        expect((receipt.surfaceType, receipt.surfaceSlug, receipt.routeId),
            (Surface.paywall, 'annual-upgrade', 'annual-push'));
        expect(receipt.reason, SurfaceDeliveryReceiptReason.unsupported);
      } finally {
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a spot with no surface files under the placement alone',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      _configure(requests,
          respond: (request) =>
              _watchedFallback(request, fallbackReceipt: 'rpf1.k.claims.mac'));
      enableReceipts();
      try {
        await tester.pumpWidget(slot());
        await _finish(tester);
        final receipt = (await fallbacks()).single;
        expect(receipt.surfaceType, isNull);
        expect(receipt.toJson(1), containsPair('surfaceType', ''));
        expect(receipt.toJson(1), containsPair('surfaceSlug', ''));
      } finally {
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('counts a decision that arrives after the deadline',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      final response = Completer<void>();
      _configure(requests,
          delay: response.future,
          respond: (request) =>
              _watchedFallback(request, fallbackReceipt: 'rpf1.k.claims.mac'));
      enableReceipts();
      try {
        await tester.pumpWidget(slot());
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Original'), findsOneWidget);
        response.complete();
        await _finish(tester);
        expect(await fallbacks(), hasLength(1));
      } finally {
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a fallback replaced by content is not counted later',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      _configure(requests,
          respond: (request) => request.mode != PlacementBatchModeV1.mount
              ? placementFixtureResponse(request)
              : switch (requests
                  .where((sent) => sent.mode == PlacementBatchModeV1.mount)
                  .length) {
                  1 => _watchedFallback(request),
                  2 => placementFixtureResponse(request),
                  _ => _watchedFallback(request,
                      fallbackReceipt: 'rpf1.k.claims.mac'),
                });
      enableReceipts();
      try {
        await tester.pumpWidget(slot());
        await _finish(tester);
        expect(find.text('Original'), findsOneWidget);
        await Restage.reloadSurfaces();
        await _finish(tester);
        expect(find.text('Welcome'), findsOneWidget);
        await Restage.reloadSurfaces();
        await _finish(tester);
        expect(
            requests.where((sent) => sent.mode == PlacementBatchModeV1.mount),
            hasLength(3));
        expect(find.text('Welcome'), findsOneWidget);
        expect(await fallbacks(), isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a fallback shown while a fetch waits counts on its answer',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      final first = Completer<void>();
      _configure(requests,
          delayEach: () async {
            if (requests.length == 1) await first.future;
          },
          respond: (request) => requests.length == 1
              ? _watchedFallback(request)
              : _watchedFallback(request,
                  fallbackReceipt: 'rpf1.k.claims.mac'));
      enableReceipts();
      final host = readPlacementDeliveryFixture()
          .request
          .buildContract
          .contractsByHash
          .values
          .first;
      final resolver = PlacementPaywallResolver(
          registry: Restage.placementRegistry!,
          declaration: PlacementMountBinding(
              definition: () => _paywallDefinition('queued', host)).capture(),
          id: 'queued',
          originalResolver: const UnavailablePlacementPaywallResolver());
      final key = resolver.storeKey;
      var settled = 0;
      resolver
          .fresh(key, sendAssignmentKey: false)
          .whenComplete(() => settled++);
      resolver
          .fresh(key, sendAssignmentKey: false)
          .whenComplete(() => settled++);
      // The mount shows its fallback while the second fetch waits.
      resolver.hostFallbackShown(key);
      first.complete();
      await _finish(tester);
      expect(settled, 2);
      expect(requests, hasLength(2));
      expect(await fallbacks(), hasLength(1));
    });

    testWidgets('a fallback with no decision counts nowhere', (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      final response = Completer<void>();
      _configure(requests, delay: response.future, respond: _watchedFallback);
      enableReceipts();
      try {
        await tester.pumpWidget(slot());
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Original'), findsOneWidget);
        expect(await fallbacks(), isEmpty);
        // An unsigned answer counts nothing either.
        response.complete();
        await _finish(tester);
        expect(await fallbacks(), isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  testWidgets('a screen keeps its fallback after the user drags it',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final channel = _PlacementPushChannel();
    var hosted = false;
    _configure(requests,
        liveRefresh: {SurfaceRefreshTrigger.updateChannel},
        updateChannel: channel,
        respond: (request) => hosted
            ? placementFixtureResponse(request,
                requirement: screenRequirement(),
                family:
                    DeliveryFamilySelectorV1.screenContract(contractVersion: 1))
            : _watchedFallback(request));
    try {
      await tester.pumpWidget(const MaterialApp(
          home: native.NativeNoticeSurface.atPlacement(
              'notice_slot', 'Notice original', 3)));
      await _finish(tester);
      await tester.drag(find.text('Notice original'), const Offset(0, 80));
      final scope = channel.controllers.keys.single;
      hosted = true;
      channel.controllers[scope]!.add(scope);
      await _finish(tester);
      expect(find.text('Notice original'), findsOneWidget);
      expect(find.text('Welcome'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a plain tap does not hold a screen on its fallback',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final channel = _PlacementPushChannel();
    var hosted = false;
    _configure(requests,
        liveRefresh: {SurfaceRefreshTrigger.updateChannel},
        updateChannel: channel,
        respond: (request) => hosted
            ? placementFixtureResponse(request,
                requirement: screenRequirement(),
                family:
                    DeliveryFamilySelectorV1.screenContract(contractVersion: 1))
            : _watchedFallback(request));
    try {
      await tester.pumpWidget(const MaterialApp(
          home: native.NativeNoticeSurface.atPlacement(
              'notice_slot', 'Notice original', 3)));
      await _finish(tester);
      await tester.tap(find.text('Notice original'));
      final scope = channel.controllers.keys.single;
      hosted = true;
      channel.controllers[scope]!.add(scope);
      await _finish(tester);
      expect(find.text('Notice original'), findsNothing);
      expect(find.text('Welcome'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('source badges label compiled and delivered content',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final channel = _PlacementPushChannel();
    var hosted = false;
    _configure(requests,
        liveRefresh: {SurfaceRefreshTrigger.updateChannel},
        updateChannel: channel,
        showSourceBadges: true,
        respond: (request) => hosted
            ? placementFixtureResponse(request,
                requirement: screenRequirement(),
                family:
                    DeliveryFamilySelectorV1.screenContract(contractVersion: 1))
            : _watchedFallback(request));
    try {
      await tester.pumpWidget(const MaterialApp(
          home: native.NativeNoticeSurface.atPlacement(
              'notice_slot', 'Notice original', 3)));
      await _finish(tester);
      expect(find.text('compiled'), findsOneWidget);
      final scope = channel.controllers.keys.single;
      hosted = true;
      channel.controllers[scope]!.add(scope);
      await _finish(tester);
      await tester.pumpAndSettle();
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^delivered r\d+$')), findsOneWidget);
      expect(find.text('compiled'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'after an app update a published design reading a value where the new '
      'build no longer computes it shows the original', (tester) async {
    final base = (readPlacementDeliveryFixture().response.decisions.first
            as PlacementBatchAvailableV1)
        .publicDelivery
        .fitRequirement;
    // The design reads `_hT` in the arm of return 1.
    final requirement = SurfaceFitRequirementV1.fromJson({
      ...base.toJson(),
      'layoutReads': SurfaceLayoutReadsV1(values: {
        '_hT': [
          {
            '_hB': SurfaceLayoutArmV1.oneOf({1})
          },
        ],
      }).toJson(),
    });
    final fixtureHost = readPlacementDeliveryFixture()
        .request
        .buildContract
        .contractsByHash
        .values
        .first;
    // The build computes `_hT` in the return [index] takes.
    SurfaceHostContractV1 build(int index) => SurfaceHostContractV1.fromJson({
          ...fixtureHost.toJson(),
          'layouts': SurfaceLayoutsV1(domains: {
            '_hB': {0, 1},
          }, values: {
            '_hT': {
              '_hB': {index},
            },
          }).toJson(),
        });
    final lines = <String>[];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
    Future<String> mount(SurfaceHostContractV1 host) async {
      final definition = _paywallDefinition('original', host);
      await tester.pumpWidget(MaterialApp(
          home: RestagePaywall(
        id: 'original',
        placementBinding: PlacementMountBinding(
            definition: () => definition, name: 'home_card'),
        fallbackBuilder: (_) => const Text('Original'),
      )));
      await _finish(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      final shown = find.text('Welcome').evaluate().isNotEmpty
          ? 'Welcome'
          : find.text('Original').evaluate().isNotEmpty
              ? 'Original'
              : 'nothing';
      await tester.pumpWidget(const SizedBox());
      return shown;
    }

    final requests = <PlacementBatchRequestV1>[];
    _configure(requests,
        respond: (request) =>
            placementFixtureResponse(request, requirement: requirement));
    expect(await mount(build(1)), 'Welcome');
    // The updated app computes `_hT` only in return 0. Its new host contract
    // keys a new stored decision, so the design is fetched and checked again.
    resetPlacementFallbackLog();
    _configure(requests,
        respond: (request) =>
            placementFixtureResponse(request, requirement: requirement));
    final updated = await mount(build(0));
    debugPrint = print;
    expect(updated, 'Original');
    expect(lines.where((line) => line.contains('unproducedHostField:_hT')),
        isNotEmpty,
        reason: lines.join('\n'));
  });

  testWidgets('a decision this build cannot render names what it lacks',
      (tester) async {
    final lines = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
    final screen = screenRequirement();
    final vocabulary = screen.requiredVocabulary;
    _configure(<PlacementBatchRequestV1>[],
        respond: (request) => placementFixtureResponse(request,
            requirement: SurfaceFitRequirementV1.fromJson({
              ...screen.toJson(),
              'requiredVocabulary': WidgetVocabulary(
                      widgetNames: {...vocabulary.widgetNames, 'acme.ui:Badge'},
                      iconCodePoints: vocabulary.iconCodePoints)
                  .toJson(),
            }),
            family:
                DeliveryFamilySelectorV1.screenContract(contractVersion: 1)));
    try {
      await tester.pumpWidget(const MaterialApp(
          home: native.NativeNoticeSurface.atPlacement(
              'notice_slot', 'Notice original', 3)));
      await _finish(tester);
      expect(find.text('Notice original'), findsOneWidget);
    } finally {
      debugPrint = previous;
      await tester.pumpWidget(const SizedBox());
    }
    expect(
        lines.where((line) => line.contains('(unsupported)')),
        [
          '[restage] placement named:notice_slot shows its fallback '
              '(unsupported): the published `welcome` r9 draws `Badge` from '
              "`acme.ui`, which this build's `acme.ui` doesn't include. "
              'Update the package that provides `acme.ui`, or annotate '
              '`Badge` with `@RestageWidget`, then run `dart run '
              'build_runner build`. See https://docs.restage.dev/authoring/'
              'custom-widgets#3-declare-exact-library-ownership'
        ],
        reason: lines.join('\n'));
  });

  for (final paywall in [false, true]) {
    testWidgets(
        'a late answer kept for the next mount reports the compiled render '
        '(${paywall ? 'paywall' : 'screen'})', (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      final resolutions = <SurfaceResolutionReport>[];
      final response = Completer<void>();
      _configure(requests,
          delay: response.future,
          onSurfaceResolution: resolutions.add,
          respond: paywall
              ? null
              : (request) => placementFixtureResponse(request,
                  requirement: screenRequirement(),
                  family: DeliveryFamilySelectorV1.screenContract(
                      contractVersion: 1)));
      final host = readPlacementDeliveryFixture()
          .request
          .buildContract
          .contractsByHash
          .values
          .first;
      final definition = _paywallDefinition('original', host);
      try {
        await tester.pumpWidget(MaterialApp(
            home: paywall
                ? RestagePaywall(
                    id: 'original',
                    placementBinding: PlacementMountBinding(
                        definition: () => definition, name: 'home_card'),
                    fallbackBuilder: (_) => const Text('Original'))
                : const native.NativeNoticeSurface.atPlacement(
                    'notice_slot', 'Original', 3)));
        await tester.pump(const Duration(milliseconds: 400));
        expect(resolutions, isEmpty);
        response.complete();
        await _finish(tester);
        expect(find.text('Original'), findsOneWidget);
        expect(resolutions.map((r) => (r.source, r.reason)),
            [(SurfaceResolutionSource.bundled, 'pending')]);
      } finally {
        await tester.pumpWidget(const SizedBox());
      }
    });
  }

  testWidgets('a source badge names delivered content that arrived late',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final requests = <PlacementBatchRequestV1>[];
    final response = Completer<void>();
    _configure(requests,
        showSourceBadges: true,
        delay: response.future,
        respond: (request) => placementFixtureResponse(request,
            requirement: screenRequirement(),
            family:
                DeliveryFamilySelectorV1.screenContract(contractVersion: 1)));
    try {
      await tester.pumpWidget(const MaterialApp(
          home: native.NativeNoticeSurface.atPlacement(
              'notice_slot', 'Notice original', 3)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Notice original'), findsOneWidget);
      expect(find.text('compiled'), findsOneWidget);
      response.complete();
      await _finish(tester);
      // The compiled original stays; the badge says what is waiting.
      expect(find.text('Notice original'), findsOneWidget);
      expect(find.text('compiled · r9 next mount'), findsOneWidget);
      expect(
          find.bySemanticsLabel('Showing the compiled screen. Version r9 '
              'arrived after it painted and shows on the next mount.'),
          findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    }
  });

  testWidgets('a paywall badge names delivered content that arrived late',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final requests = <PlacementBatchRequestV1>[];
    final response = Completer<void>();
    _configure(requests, showSourceBadges: true, delay: response.future);
    final host = readPlacementDeliveryFixture()
        .request
        .buildContract
        .contractsByHash
        .values
        .first;
    final definition = _paywallDefinition('original', host);
    try {
      await tester.pumpWidget(MaterialApp(
          home: RestagePaywall(
              id: 'original',
              placementBinding: PlacementMountBinding(
                  definition: () => definition, name: 'home_card'),
              fallbackBuilder: (_) => const Text('Original'))));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('compiled'), findsOneWidget);
      response.complete();
      await _finish(tester);
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('compiled · r9 next mount'), findsOneWidget);
      expect(
          find.bySemanticsLabel('Showing the compiled screen. Version r9 '
              'arrived after it painted and shows on the next mount.'),
          findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    }
  });

  testWidgets('a paywall adopts a pushed flow from its settled fallback',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final selected = flows.childScreenFlow(text: 'Selected journey');
    final document =
        selected.document.copyWith(flow: 'selected_journey', version: 9);
    final payload = FlowSurfacePayload(
        flowDocument: document,
        screenBlobs: selected.screenBlobs,
        requiredLibraries: []);
    final boundary = FlowHostBoundaryV1.fromDocument(document, signals: {});
    final host = SurfaceHostContractV1(
        hosting: const SurfaceHostingV1(
            contentKind: SurfaceContentKindV1.flow,
            presentation: SurfacePresentationV1.inline),
        providedContext: const SurfaceScreenHostDataSchema.empty(),
        handledEvents: SurfaceScreenEventSchema(events: []),
        flowBoundary: boundary);
    final requirement = SurfaceFitRequirementV1(
        hosting: SurfaceHostingRequirementV1(
            contentKind: SurfaceContentKindV1.flow,
            allowedPresentations: {SurfacePresentationV1.inline}),
        requiredContext: const SurfaceScreenHostDataSchema.empty(),
        emittedEvents: SurfaceScreenEventSchema(events: []),
        capabilities:
            CapabilityManifest(builtInFloor: 3, requiredLibraries: []),
        requiredVocabulary: WidgetVocabulary(
            widgetNames: {'restage.core:Text', 'restage.core:GestureDetector'}),
        flowBoundary: boundary);
    final channel = _PlacementPushChannel();
    var hosted = false;
    _configure(requests,
        liveRefresh: {SurfaceRefreshTrigger.updateChannel},
        updateChannel: channel,
        respond: (request) => hosted
            ? placementFixtureResponse(request,
                payload: payload,
                requirement: requirement,
                family: const DeliveryFamilySelectorV1.general(),
                watch: (delivery) => PlacementDeliveryWatchV1(
                        decisionIdentityDigest: CanonicalDigest('e' * 64),
                        channels: [
                          for (final scope in delivery.dependencyClosure)
                            PlacementDeliveryWatchChannelV1(
                                scope: scope, token: _watchToken)
                        ]))
            : _watchedFallback(request));
    final definition = _paywallDefinition('original', host);
    final flowView =
        find.byWidgetPredicate((widget) => widget is RestageFlowView);
    try {
      await tester.pumpWidget(MaterialApp(
          home: RestagePaywall(
              id: 'original',
              placementBinding:
                  PlacementMountBinding(definition: () => definition),
              fallbackBuilder: (_) => const Text('Original'))));
      await _finish(tester);
      expect(find.text('Original'), findsOneWidget);
      final scope = channel.controllers.keys.single;
      hosted = true;
      channel.controllers[scope]!.add(scope);
      await _finish(tester);
      expect(requests, hasLength(2));
      expect(find.text('Selected journey'), findsOneWidget);
      expect(find.text('Original'), findsNothing);
      final painted = tester.state(flowView);
      // An unchanged push neither stages nor replaces the painted flow.
      for (final scope in channel.controllers.keys) {
        channel.controllers[scope]!.add(scope);
      }
      await tester.pump();
      expect(flowView, findsOneWidget);
      await _finish(tester);
      expect(requests.length, greaterThan(2));
      expect(flowView, findsOneWidget);
      expect(tester.state(flowView), same(painted));
      expect(find.text('Selected journey'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'a watched fallback renews its socket without resolving after a drop',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final channel = _ReconnectingChannel();
    _configure(requests,
        liveRefresh: {SurfaceRefreshTrigger.updateChannel},
        updateChannel: channel,
        respond: _watchedFallback);
    final host = readPlacementDeliveryFixture()
        .request
        .buildContract
        .contractsByHash
        .values
        .first;
    final definition = _paywallDefinition('original', host);
    try {
      await tester.pumpWidget(MaterialApp(
          home: RestagePaywall(
              id: 'original',
              placementBinding:
                  PlacementMountBinding(definition: () => definition),
              fallbackBuilder: (_) => const Text('Original'))));
      await _finish(tester);
      expect(find.text('Original'), findsOneWidget);
      expect(requests, hasLength(1));
      final scope = channel.subscriptions.keys.single;
      // A token expiry and a socket drop, then ten quiet minutes.
      await channel.drop(scope);
      await _finish(tester);
      await channel.drop(scope);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(seconds: 10));
      }
      expect(requests.where((r) => r.mode == PlacementBatchModeV1.mount),
          hasLength(1));
      expect(requests.where((r) => r.mode == PlacementBatchModeV1.refresh),
          hasLength(2));
      expect(channel.reconnects, 2);
      expect(find.text('Original'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a resolve that renews the fallback token resubscribes its watch',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final channel = _ReconnectingChannel();
    _configure(requests,
        liveRefresh: {SurfaceRefreshTrigger.updateChannel},
        updateChannel: channel,
        respond: (request) => _watchedFallback(request,
            token: requests.length == 1 ? _watchToken : _renewedWatchToken));
    final host = readPlacementDeliveryFixture()
        .request
        .buildContract
        .contractsByHash
        .values
        .first;
    final definition = _paywallDefinition('original', host);
    try {
      await tester.pumpWidget(MaterialApp(
          home: RestagePaywall(
              id: 'original',
              placementBinding:
                  PlacementMountBinding(definition: () => definition),
              fallbackBuilder: (_) => const Text('Original'))));
      await _finish(tester);
      final scope = channel.subscriptions.keys.single;
      channel.subscriptions[scope]!.controller.add(scope);
      await _finish(tester);
      expect(requests, hasLength(2));
      expect(
          channel.watches.map((watch) => watch!.channels.single.token).toList(),
          [_watchToken, _renewedWatchToken]);
      expect(find.text('Original'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  for (final screen in [false, true]) {
    testWidgets(
        'generated ${screen ? 'screen' : 'paywall'} wrapper owns its presented first paint across rebuilds',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      final requirement = SurfaceFitRequirementV1.fromJson({
        ...readPlacementDeliveryFixture()
            .response
            .decisions
            .whereType<PlacementBatchAvailableV1>()
            .first
            .publicDelivery
            .fitRequirement
            .toJson(),
        'hosting': {
          'contentKind': 'single',
          'allowedPresentations': ['inline', 'presented']
        }
      });
      _configure(requests,
          requirement: requirement,
          family: screen
              ? DeliveryFamilySelectorV1.screenContract(contractVersion: 1)
              : const DeliveryFamilySelectorV1.general());
      final receipts = SurfaceDeliveryReceiptBatch.instance
        ..enabled = true
        ..deviceSource = () async => (platform: 'android', appBuild: 42);
      late BuildContext hostContext;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        hostContext = context;
        return const Text('Home');
      })));
      late PlacementPresentationController presentation;
      final pending =
          Restage.presentPlacement(hostContext, builder: (context, controller) {
        presentation = controller;
        return screen
            ? const native.NativeNoticeSurface.atPlacement(
                'notice_slot', 'Notice original', 3)
            : const native.NativeOfferSurface.atPlacement('offer_slot');
      });
      try {
        await _finish(tester);
        await tester.pumpAndSettle();
        expect(find.text('Welcome'), findsOneWidget);
        expect(requests, hasLength(1));
        final request = requests.single;
        final mount = request.mounts.single;
        expect(mount.key.slug, screen ? 'notice_slot' : 'offer_slot');
        expect(
            request.buildContract.contractsByHash[mount.hostContractHash]!
                .hosting.presentation,
            SurfacePresentationV1.presented);
        final firstPaint = await receipts.drain();
        expect(firstPaint.presentations, 1);
        expect(firstPaint.entries().single.receipt.outcome,
            SurfaceDeliveryReceiptOutcome.painted);
        expect(firstPaint.entries().single.receipt.attribution!.placementKey,
            mount.key);
        final wrapper = screen
            ? find.byType(native.NativeNoticeSurface)
            : find.byType(native.NativeOfferSurface);
        final actualHost = screen
            ? find.byWidgetPredicate((widget) => widget is RestageScreen)
            : find.byType(RestagePaywall);
        final hostState = tester.state(actualHost);
        tester.element(wrapper).markNeedsBuild();
        await _finish(tester);
        expect(tester.state(actualHost), same(hostState));
        expect(find.text('Welcome'), findsOneWidget);
        expect((await receipts.drain()).isEmpty, isTrue,
            reason: 'An unchanged generated getter must not open a new paint.');
        expect(requests, hasLength(1));
        expect(
            Restage.firstLaunchWaitFor(""), const Duration(milliseconds: 300));
      } finally {
        presentation.close();
        await tester.pumpAndSettle();
        await pending;
        await tester.pumpWidget(const SizedBox());
      }
    });
  }

  testWidgets(
      'emitted flow accepts hosted first paint and renews only for a changed name',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final failures = <Object>[];
    final selected = flows.childScreenFlow(text: 'Hosted generated flow');
    final document = selected.document
        .copyWith(flow: 'selected_generated_journey', version: 9);
    final payload = FlowSurfacePayload(
        flowDocument: document,
        screenBlobs: selected.screenBlobs,
        requiredLibraries: []);
    final requirement = SurfaceFitRequirementV1(
        hosting: SurfaceHostingRequirementV1(
            contentKind: SurfaceContentKindV1.flow,
            allowedPresentations: {SurfacePresentationV1.inline}),
        requiredContext: const SurfaceScreenHostDataSchema.empty(),
        emittedEvents: SurfaceScreenEventSchema(events: []),
        capabilities:
            CapabilityManifest(builtInFloor: 3, requiredLibraries: []),
        requiredVocabulary: WidgetVocabulary(
            widgetNames: {'restage.core:Text', 'restage.core:GestureDetector'}),
        flowBoundary: FlowHostBoundaryV1.fromDocument(document, signals: {}));
    _configure(requests,
        payload: payload,
        requirement: requirement,
        family: const DeliveryFamilySelectorV1.general());
    final receipts = SurfaceDeliveryReceiptBatch.instance
      ..enabled = true
      ..deviceSource = () async => (platform: 'android', appBuild: 42);
    final completions = <native.NativeClassResult>[];
    Widget build(String placement) => MaterialApp(
        home: native.NativeClassFlowSurface.atPlacement(placement,
            onFlowUnavailable: failures.add, onComplete: completions.add));
    try {
      await tester.pumpWidget(build('journey_slot'));
      final host = find.byType(native.NativeClassFlowSurface);
      final hostState = tester.state(host);
      final emitted = tester.widget<native.NativeClassFlowSurface>(host);
      expect(emitted.placementBinding, isNot(same(emitted.placementBinding)));
      await _finish(tester);
      expect(find.text('Hosted generated flow'), findsOneWidget,
          reason: failures.toString());
      expect(find.text('Preferences original'), findsNothing);
      expect(requests, hasLength(1), reason: failures.toString());
      expect(requests.single.mounts.single.key.slug, 'journey_slot');
      final firstPaint = await receipts.drain();
      expect(firstPaint.presentations, 1);
      final firstReceipt = firstPaint.entries().single.receipt;
      expect(firstReceipt.outcome, SurfaceDeliveryReceiptOutcome.painted);
      expect(firstReceipt.attribution!.placementKey!.slug, 'journey_slot');
      await tester.pumpWidget(build('journey_slot'));
      await _finish(tester);
      expect(tester.state(host), same(hostState));
      expect(find.text('Hosted generated flow'), findsOneWidget);
      expect((await receipts.drain()).isEmpty, isTrue);
      expect(requests, hasLength(1));
      await tester.pumpWidget(build('changed_journey'));
      await _finish(tester);
      expect(tester.state(host), same(hostState));
      expect(requests, hasLength(2));
      expect(requests.last.mounts.single.key.slug, 'changed_journey');
      final changedPaint = await receipts.drain();
      expect(changedPaint.presentations, 1);
      final changedReceipt = changedPaint.entries().single.receipt;
      expect(changedReceipt.outcome, SurfaceDeliveryReceiptOutcome.painted);
      expect(changedReceipt.attribution!.placementKey!.slug, 'changed_journey');
      expect(changedReceipt.attribution!.mountNonceDigest,
          isNot(firstReceipt.attribution!.mountNonceDigest));
      expect(Restage.firstLaunchWaitFor(""), const Duration(milliseconds: 300));
      await tester.tap(find.text('Hosted generated flow'));
      await _finish(tester);
      expect(completions, hasLength(1));
      expect(failures, isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'screen host consumes the selected own family through its original race',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final original = stringScreenFixture(
        slug: 'original_notice', schema: SurfaceScreenEventSchema(events: []));
    final channel = _PlacementWatchRecorder();
    var contract = 7;
    var digest = CanonicalDigest('c' * 64);
    var failRefresh = false;
    _configure(requests,
        liveRefresh: {
          SurfaceRefreshTrigger.appResume,
          SurfaceRefreshTrigger.updateChannel
        },
        updateChannel: channel, respond: (request) {
      if (failRefresh) throw StateError('The refresh is unavailable.');
      return placementFixtureResponse(request,
          family: DeliveryFamilySelectorV1.screenContract(
              contractVersion: contract),
          watch: (delivery) => PlacementDeliveryWatchV1(
                  decisionIdentityDigest: digest,
                  channels: [
                    for (final scope in delivery.dependencyClosure)
                      PlacementDeliveryWatchChannelV1(
                          scope: scope, token: _watchToken)
                  ]));
    });
    final host = readPlacementDeliveryFixture()
        .request
        .buildContract
        .contractsByHash
        .values
        .first;
    final definition = GeneratedPlacementDefinition(
        defaultSurface: original.ref,
        defaultSurfaceLocator: DeliverySurfaceLocatorV1(
            surfaceType: DeliverySurfaceTypeId('general'),
            slug: original.ref.slug,
            family: DeliveryFamilySelectorV1.screenContract(
                contractVersion: original.ref.contractVersion)),
        key: PlacementKeyV1.generatedDefault(
            surfaceType: DeliverySurfaceTypeId('general'),
            slug: original.ref.slug),
        hostContract: host,
        vocabulary: SurfaceVocabulary.none);
    await tester.pumpWidget(MaterialApp(
        home: RestageScreen(
            screen: original.ref,
            placementBinding:
                PlacementMountBinding(definition: () => definition),
            fallbackBuilder: (_) => const Text('Original'))));
    await _finish(tester);
    expect(requests, hasLength(1));
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Original'), findsNothing);
    expect(requests.single.mounts.single.defaultSurface!.family.contractVersion,
        1);
    failRefresh = true;
    await SurfaceRefreshRegistry.instance.onAppResumed();
    await _finish(tester);
    final retained = find.text('Welcome').evaluate().length;
    failRefresh = false;
    contract = 8;
    digest = CanonicalDigest('d' * 64);
    await SurfaceRefreshRegistry.instance.onAppResumed();
    await _finish(tester);
    final updated = find.text('Welcome').evaluate().length;
    final accepted = channel.watches.toList();
    await tester.pumpWidget(const SizedBox());
    Restage.debugReset();
    expect(retained, 1);
    expect(updated, 1);
    expect(requests.map((request) => request.mode).toList(), [
      PlacementBatchModeV1.mount,
      PlacementBatchModeV1.refresh,
      PlacementBatchModeV1.mount,
      PlacementBatchModeV1.refresh,
      PlacementBatchModeV1.mount
    ]);
    expect(accepted.last.decisionIdentityDigest, digest);
    expect(accepted.last.channels.map((entry) => entry.scope.family),
        contains(DeliveryFamilySelectorV1.screenContract(contractVersion: 8)));
  });

  testWidgets('mounted expiry uses local fallback without another request',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    var now = DateTime.utc(2026, 10, 4, 12);
    _configure(requests, now: () => now, cacheValidityOverrides: {
      'contentExpiresAtMicros':
          now.add(const Duration(seconds: 1)).microsecondsSinceEpoch
    });
    await tester.pumpWidget(MaterialApp(
        home: RestagePlacement(
            id: 'expiring_card',
            fallbackBuilder: (_) => const Text('Original'))));
    await _finish(tester);
    final selectedBefore = find.text('Welcome').evaluate().length;
    now = now.add(const Duration(seconds: 1));
    await SurfaceRefreshRegistry.instance.onAppResumed();
    await _finish(tester);
    final originalAfter = find.text('Original').evaluate().length;
    final selectedAfter = find.text('Welcome').evaluate().length;
    await tester.pumpWidget(const SizedBox());
    expect(selectedBefore, 1);
    expect(originalAfter, 1);
    expect(selectedAfter, 0);
    expect(requests, hasLength(1));
    expect(requests.single.mounts.single.surfaceType, isNull);
  });

  testWidgets(
      'a hiding paywall keeps its content when it expires with no original',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    var now = DateTime.utc(2026, 10, 4, 12);
    _configure(requests, now: () => now, cacheValidityOverrides: {
      'contentExpiresAtMicros':
          now.add(const Duration(seconds: 1)).microsecondsSinceEpoch
    });
    final contract = SurfaceHostContractV1(
        hosting: const SurfaceHostingV1(
            contentKind: SurfaceContentKindV1.single,
            presentation: SurfacePresentationV1.inline),
        providedContext: const SurfaceScreenHostDataSchema.empty(),
        handledEvents: SurfaceScreenEventSchema(events: const []));
    await tester.pumpWidget(MaterialApp(
        home: RestagePaywall(
            id: 'expiring_card',
            placementBinding: PlacementMountBinding.request(
                mount: PlacementMountRequestV1(
                    key: PlacementKeyV1.named(slug: 'expiring_card'),
                    hostContractHash: contract.contentHash),
                hostContract: contract))));
    await _finish(tester);
    final before = find.text('Welcome').evaluate().length;
    now = now.add(const Duration(seconds: 1));
    await SurfaceRefreshRegistry.instance.onAppResumed();
    await _finish(tester);
    final after = find.text('Welcome').evaluate().length;
    await tester.pumpWidget(const SizedBox());
    expect(before, 1);
    expect(after, 1);
  });

  testWidgets(
      'an expired flow placement the user went forward and back in keeps its '
      'content', (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    var now = DateTime.utc(2026, 10, 4, 12);
    final welcome = flows.screenBlob('Welcome', 'next');
    final profile = flows.screenBlob('Profile', 'back');
    final document =
        flows.flowDocument(flow: 'expiring_journey', screenHashes: {
      'welcome': FlowContentHash.compute(welcome),
      'profile': FlowContentHash.compute(profile),
    });
    final boundary = FlowHostBoundaryV1.fromDocument(document, signals: {});
    _configure(requests,
        now: () => now,
        payload: FlowSurfacePayload(
            flowDocument: document,
            screenBlobs: {'welcome': welcome, 'profile': profile},
            requiredLibraries: []),
        requirement: SurfaceFitRequirementV1(
            hosting: SurfaceHostingRequirementV1(
                contentKind: SurfaceContentKindV1.flow,
                allowedPresentations: {SurfacePresentationV1.inline}),
            requiredContext: const SurfaceScreenHostDataSchema.empty(),
            emittedEvents: SurfaceScreenEventSchema(events: []),
            capabilities:
                CapabilityManifest(builtInFloor: 3, requiredLibraries: []),
            requiredVocabulary: WidgetVocabulary(widgetNames: {
              'restage.core:Text',
              'restage.core:GestureDetector'
            }),
            flowBoundary: boundary),
        family: const DeliveryFamilySelectorV1.general(),
        cacheValidityOverrides: {
          'contentExpiresAtMicros':
              now.add(const Duration(seconds: 5)).microsecondsSinceEpoch
        });
    const flow = SurfaceFlowRef<void>(
        id: 'expiring_journey',
        version: 1,
        minClient: 3,
        surface: Surface.onboarding,
        decodeResult: _decodeVoid);
    final definition = GeneratedPlacementDefinition(
        defaultSurface: flow,
        defaultSurfaceLocator: DeliverySurfaceLocatorV1(
            surfaceType: DeliverySurfaceTypeId('onboarding'),
            slug: flow.id,
            family: const DeliveryFamilySelectorV1.general()),
        key: PlacementKeyV1.generatedDefault(
            surfaceType: DeliverySurfaceTypeId('onboarding'), slug: flow.id),
        hostContract: SurfaceHostContractV1(
            hosting: const SurfaceHostingV1(
                contentKind: SurfaceContentKindV1.flow,
                presentation: SurfacePresentationV1.inline),
            providedContext: const SurfaceScreenHostDataSchema.empty(),
            handledEvents: SurfaceScreenEventSchema(events: []),
            flowBoundary: boundary),
        vocabulary: SurfaceVocabulary.none);
    Future<void> fire(String name) async {
      tester.widget<RemoteWidget>(find.byType(RemoteWidget).last).onEvent!(
          name, const <String, Object?>{});
      await tester.pump(const Duration(seconds: 1));
      await _finish(tester);
    }

    try {
      await tester.pumpWidget(MaterialApp(
          home: RestageFlowGraph<void>(
              flow: flow,
              placementBinding:
                  PlacementMountBinding(definition: () => definition),
              fallbackBuilder: (_) => const Text('Original'),
              errorBuilder: (_, __) => const Text('Error'))));
      await _finish(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Welcome'), findsOneWidget);
      // Events without a pointer: progress without interaction.
      await fire('next');
      expect(find.text('Profile'), findsOneWidget);
      await fire('back');
      expect(find.text('Welcome'), findsOneWidget);
      now = now.add(const Duration(seconds: 5));
      await SurfaceRefreshRegistry.instance.onAppResumed();
      await _finish(tester);
      // The load advanced, so expiry never swaps it out.
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('Error'), findsNothing);
      expect(find.text('Original'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a flow that shows its error builder reports its painted spot',
      (tester) async {
    Restage.configure(analyticsEnabled: false, measurementEnabled: false);
    final reports = <PlacementDiscoveryReportV1>[];
    PlacementDiscovery.instance.configure(
        installedCapability: currentInstalledCapability,
        platform: 'android',
        report: (report) async {
          reports.add(report);
          return true;
        });
    const flow = SurfaceFlowRef<void>(
        id: 'fallback_journey',
        version: 1,
        minClient: 3,
        surface: Surface.onboarding,
        decodeResult: _decodeVoid);
    final document = flows.childScreenFlow().document;
    final definition = GeneratedPlacementDefinition(
        defaultSurface: flow,
        defaultSurfaceLocator: DeliverySurfaceLocatorV1(
            surfaceType: DeliverySurfaceTypeId('onboarding'),
            slug: flow.id,
            family: const DeliveryFamilySelectorV1.general()),
        key: PlacementKeyV1.generatedDefault(
            surfaceType: DeliverySurfaceTypeId('onboarding'), slug: flow.id),
        hostContract: SurfaceHostContractV1(
            hosting: const SurfaceHostingV1(
                contentKind: SurfaceContentKindV1.flow,
                presentation: SurfacePresentationV1.inline),
            providedContext: const SurfaceScreenHostDataSchema.empty(),
            handledEvents: SurfaceScreenEventSchema(events: []),
            flowBoundary:
                FlowHostBoundaryV1.fromDocument(document, signals: {})),
        vocabulary: SurfaceVocabulary.none);
    final gate = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: Column(children: [
      RestageFlowGraph<void>(
          flow: flow,
          placementBinding: PlacementMountBinding(definition: () => definition),
          resolver: _GatedUnavailableFlow(gate.future),
          loadingBuilder: (_) => const SizedBox(
              key: ValueKey('loading'),
              height: 100,
              width: 100,
              child: ColoredBox(color: Colors.white)),
          fallbackBuilder: (_) => const Expanded(child: Text('Flow original')),
          errorBuilder: (_, __) => const Expanded(child: Text('Flow error'))),
    ])));
    await tester.pump();
    // A drag on the loading state is progress.
    await tester.drag(
        find.byKey(const ValueKey('loading')), const Offset(0, 30));
    gate.complete();
    await _finish(tester);
    await tester.pump(const Duration(milliseconds: 251));
    await tester.pump(const Duration(milliseconds: 251));
    final shown = find.text('Flow error').evaluate().length;
    final painted = reports.isEmpty ? null : reports.last;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
    expect(shown, 1);
    expect(
        painted?.mounts.map((mount) => mount.key.slug), ['fallback_journey']);
    expect(painted?.bounds, hasLength(1));
  });

  testWidgets('screen and flow fallbacks report their painted placements',
      (tester) async {
    Restage.configure(analyticsEnabled: false, measurementEnabled: false);
    final reports = <PlacementDiscoveryReportV1>[];
    PlacementDiscovery.instance.configure(
        installedCapability: currentInstalledCapability,
        platform: 'android',
        report: (report) async {
          reports.add(report);
          return true;
        });
    final original = stringScreenFixture(
        slug: 'fallback_notice', schema: SurfaceScreenEventSchema(events: []));
    final host = readPlacementDeliveryFixture()
        .request
        .buildContract
        .contractsByHash
        .values
        .first;
    final screenDefinition = GeneratedPlacementDefinition(
        defaultSurface: original.ref,
        defaultSurfaceLocator: DeliverySurfaceLocatorV1(
            surfaceType: DeliverySurfaceTypeId('general'),
            slug: original.ref.slug,
            family:
                DeliveryFamilySelectorV1.screenContract(contractVersion: 1)),
        key: PlacementKeyV1.generatedDefault(
            surfaceType: DeliverySurfaceTypeId('general'),
            slug: original.ref.slug),
        hostContract: host,
        vocabulary: SurfaceVocabulary.none);
    const flow = SurfaceFlowRef<void>(
        id: 'fallback_journey',
        version: 1,
        minClient: 3,
        surface: Surface.onboarding,
        decodeResult: _decodeVoid);
    final document = flows.childScreenFlow().document;
    final flowHost = SurfaceHostContractV1(
        hosting: const SurfaceHostingV1(
            contentKind: SurfaceContentKindV1.flow,
            presentation: SurfacePresentationV1.inline),
        providedContext: const SurfaceScreenHostDataSchema.empty(),
        handledEvents: SurfaceScreenEventSchema(events: []),
        flowBoundary: FlowHostBoundaryV1.fromDocument(document, signals: {}));
    final flowDefinition = GeneratedPlacementDefinition(
        defaultSurface: flow,
        defaultSurfaceLocator: DeliverySurfaceLocatorV1(
            surfaceType: DeliverySurfaceTypeId('onboarding'),
            slug: flow.id,
            family: const DeliveryFamilySelectorV1.general()),
        key: PlacementKeyV1.generatedDefault(
            surfaceType: DeliverySurfaceTypeId('onboarding'), slug: flow.id),
        hostContract: flowHost,
        vocabulary: SurfaceVocabulary.none);
    await tester.pumpWidget(MaterialApp(
        home: Column(children: [
      RestageScreen(
          screen: original.ref,
          placementBinding:
              PlacementMountBinding(definition: () => screenDefinition),
          resolver: const _UnavailableScreen(),
          fallbackBuilder: (_) =>
              const Expanded(child: Text('Screen fallback'))),
      RestageFlowGraph<void>(
          flow: flow,
          placementBinding:
              PlacementMountBinding(definition: () => flowDefinition),
          resolver: const _UnavailableFlow(),
          fallbackBuilder: (_) => const Expanded(child: Text('Flow fallback'))),
    ])));
    await _finish(tester);
    await tester.pump(const Duration(milliseconds: 251));
    await tester.pump(const Duration(milliseconds: 251));
    final frame = PlacementDiscovery.instance
        .captureFrame(view: tester.binding.renderViews.single);
    final screenFallback = find.text('Screen fallback').evaluate().length;
    final flowFallback = find.text('Flow fallback').evaluate().length;
    final captured = frame.mounts.length;
    final painted = reports.isEmpty ? null : reports.last;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
    expect(screenFallback, 1);
    expect(flowFallback, 1);
    expect(captured, 2);
    expect(painted?.mounts.map((mount) => mount.key.slug).toSet(),
        {'fallback_notice', 'fallback_journey'});
    expect(painted?.bounds, hasLength(2));
  });

  for (final milliseconds in [300, 550]) {
    testWidgets(
        'placement preserves the configured $milliseconds ms fallback deadline',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      final response = Completer<void>();
      _configure(requests,
          deadline: Duration(milliseconds: milliseconds),
          delay: response.future);
      await tester.pumpWidget(MaterialApp(
          home: RestagePlacement(
              id: 'slow_card',
              loadingBuilder: (_) => const Text('Loading'),
              fallbackBuilder: (_) => const Text('Original'))));
      await tester.pump(Duration(milliseconds: milliseconds - 1));
      expect(find.text('Original'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.text('Original'), findsOneWidget);
      response.complete();
      await _finish(tester);
      expect(
          requests
              .where((request) => request.mode == PlacementBatchModeV1.mount),
          hasLength(1));
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('Welcome'), findsNothing);
    });
  }

  testWidgets(
      'flow host keeps its typed boundary while loading selected root identity',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final failures = <FlowUnavailableError>[];
    final selected = flows.childScreenFlow(text: 'Selected journey');
    final document =
        selected.document.copyWith(flow: 'selected_journey', version: 9);
    final payload = FlowSurfacePayload(
        flowDocument: document,
        screenBlobs: selected.screenBlobs,
        requiredLibraries: []);
    final boundary = FlowHostBoundaryV1.fromDocument(document, signals: {});
    final host = SurfaceHostContractV1(
        hosting: const SurfaceHostingV1(
            contentKind: SurfaceContentKindV1.flow,
            presentation: SurfacePresentationV1.inline),
        providedContext: const SurfaceScreenHostDataSchema.empty(),
        handledEvents: SurfaceScreenEventSchema(events: []),
        flowBoundary: boundary);
    final requirement = SurfaceFitRequirementV1(
        hosting: SurfaceHostingRequirementV1(
            contentKind: SurfaceContentKindV1.flow,
            allowedPresentations: {SurfacePresentationV1.inline}),
        requiredContext: const SurfaceScreenHostDataSchema.empty(),
        emittedEvents: SurfaceScreenEventSchema(events: []),
        capabilities:
            CapabilityManifest(builtInFloor: 3, requiredLibraries: []),
        requiredVocabulary: WidgetVocabulary(
            widgetNames: {'restage.core:Text', 'restage.core:GestureDetector'}),
        flowBoundary: boundary);
    _configure(requests,
        payload: payload,
        requirement: requirement,
        family: const DeliveryFamilySelectorV1.general());
    const original = SurfaceFlowRef<void>(
        id: 'original_journey',
        version: 1,
        minClient: 3,
        surface: Surface.onboarding,
        decodeResult: _decodeVoid);
    final definition = GeneratedPlacementDefinition(
        defaultSurface: original,
        defaultSurfaceLocator: DeliverySurfaceLocatorV1(
            surfaceType: DeliverySurfaceTypeId('onboarding'),
            slug: original.id,
            family: const DeliveryFamilySelectorV1.general()),
        key: PlacementKeyV1.generatedDefault(
            surfaceType: DeliverySurfaceTypeId('onboarding'),
            slug: original.id),
        hostContract: host,
        vocabulary: SurfaceVocabulary.none);
    await tester.pumpWidget(MaterialApp(
        home: RestageFlowGraph<void>(
            flow: original,
            onFlowUnavailable: failures.add,
            placementBinding: PlacementMountBinding(
                definition: () => definition, name: 'journey_slot'),
            fallbackBuilder: (_) => const Text('Original journey'))));
    await _finish(tester);
    final selectedCount = find.text('Selected journey').evaluate().length;
    final originalCount = find.text('Original journey').evaluate().length;
    await tester.pumpWidget(const SizedBox());
    expect(requests, hasLength(1), reason: failures.toString());
    expect(requests.single.mounts.single.key.slug, 'journey_slot');
    expect(selectedCount, 1, reason: failures.toString());
    expect(originalCount, 0);
  });

  testWidgets('an unhosted flow default adopts a pushed publication',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final failures = <FlowUnavailableError>[];
    final selected = flows.childScreenFlow(text: 'Selected journey');
    final document =
        selected.document.copyWith(flow: 'selected_journey', version: 9);
    final payload = FlowSurfacePayload(
        flowDocument: document,
        screenBlobs: selected.screenBlobs,
        requiredLibraries: []);
    final boundary = FlowHostBoundaryV1.fromDocument(document, signals: {});
    final host = SurfaceHostContractV1(
        hosting: const SurfaceHostingV1(
            contentKind: SurfaceContentKindV1.flow,
            presentation: SurfacePresentationV1.inline),
        providedContext: const SurfaceScreenHostDataSchema.empty(),
        handledEvents: SurfaceScreenEventSchema(events: []),
        flowBoundary: boundary);
    final requirement = SurfaceFitRequirementV1(
        hosting: SurfaceHostingRequirementV1(
            contentKind: SurfaceContentKindV1.flow,
            allowedPresentations: {SurfacePresentationV1.inline}),
        requiredContext: const SurfaceScreenHostDataSchema.empty(),
        emittedEvents: SurfaceScreenEventSchema(events: []),
        capabilities:
            CapabilityManifest(builtInFloor: 3, requiredLibraries: []),
        requiredVocabulary: WidgetVocabulary(
            widgetNames: {'restage.core:Text', 'restage.core:GestureDetector'}),
        flowBoundary: boundary);
    final channel = _PlacementPushChannel();
    var hosted = false;
    _configure(requests,
        liveRefresh: {SurfaceRefreshTrigger.updateChannel},
        updateChannel: channel,
        respond: (request) => hosted
            ? placementFixtureResponse(request,
                payload: payload,
                requirement: requirement,
                family: const DeliveryFamilySelectorV1.general())
            : _watchedFallback(request));
    const original = SurfaceFlowRef<void>(
        id: 'original_journey',
        version: 1,
        minClient: 3,
        surface: Surface.onboarding,
        decodeResult: _decodeVoid);
    final definition = GeneratedPlacementDefinition(
        defaultSurface: original,
        defaultSurfaceLocator: DeliverySurfaceLocatorV1(
            surfaceType: DeliverySurfaceTypeId('onboarding'),
            slug: original.id,
            family: const DeliveryFamilySelectorV1.general()),
        key: PlacementKeyV1.generatedDefault(
            surfaceType: DeliverySurfaceTypeId('onboarding'),
            slug: original.id),
        hostContract: host,
        vocabulary: SurfaceVocabulary.none);
    await tester.pumpWidget(MaterialApp(
        home: RestageFlowGraph<void>(
            flow: original,
            onFlowUnavailable: failures.add,
            placementBinding: PlacementMountBinding(
                definition: () => definition, name: 'journey_slot'),
            fallbackBuilder: (_) => const Text('Original journey'))));
    await _finish(tester);
    expect(find.text('Original journey'), findsOneWidget);
    expect(requests, hasLength(1), reason: failures.toString());
    final scope = channel.controllers.keys.single;
    expect(scope.root.placement!.key.slug, 'journey_slot');
    hosted = true;
    channel.controllers[scope]!.add(scope);
    await _finish(tester);
    final selectedCount = find.text('Selected journey').evaluate().length;
    await tester.pumpWidget(const SizedBox());
    expect(requests, hasLength(2), reason: failures.toString());
    expect(selectedCount, 1, reason: failures.toString());
  });

  testWidgets('a flow placement hosts a typed flow and decodes its result',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final results = <Map<String, Object?>>[];
    final received = <RestageEvent>[];
    final events = <RestageEvent>[];
    final subscription = Restage.events.listen(events.add);
    addTearDown(subscription.cancel);
    final selected = flows.childScreenFlow(text: 'Selected journey');
    final document = selected.document;
    expect(document.deliveryMode, FlowDeliveryMode.typed);
    final served = _flowHost(document);
    _configure(requests,
        payload: FlowSurfacePayload(
            flowDocument: document,
            screenBlobs: selected.screenBlobs,
            requiredLibraries: []),
        requirement: served.requirement,
        family: const DeliveryFamilySelectorV1.general());
    await tester.pumpWidget(MaterialApp(
        home: RestagePlacement.flowForSurface(
            surfaceType: Surface.onboarding,
            surfaceId: 'original_journey',
            contract: served.host,
            onComplete: results.add,
            onEvent: received.add,
            fallbackBuilder: (_) => const Text('Original journey'))));
    await _finish(tester);
    expect(find.text('Selected journey'), findsOneWidget);
    await tester.tap(find.text('Selected journey'));
    await _finish(tester);
    await tester.pumpWidget(const SizedBox());
    expect(requests, hasLength(1));
    expect(requests.single.mounts.single.surfaceType?.value, 'onboarding');
    expect(results, [<String, Object?>{}]);
    expect(received, isNotEmpty);
    expect(received.whereType<FlowStarted>(), hasLength(1));
    expect(events, containsAll(received));
  });

  testWidgets('a paywall flow placement delivers continue to the app',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final events = <RestageEvent>[];
    final received = <RestageEvent>[];
    final subscription = Restage.events.listen(events.add);
    addTearDown(subscription.cancel);
    final offer = flows.screenBlob('Get Plus', 'continue');
    final document = _paywallFlowDocument(offer);
    final served = _flowHost(document);
    _configure(requests,
        payload: FlowSurfacePayload(
            flowDocument: document,
            screenBlobs: {'offer': offer},
            requiredLibraries: []),
        requirement: served.requirement,
        family: const DeliveryFamilySelectorV1.general(),
        flowSurfaceType: 'paywall');
    await tester.pumpWidget(MaterialApp(
        home: RestagePlacement.flowForSurface(
            surfaceType: Surface.paywall,
            surfaceId: 'plus_offer',
            contract: served.host,
            onEvent: received.add,
            fallbackBuilder: (_) => const Text('Original offer'))));
    await _finish(tester);
    expect(find.text('Get Plus'), findsOneWidget);
    await tester.tap(find.text('Get Plus'));
    await _finish(tester);
    await tester.pumpWidget(const SizedBox());
    expect(requests, hasLength(1));
    final custom = events.whereType<PaywallCustomEvent>().single;
    expect(custom.eventName, 'continue');
    expect(custom.paywallId, 'plus_offer');
    expect(received.whereType<PaywallCustomEvent>().single, same(custom));
  });

  test('a paywall flow placement refuses flow-only callbacks', () {
    final document = flows.childScreenFlow().document;
    expect(
        () => RestagePlacement.flowForSurface(
            surfaceType: Surface.paywall,
            surfaceId: 'plus_offer',
            contract: _flowHost(document).host,
            onComplete: (_) {},
            fallbackBuilder: (_) => const SizedBox()),
        throwsArgumentError);
  });

  testWidgets('a named paywall slot hosts a served paywall flow',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final received = <RestageEvent>[];
    final offer = flows.screenBlob('Get Plus', 'continue');
    final document = _paywallFlowDocument(offer);
    final served = _flowHost(document);
    _configure(requests,
        payload: FlowSurfacePayload(
            flowDocument: document,
            screenBlobs: {'offer': offer},
            requiredLibraries: []),
        requirement: served.requirement,
        family: const DeliveryFamilySelectorV1.general(),
        flowSurfaceType: 'paywall');
    await tester.pumpWidget(MaterialApp(
        home: RestagePlacement.flow(
            id: 'upsell_slot',
            surfaceType: Surface.paywall,
            contract: served.host,
            onEvent: received.add,
            fallbackBuilder: (_) => const Text('Original offer'))));
    await _finish(tester);
    await tester.tap(find.text('Get Plus'));
    await _finish(tester);
    await tester.pumpWidget(const SizedBox());
    expect(requests.single.mounts.single.key.slug, 'upsell_slot');
    expect(requests.single.mounts.single.defaultSurface, isNull);
    expect(requests.single.mounts.single.surfaceType?.value, 'paywall');
    expect(
        received.whereType<PaywallCustomEvent>().single.eventName, 'continue');
  });

  testWidgets(
      'a late flow root kept for the next mount reports the compiled render '
      'once', (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final resolutions = <SurfaceResolutionReport>[];
    final response = Completer<void>();
    final selected = flows.childScreenFlow(text: 'Hosted generated flow');
    final document = selected.document
        .copyWith(flow: 'selected_generated_journey', version: 9);
    final served = _flowHost(document);
    _configure(requests,
        delay: response.future,
        onSurfaceResolution: resolutions.add,
        payload: FlowSurfacePayload(
            flowDocument: document,
            screenBlobs: selected.screenBlobs,
            requiredLibraries: []),
        requirement: served.requirement,
        family: const DeliveryFamilySelectorV1.general());
    try {
      await tester.pumpWidget(const MaterialApp(
          home: native.NativeClassFlowSurface.atPlacement('journey_slot')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('Preferences original'), findsOneWidget);
      response.complete();
      await _finish(tester);
      expect(find.text('Preferences original'), findsOneWidget);
      expect(resolutions.map((r) => (r.source, r.reason)),
          [(SurfaceResolutionSource.bundled, null)]);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a named flow slot hosts a served onboarding flow',
      (tester) async {
    final requests = <PlacementBatchRequestV1>[];
    final results = <Map<String, Object?>>[];
    final selected = flows.childScreenFlow(text: 'Selected journey');
    final served = _flowHost(selected.document);
    _configure(requests,
        payload: FlowSurfacePayload(
            flowDocument: selected.document,
            screenBlobs: selected.screenBlobs,
            requiredLibraries: []),
        requirement: served.requirement,
        family: const DeliveryFamilySelectorV1.general());
    await tester.pumpWidget(MaterialApp(
        home: RestagePlacement.flow(
            id: 'journey_slot',
            contract: served.host,
            onComplete: results.add,
            fallbackBuilder: (_) => const Text('Original journey'))));
    await _finish(tester);
    await tester.tap(find.text('Selected journey'));
    await _finish(tester);
    await tester.pumpWidget(const SizedBox());
    expect(requests.single.mounts.single.key.slug, 'journey_slot');
    expect(requests.single.mounts.single.surfaceType?.value, 'onboarding');
    expect(results, [<String, Object?>{}]);
  });

  group('the mounted-surface report', () {
    testWidgets('a screen delivered in the startup batch is reported',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      final requirement = SurfaceFitRequirementV1.fromJson({
        ...readPlacementDeliveryFixture()
            .response
            .decisions
            .whereType<PlacementBatchAvailableV1>()
            .first
            .publicDelivery
            .fitRequirement
            .toJson(),
        'hosting': {
          'contentKind': 'single',
          'allowedPresentations': ['inline', 'presented']
        }
      });
      MountedSurfaceReport.instance =
          MountedSurfaceReport(mirror: (_, __) async {});
      addTearDown(() => MountedSurfaceReport.instance = MountedSurfaceReport());
      void configure() => _configure(requests,
          requirement: requirement,
          family: DeliveryFamilySelectorV1.screenContract(contractVersion: 1));
      configure();
      const host = native.NativeNoticeSurface.atPlacement(
          'notice_slot', 'Notice original', 3);
      await tester.pumpWidget(const MaterialApp(home: host));
      await _finish(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(find.text('Welcome'), findsOneWidget);
      final held = (await tester
          .runAsync(() => MountedSurfaceReport.instance.pending()))!;
      expect(held, hasLength(1));
      expect(held.single.placement, PlacementKeyV1.named(slug: 'notice_slot'));
      await tester.pumpWidget(const SizedBox());

      // The next process reports it on its first request and is answered.
      MountedSurfaceReport.instance =
          MountedSurfaceReport(mirror: (_, __) async {});
      final launches = requests.length;
      configure();
      await tester.pumpWidget(const MaterialApp(home: host));
      await _finish(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(requests.skip(launches).first.mountedSince, held);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an onboarding flow delivered in the startup batch is reported',
        (tester) async {
      final requests = <PlacementBatchRequestV1>[];
      final selected = flows.childScreenFlow(text: 'Selected journey');
      final served = _flowHost(selected.document);
      MountedSurfaceReport.instance =
          MountedSurfaceReport(mirror: (_, __) async {});
      addTearDown(() => MountedSurfaceReport.instance = MountedSurfaceReport());
      void configure() => _configure(requests,
          payload: FlowSurfacePayload(
              flowDocument: selected.document,
              screenBlobs: selected.screenBlobs,
              requiredLibraries: []),
          requirement: served.requirement,
          family: const DeliveryFamilySelectorV1.general());
      Widget host() => RestagePlacement.flow(
          id: 'journey_slot',
          contract: served.host,
          onComplete: (_) {},
          fallbackBuilder: (_) => const Text('Original journey'));
      configure();
      await tester.pumpWidget(MaterialApp(home: host()));
      await _finish(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(find.text('Selected journey'), findsOneWidget);
      final held = (await tester
          .runAsync(() => MountedSurfaceReport.instance.pending()))!;
      expect(held, hasLength(1));
      expect(held.single.placement, PlacementKeyV1.named(slug: 'journey_slot'));
      await tester.pumpWidget(const SizedBox());

      MountedSurfaceReport.instance =
          MountedSurfaceReport(mirror: (_, __) async {});
      final launches = requests.length;
      configure();
      await tester.pumpWidget(MaterialApp(home: host()));
      await _finish(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(requests.skip(launches).first.mountedSince, held);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

FlowDocument _paywallFlowDocument(Uint8List offer) => FlowDocument(
        flow: 'plus_offer',
        version: 1,
        schemaVersion: 1,
        minClient: flows.firstRunFlowRef.minClient,
        initial: 'offer',
        actions: const {},
        screenArtifacts: {
          'offer': ScreenArtifact(
              path: 'offer.rfw',
              version: 1,
              schemaVersion: 1,
              minClient: flows.firstRunFlowRef.minClient,
              contentHash: FlowContentHash.compute(offer))
        },
        states: const {
          'offer': ScreenFlowState(
              screen: 'offer', on: {'skip': FlowTransition.goto('done')}),
          'done': EndFlowState(result: <String, Object?>{}),
        });

({SurfaceHostContractV1 host, SurfaceFitRequirementV1 requirement}) _flowHost(
    FlowDocument document) {
  final boundary = FlowHostBoundaryV1.fromDocument(document, signals: {});
  return (
    host: SurfaceHostContractV1(
        hosting: const SurfaceHostingV1(
            contentKind: SurfaceContentKindV1.flow,
            presentation: SurfacePresentationV1.inline),
        providedContext: const SurfaceScreenHostDataSchema.empty(),
        handledEvents: SurfaceScreenEventSchema(events: []),
        flowBoundary: boundary),
    requirement: SurfaceFitRequirementV1(
        hosting: SurfaceHostingRequirementV1(
            contentKind: SurfaceContentKindV1.flow,
            allowedPresentations: {SurfacePresentationV1.inline}),
        requiredContext: const SurfaceScreenHostDataSchema.empty(),
        emittedEvents: SurfaceScreenEventSchema(events: []),
        capabilities:
            CapabilityManifest(builtInFloor: 3, requiredLibraries: []),
        requiredVocabulary: WidgetVocabulary(
            widgetNames: {'restage.core:Text', 'restage.core:GestureDetector'}),
        flowBoundary: boundary),
  );
}

void _decodeVoid(Map<String, Object?> value) {}

GeneratedPlacementDefinition _paywallDefinition(
        String name, SurfaceHostContractV1 host) =>
    GeneratedPlacementDefinition(
        defaultSurface: PaywallRef(name),
        defaultSurfaceLocator: DeliverySurfaceLocatorV1(
            surfaceType: DeliverySurfaceTypeId('paywall'),
            slug: name,
            family: const DeliveryFamilySelectorV1.general()),
        key: PlacementKeyV1.generatedDefault(
            surfaceType: DeliverySurfaceTypeId('paywall'), slug: name),
        hostContract: host,
        vocabulary: SurfaceVocabulary.none);

void _configure(List<PlacementBatchRequestV1> requests,
    {List<RestageSurfaceRef> surfaces = const [],
    Duration deadline = const Duration(milliseconds: 300),
    Duration? freshWindow,
    Future<void>? delay,
    Future<void> Function()? delayEach,
    SurfacePayload? payload,
    SurfaceFitRequirementV1? requirement,
    DeliveryFamilySelectorV1? family,
    Set<SurfaceRefreshTrigger> liveRefresh = const {},
    SurfaceUpdateChannel? updateChannel,
    void Function(SurfaceResolutionReport)? onSurfaceResolution,
    bool showSourceBadges = false,
    Duration? installDateAfter,
    Duration? gatherAfter,
    PlacementBatchResolvedV1 Function(PlacementBatchRequestV1)? respond,
    DateTime Function()? now,
    Map<String, Object?> cacheValidityOverrides = const {},
    String flowSurfaceType = 'onboarding',
    bool contentUnavailable = false,
    bool analytics = false}) {
  // Set before configure, which builds the registry it reads.
  Restage.debugPlacementNow = now ?? () => DateTime.utc(2026, 10, 4, 12);
  Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://example.com',
      analyticsEnabled: analytics,
      measurementEnabled: false,
      deliveryReceiptsEnabled: false,
      surfaces: surfaces,
      liveRefresh: liveRefresh,
      updateChannel: updateChannel,
      onSurfaceResolution: onSurfaceResolution,
      showSourceBadges: showSourceBadges,
      firstLaunchWait: deadline,
      freshWindow: freshWindow ?? deadline);
  debugResetInstallObservations();
  // As in a fresh process: the install date and the gather's own storage
  // reads answer later.
  Future<SharedPreferences> slow(Duration delay) async {
    await Future<void>.delayed(delay);
    return SharedPreferences.getInstance();
  }

  if (installDateAfter != null) {
    debugResetInstallObservations(
        store: FirstLaunchStore(preferences: () => slow(installDateAfter)));
    configureSurfaceDeliveryObservations();
  }
  debugSetOsVersion(19);
  SurfaceMeteringKeyProvider.clear();
  if (gatherAfter != null) {
    SurfaceMeteringKeyProvider.install(
        store: MeteringTokenStore(prefsProvider: () => slow(gatherAfter)));
  }
  final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((request) async {
        if (contentUnavailable && request.method == 'GET') {
          return http.Response('', 503);
        }
        final artifact = placementFixtureArtifact(request);
        if (artifact != null) return artifact;
        if (request.method != 'POST' ||
            request.url.path != '/sdk/v1/placements/resolve') {
          throw StateError(
              'Unexpected request: ${request.method} ${request.url}');
        }
        final PlacementBatchRequestV1 batch;
        try {
          batch = sentPlacementRequest(request.bodyBytes);
        } on PlacementBuildContractRequired {
          // As the service answers a build it does not hold yet.
          return http.Response('', PlacementBuildContractRequired.status);
        }
        requests.add(batch);
        if (delay != null) await delay;
        if (delayEach != null) await delayEach();
        if (respond != null) {
          return http.Response.bytes(respond(batch).canonicalBytes, 200);
        }
        return http.Response.bytes(
            placementFixtureResponse(batch,
                    payload: payload,
                    requirement: requirement,
                    family: family,
                    cacheValidityOverrides: cacheValidityOverrides,
                    flowSurfaceType: flowSurfaceType)
                .canonicalBytes,
            200);
      }));
  Restage.debugRestageRpcClient = client;
  addTearDown(client.close);
}

Future<void> _finish(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

final class _UnavailableScreen implements SurfaceScreenResolver {
  const _UnavailableScreen();
  @override
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> screen) async =>
      throw const SurfaceScreenUnavailableError(
          reason: SurfaceScreenUnavailableReason.missing,
          message: 'Unavailable');
}

const _watchToken =
    'v2.i5p7lxR3.1767229200.NDI6b25ib2FyZGluZzp3ZWxjb21lLWZsb3c.'
    'kV0gFtXCrtsWdYcIFXaVNEQDQFjXwvrEn4t_WY_KX44';

const _renewedWatchToken =
    'v2.i5p7lxR3.1767232800.NDI6b25ib2FyZGluZzp3ZWxjb21lLWZsb3c.'
    'kV0gFtXCrtsWdYcIFXaVNEQDQFjXwvrEn4t_WY_KX44';

final class _PlacementWatchRecorder implements DeliveryUpdateChannel {
  final watches = <PlacementDeliveryWatchV1>[];
  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) => const Stream.empty();
  @override
  Stream<DeliveryPolicyScopeV1> watchDelivery(DeliveryPolicyScopeV1 scope,
      {PlacementDeliveryWatchV1? watch,
      Future<PlacementRefreshProbeV1> Function()? reconnectProbe}) {
    watches.add(watch!);
    return const Stream.empty();
  }
}

final class _GatedUnavailableFlow implements FlowResolver {
  const _GatedUnavailableFlow(this.gate);
  final Future<void> gate;
  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async {
    await gate;
    throw StateError('Unavailable');
  }
}

final class _UnavailableFlow implements FlowResolver {
  const _UnavailableFlow();
  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async =>
      throw StateError('Unavailable');
}

PlacementBatchResolvedV1 _watchedFallback(PlacementBatchRequestV1 request,
    {String token = _watchToken,
    String? fallbackReceipt,
    DeliverySurfaceLocatorV1? selectedSurface,
    String? routeId,
    PlacementBatchRefusalReasonV1 reason =
        PlacementBatchRefusalReasonV1.unavailable}) {
  final target = readPlacementDeliveryFixture().target;
  final mount = request.mounts.single;
  final descriptor = PlacementMountDescriptorV1(
      placement: PlacementIdentityV1(target: target, key: mount.key),
      hostContractHash: mount.hostContractHash);
  return PlacementBatchResolvedV1(
    request: request,
    expectedTarget: target,
    decisions: [
      PlacementBatchEntryV1.useFallback(descriptor, reason, const [],
          watch: PlacementDeliveryWatchV1(
              decisionIdentityDigest: CanonicalDigest('f' * 64),
              channels: [
                PlacementDeliveryWatchChannelV1(
                    scope: DeliveryPolicyScopeV1(
                        root: DeliveryRootIdentityV1.placement(
                            descriptor.placement),
                        family: const DeliveryFamilySelectorV1.none()),
                    token: token)
              ]),
          fallbackReceipt: fallbackReceipt,
          selectedSurface: selectedSurface,
          routeId: routeId)
    ],
  );
}

final class _PlacementPushChannel implements DeliveryUpdateChannel {
  final controllers =
      <DeliveryPolicyScopeV1, StreamController<DeliveryPolicyScopeV1>>{};
  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) => const Stream.empty();
  @override
  Stream<DeliveryPolicyScopeV1> watchDelivery(DeliveryPolicyScopeV1 scope,
          {PlacementDeliveryWatchV1? watch,
          Future<PlacementRefreshProbeV1> Function()? reconnectProbe}) =>
      (controllers[scope] ??= StreamController.broadcast()).stream;
}

/// Reconnects as the hosted channel does: a renewed watch reconnects quietly;
/// anything else asks for resolution and retries at the backoff cap.
final class _ReconnectingChannel implements DeliveryUpdateChannel {
  final subscriptions = <DeliveryPolicyScopeV1,
      ({
    StreamController<DeliveryPolicyScopeV1> controller,
    Future<PlacementRefreshProbeV1> Function() probe
  })>{};
  final _retries = <DeliveryPolicyScopeV1, Timer>{};
  final watches = <PlacementDeliveryWatchV1?>[];
  var reconnects = 0;

  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) => const Stream.empty();
  @override
  Stream<DeliveryPolicyScopeV1> watchDelivery(DeliveryPolicyScopeV1 scope,
      {PlacementDeliveryWatchV1? watch,
      Future<PlacementRefreshProbeV1> Function()? reconnectProbe}) {
    late final StreamController<DeliveryPolicyScopeV1> controller;
    controller = StreamController(onCancel: () {
      if (identical(subscriptions[scope]?.controller, controller)) {
        subscriptions.remove(scope);
        _retries.remove(scope)?.cancel();
      }
    });
    _retries.remove(scope)?.cancel();
    subscriptions[scope] = (controller: controller, probe: reconnectProbe!);
    watches.add(watch);
    return controller.stream;
  }

  Future<void> drop(DeliveryPolicyScopeV1 scope) async {
    final subscription = subscriptions[scope];
    if (subscription == null) return;
    final probe = await subscription.probe();
    if (!identical(subscriptions[scope], subscription)) return;
    if (probe is PlacementRefreshUnchangedV1 &&
        probe.watch?.decisionIdentityDigest == probe.decisionIdentityDigest) {
      reconnects++;
      return;
    }
    subscription.controller.add(scope);
    _retries[scope] =
        Timer(const Duration(seconds: 60), () => unawaited(drop(scope)));
  }
}

/// A store whose writes take [delay].
final class _FailingRowStore implements SurfaceArtifactStore {
  bool failRows = false;
  final _store = MemorySurfaceArtifactStore();
  @override
  Future<StoredSurface?> read(SurfaceStoreKey key) => _store.read(key);
  @override
  Future<void> write(SurfaceStoreKey key, StoredSurface value) async {
    if (failRows && key.surfaceType == 'placementDecision') {
      throw const FileSystemException('full');
    }
    await _store.write(key, value);
  }

  @override
  Future<void> remove(SurfaceStoreKey key) => _store.remove(key);
  @override
  Future<List<SurfaceStoreKey>> keys() => _store.keys();
  @override
  Future<void> clear() => _store.clear();
}

final class _SlowWriteStore implements SurfaceArtifactStore {
  _SlowWriteStore(this.delay);
  final Duration delay;
  Duration readDelay = Duration.zero;
  Duration keysDelay = Duration.zero;
  final _store = MemorySurfaceArtifactStore();
  @override
  Future<StoredSurface?> read(SurfaceStoreKey key) async {
    await Future<void>.delayed(readDelay);
    return _store.read(key);
  }

  @override
  Future<void> write(SurfaceStoreKey key, StoredSurface value) async {
    await Future<void>.delayed(delay);
    await _store.write(key, value);
  }

  @override
  Future<void> remove(SurfaceStoreKey key) => _store.remove(key);
  @override
  Future<List<SurfaceStoreKey>> keys() async {
    await Future<void>.delayed(keysDelay);
    return _store.keys();
  }

  @override
  Future<void> clear() => _store.clear();
}

/// [utc] as read in a zone [offset] from UTC.
final class _ZonedTime implements DateTime {
  _ZonedTime(this._utc, this.timeZoneOffset);
  final DateTime _utc;
  @override
  final Duration timeZoneOffset;
  DateTime get _wall => _utc.add(timeZoneOffset);
  @override
  String get timeZoneName => 'UTC+${timeZoneOffset.inHours}';
  @override
  bool get isUtc => false;
  @override
  DateTime toUtc() => _utc;
  @override
  DateTime toLocal() => this;
  @override
  int get millisecondsSinceEpoch => _utc.millisecondsSinceEpoch;
  @override
  int get microsecondsSinceEpoch => _utc.microsecondsSinceEpoch;
  @override
  int get year => _wall.year;
  @override
  int get month => _wall.month;
  @override
  int get day => _wall.day;
  @override
  int get hour => _wall.hour;
  @override
  int get minute => _wall.minute;
  @override
  int get second => _wall.second;
  @override
  int get millisecond => _wall.millisecond;
  @override
  int get microsecond => _wall.microsecond;
  @override
  int get weekday => _wall.weekday;
  @override
  DateTime add(Duration duration) =>
      _ZonedTime(_utc.add(duration), timeZoneOffset);
  @override
  DateTime subtract(Duration duration) =>
      _ZonedTime(_utc.subtract(duration), timeZoneOffset);
  @override
  Duration difference(DateTime other) => _utc.difference(other.toUtc());
  @override
  bool isBefore(DateTime other) => _utc.isBefore(other.toUtc());
  @override
  bool isAfter(DateTime other) => _utc.isAfter(other.toUtc());
  @override
  bool isAtSameMomentAs(DateTime other) => _utc.isAtSameMomentAs(other.toUtc());
  @override
  int compareTo(DateTime other) => _utc.compareTo(other.toUtc());
  @override
  String toIso8601String() => _utc.toIso8601String();
}

Map<Object?, Object?> _builtInsOf(PlacementBatchRequestV1 request) =>
    CanonicalJsonCodec.decode(base64Url.decode(
        base64Url.normalize(request.sdkBuiltInsCanonicalBase64!))) as Map;

// A memory store that reads its scopes as release builds do, off the frame
// isolate.
final class _OffIsolateStore
    implements SurfaceArtifactStore, SurfaceArtifactScopeReader {
  /// Holds the read ahead until completed, as a slow disk does.
  Completer<void>? readAheadGate;
  final _store = MemorySurfaceArtifactStore();
  @override
  bool get readsOffIsolate => true;
  @override
  Future<R> readScope<R>(String scope, Set<String> surfaceTypes,
      R Function(StoredScopeRows rows) process) async {
    await readAheadGate?.future;
    return readStoreScope(_store, scope, surfaceTypes, process);
  }

  @override
  Future<StoredSurface?> read(SurfaceStoreKey key) => _store.read(key);
  @override
  Future<void> write(SurfaceStoreKey key, StoredSurface value) =>
      _store.write(key, value);
  @override
  Future<void> remove(SurfaceStoreKey key) => _store.remove(key);
  @override
  Future<List<SurfaceStoreKey>> keys() => _store.keys();
  @override
  Future<void> clear() => _store.clear();
}
