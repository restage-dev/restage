import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/render_deadline.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart'
    show MemorySurfaceArtifactStore;
import 'package:restage/src/flow/flow_resolver.dart' show ActiveArmFlowResolver;
import 'package:restage/src/measurement/bundled_measurement_target_profile_loader.dart';
import 'package:restage/src/measurement/measurement_host_session.dart';
import 'package:restage/src/measurement/measurement_resolved_publication_provenance.dart';
import 'package:restage/src/resolver/resolved_paywall_payload.dart';
import 'package:rfw/formats.dart';

import '../fixtures/compiled_surfaces/native_flow.dart';
import '../measurement/admitted_bundled_publication_fixture.dart';
import '../support/canonical_assignment_fixture.dart';
import '../measurement/measurement_host_construction_test_support.dart';
import '../flow/flow_test_support.dart' as flows;
import '../surface_screen/surface_screen_test_support.dart';
import 'package:restage/src/delivery/raced_surface_resolver.dart';
import 'package:restage/src/delivery/surface_race.dart' show markHeldDecision;
import 'package:restage/src/delivery/surface_artifact_store.dart';

const _wait = Duration(milliseconds: 300);

void _configureFast() =>
    Restage.configure(firstLaunchWait: _wait, freshWindow: _wait);

void main() {
  setUp(Restage.debugReset);
  tearDown(Restage.debugReset);

  group('paywall', () {
    setUp(_configureFast);
    testWidgets('fresh content before the deadline renders', (tester) async {
      final resolver = _PaywallResolver();
      await tester.pumpWidget(_paywall(resolver));
      await tester.pump(const Duration(milliseconds: 100));
      resolver.freshResult.complete(_blob('Fresh'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Fresh'), findsOneWidget);
      expect(resolver.freshCalls.single.$2, isTrue);
      expect(resolver.freshCalls.single.$3, isNotNull);
    });

    testWidgets('the ready local candidate renders at the deadline',
        (tester) async {
      final resolver = _PaywallResolver(local: _blob('Disk'));
      await tester.pumpWidget(_paywall(resolver));
      await tester.pump(const Duration(milliseconds: 299));
      expect(find.text('Disk'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.text('Disk'), findsOneWidget);
    });

    testWidgets('saved content renders at the fresh window, not the first wait',
        (tester) async {
      Restage.configure(
        firstLaunchWait: const Duration(seconds: 1),
        freshWindow: const Duration(milliseconds: 100),
      );
      final saved = _blob('Disk');
      markHeldDecision(saved);
      final resolver = _PaywallResolver(local: saved);
      await tester.pumpWidget(_paywall(resolver));
      await tester.pump(const Duration(milliseconds: 99));
      expect(find.text('Disk'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.text('Disk'), findsOneWidget);
    });

    testWidgets('nothing saved renders its original only at the first wait',
        (tester) async {
      Restage.configure(
        firstLaunchWait: const Duration(seconds: 1),
        freshWindow: const Duration(milliseconds: 100),
      );
      final resolver = _PaywallResolver();
      await tester.pumpWidget(_paywall(resolver));
      await tester.pump(const Duration(milliseconds: 999));
      await tester.pump();
      expect(find.text('Compiled'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.text('Compiled'), findsOneWidget);
    });

    testWidgets('nothing local renders the compiled widget and keeps it',
        (tester) async {
      final events = <RestageEvent>[];
      final resolver = _PaywallResolver();
      await tester.pumpWidget(_paywall(resolver, onEvent: events.add));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('Compiled'), findsOneWidget);
      expect(events.whereType<PaywallLoadFailed>(), isEmpty);

      resolver.freshResult.complete(_blob('Fresh'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Compiled'), findsOneWidget);
      expect(find.text('Fresh'), findsNothing);
    });

    testWidgets('slow storage renders the compiled widget at the deadline',
        (tester) async {
      final resolver = _PaywallResolver(slowStorage: true);
      await tester.pumpWidget(_paywall(resolver));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('Compiled'), findsOneWidget);
    });

    testWidgets('late fresh content swaps in when live refresh is on',
        (tester) async {
      final reports = <SurfaceResolutionReport>[];
      Restage.configure(
          firstLaunchWait: _wait,
          freshWindow: _wait,
          onSurfaceResolution: reports.add);
      final resolver = _PaywallResolver();
      await tester.pumpWidget(_paywall(
        resolver,
        liveRefresh: const {SurfaceRefreshTrigger.appResume},
      ));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('Compiled'), findsOneWidget);

      expect(reports, isEmpty);

      resolver.freshResult.complete(_blob('Fresh'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Fresh'), findsOneWidget);
      expect(reports, hasLength(1));
    });

    testWidgets('a late swap the gate rejects at paint is not reported',
        (tester) async {
      final reports = <SurfaceResolutionReport>[];
      Restage.configure(
          firstLaunchWait: _wait,
          freshWindow: _wait,
          onSurfaceResolution: reports.add);
      final resolver = _PaywallResolver(local: _tappableBlob('Disk'));
      await tester.pumpWidget(_paywall(
        resolver,
        liveRefresh: const {SurfaceRefreshTrigger.appResume},
      ));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('Disk'), findsOneWidget);
      expect(reports, hasLength(1));

      // The swap is staged, then the user taps before it can paint.
      resolver.freshResult.complete(_blob('Fresh'));
      await tester.tap(find.text('Disk'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Disk'), findsOneWidget);
      expect(find.text('Fresh'), findsNothing);
      expect(reports, hasLength(1));
    });

    testWidgets('the key deadline passed to fresh is the render deadline',
        (tester) async {
      final resolver = _PaywallResolver();
      await tester.pumpWidget(_paywall(resolver));
      var keyDeadlinePassed = false;
      unawaited(
          resolver.freshCalls.single.$3!.then((_) => keyDeadlinePassed = true));
      await tester.pump(const Duration(milliseconds: 299));
      expect(keyDeadlinePassed, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      expect(keyDeadlinePassed, isTrue);
    });

    testWidgets('late assigned content never swaps in, even with live refresh',
        (tester) async {
      final resolver = _PaywallResolver(local: _blob('Unassigned'));
      await tester.pumpWidget(_paywall(
        resolver,
        liveRefresh: const {SurfaceRefreshTrigger.appResume},
      ));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('Unassigned'), findsOneWidget);

      final assigned = BlobPaywallPayload(
        attachMeasurementPublicationBindingReference(
          _variant('Assigned arm'),
          null,
          canonicalExperimentAssignment: canonicalAssignmentFixture(),
        ),
      );
      resolver.freshResult.complete(assigned);
      await tester.pump();
      await tester.pump();
      expect(find.text('Assigned arm'), findsNothing);
      expect(find.text('Unassigned'), findsOneWidget);
    });

    testWidgets('a custom resolver is raced as an opaque future',
        (tester) async {
      final resolver = _PendingCustomResolver();
      await tester.pumpWidget(_paywall(resolver));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('Compiled'), findsOneWidget);
    });

    for (final outcome in ['nothing', 'an error']) {
      testWidgets(
          'without a compiled widget a fresh that ends with $outcome fails',
          (tester) async {
        final events = <RestageEvent>[];
        final resolver = _PaywallResolver();
        await tester.pumpWidget(MaterialApp(
          home: RestagePaywall(
            id: 'pro',
            resolver: resolver,
            onEvent: events.add,
            loadingBuilder: (_) => const Text('Loading'),
            errorBuilder: (_, __) => const Text('Error'),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(find.text('Loading'), findsOneWidget);
        if (outcome == 'nothing') {
          resolver.freshResult.complete(null);
        } else {
          resolver.freshResult.completeError(const RestagePaywallError(
            code: RestageErrorCodes.deliveryUnavailable,
            message: 'offline',
          ));
        }
        await tester.pump();
        await tester.pump();
        // No fallback and no original, so the error builder shows.
        expect(find.text('Error'), findsOneWidget);
        expect(events.whereType<PaywallLoadFailed>(), hasLength(1));
      });
    }

    testWidgets('a late fresh render on an empty mount is reported',
        (tester) async {
      final reports = <SurfaceResolutionReport>[];
      Restage.configure(
          firstLaunchWait: _wait,
          freshWindow: _wait,
          onSurfaceResolution: reports.add);
      final resolver = _PaywallResolver();
      await tester.pumpWidget(MaterialApp(
        home: RestagePaywall(id: 'pro', resolver: resolver),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(reports, isEmpty);
      resolver.freshResult.complete(_blob('Late'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Late'), findsOneWidget);
      expect(reports.map((r) => r.surface), ['pro']);
    });

    testWidgets('a mount gone before the race settles reports nothing',
        (tester) async {
      final reports = <SurfaceResolutionReport>[];
      Restage.configure(
          firstLaunchWait: _wait,
          freshWindow: _wait,
          onSurfaceResolution: reports.add);
      final resolver = _PaywallResolver(local: _blob('Disk'));
      await tester.pumpWidget(_paywall(resolver));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(reports, isEmpty);
    });

    testWidgets('without a compiled widget the paywall waits for fresh',
        (tester) async {
      final resolver = _PendingCustomResolver();
      await tester.pumpWidget(MaterialApp(
        home: RestagePaywall(
          id: 'pro',
          resolver: resolver,
          loadingBuilder: (_) => const Text('Loading'),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('Loading'), findsOneWidget);
      resolver.completer.complete(_variant('Late'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Late'), findsOneWidget);
    });

    testWidgets('cacheLastRender has no effect', (tester) async {
      final resolver = _SwitchableCustomResolver();
      Widget mount(Key key) => MaterialApp(
            home: RestagePaywall(
              key: key,
              id: 'pro',
              resolver: resolver,
              // ignore: deprecated_member_use_from_same_package
              cacheLastRender: true,
              errorBuilder: (_, __) => const Text('Error'),
            ),
          );
      await tester.pumpWidget(mount(const ValueKey(1)));
      await tester.pumpAndSettle();
      expect(find.text('First'), findsOneWidget);

      resolver.fail = true;
      await tester.pumpWidget(mount(const ValueKey(2)));
      await tester.pumpAndSettle();
      expect(find.text('First'), findsNothing);
      expect(find.text('Error'), findsOneWidget);
    });
  });

  group('screen', () {
    setUp(_configureFast);
    testWidgets('fresh content before the deadline renders', (tester) async {
      final fixture = stringScreenFixture(text: 'Hosted screen');
      final resolver = _ScreenResolver();
      await tester.pumpWidget(_screen(fixture, resolver));
      await tester.pump(const Duration(milliseconds: 100));
      resolver.freshResult.complete(fixture.hosted());
      await tester.pump();
      await tester.pump();
      expect(find.text('Hosted screen'), findsOneWidget);
      expect(resolver.freshCalls.single.$2, isTrue);
      expect(resolver.freshCalls.single.$3, isNotNull);
    });

    testWidgets('the ready local candidate renders at the deadline',
        (tester) async {
      final fixture = stringScreenFixture(text: 'Stored screen');
      final resolver = _ScreenResolver(local: fixture.bundled());
      await tester.pumpWidget(_screen(fixture, resolver));
      await tester.pump(const Duration(milliseconds: 299));
      expect(find.text('Stored screen'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.text('Stored screen'), findsOneWidget);
    });

    testWidgets('nothing local renders the compiled widget and keeps it',
        (tester) async {
      final fixture = stringScreenFixture(text: 'Hosted screen');
      final resolver = _ScreenResolver();
      final unavailable = <SurfaceScreenUnavailableError>[];
      await tester.pumpWidget(
        _screen(fixture, resolver, onUnavailable: unavailable.add),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('Compiled screen'), findsOneWidget);
      expect(unavailable, isEmpty);

      resolver.freshResult.complete(fixture.hosted());
      await tester.pump();
      await tester.pump();
      expect(find.text('Compiled screen'), findsOneWidget);
      expect(find.text('Hosted screen'), findsNothing);
    });

    testWidgets('a custom resolver is raced as an opaque future',
        (tester) async {
      final fixture = stringScreenFixture();
      await tester.pumpWidget(_screen(fixture, _PendingScreenResolver()));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('Compiled screen'), findsOneWidget);
    });

    testWidgets('a stored screen that throws at build is forgotten',
        (tester) async {
      flows.registerThrowingWidget();
      final fixture = stringScreenFixture();
      final resolver = _ScreenResolver(
        local: fixture.hosted(
          hostedBlob: rfwSourceBlob('''
import acme.throwing;

widget OnboardingScreen = ThrowingWidget();
'''),
        ),
      );
      final reasons = <SurfaceScreenUnavailableError>[];
      await tester.pumpWidget(
        _screen(fixture, resolver, onUnavailable: reasons.add),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pump();
      tester.takeException();
      expect(
          reasons.single.reason, SurfaceScreenUnavailableReason.renderFailure);
      expect(resolver.forgotten, hasLength(1));
      expect(resolver.forgotten.single.slug, fixture.ref.slug);
    });

    testWidgets(
        'an untrusted hosted screen response falls back to the local copy',
        (tester) async {
      final fixture = stringScreenFixture(text: 'Stored screen');
      final resolver = _ScreenResolver(local: fixture.bundled());
      final unavailable = <SurfaceScreenUnavailableError>[];
      await tester.pumpWidget(
        _screen(fixture, resolver, onUnavailable: unavailable.add),
      );
      resolver.freshResult.completeError(const SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.contractMismatch,
        message: 'The hosted screen does not match its contract.',
      ));
      await tester.pump();
      await tester.pump();
      // As on every host: last good, then the bundled copy, then the policy.
      expect(find.text('Stored screen'), findsOneWidget);
      expect(unavailable, isEmpty);
    });

    testWidgets('a hidden screen whose fresh fails reports it unavailable',
        (tester) async {
      final fixture = stringScreenFixture();
      final resolver = _ScreenResolver();
      final unavailable = <SurfaceScreenUnavailableError>[];
      await tester.pumpWidget(MaterialApp(
        home: RestageScreen<String>(
          screen: fixture.ref,
          resolver: resolver,
          onUnavailable: unavailable.add,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      resolver.freshResult.complete(null);
      await tester.pump();
      await tester.pump();
      expect(unavailable, hasLength(1));
    });

    testWidgets('a hidden screen waits for fresh content', (tester) async {
      final fixture = stringScreenFixture(text: 'Late screen');
      final resolver = _PendingScreenResolver();
      await tester.pumpWidget(MaterialApp(
        home: RestageScreen<String>(
          screen: fixture.ref,
          resolver: resolver,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      resolver.completer.complete(fixture.bundled());
      await tester.pump();
      await tester.pump();
      expect(find.text('Late screen'), findsOneWidget);
    });
  });

  group('flow', () {
    setUp(_configureFast);
    testWidgets('a pending resolver renders the compiled flow at the deadline',
        (tester) async {
      final controller = _flowController(
        nativeOfferFlowRef,
        _PendingFlowResolver(),
      );
      await _mountFlow(tester, controller);
      await tester.pump(const Duration(milliseconds: 299));
      expect(find.text('Offer original'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.text('Offer original'), findsOneWidget);
      await _unmountFlow(tester, controller);
    });

    testWidgets('fresh content before the deadline renders', (tester) async {
      final resolver = _FlowRacer();
      final controller = _flowController(flows.firstRunFlowRef, resolver);
      await _mountFlow(tester, controller);
      await tester.pump(const Duration(milliseconds: 100));
      resolver.freshResult.complete(flows.resolvedFlow(welcomeText: 'Fresh'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.text('Fresh'), findsOneWidget);
      expect(resolver.freshCalls.single.$2, isTrue);
      expect(resolver.freshCalls.single.$3, isNotNull);
      await _unmountFlow(tester, controller);
    });

    testWidgets('the ready local candidate renders at the deadline',
        (tester) async {
      final resolver = _FlowRacer(
        local: flows.resolvedFlow(welcomeText: 'Stored'),
      );
      final controller = _flowController(flows.firstRunFlowRef, resolver);
      await _mountFlow(tester, controller);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('Stored'), findsOneWidget);
      await _unmountFlow(tester, controller);
    });

    testWidgets('a late assigned flow root never swaps in', (tester) async {
      final resolver = _FlowRacer(
        local: flows.resolvedFlow(welcomeText: 'Stored'),
      );
      await tester.pumpWidget(MaterialApp(
        home: RestageFlowGraph<flows.FirstRunResult>(
          flow: flows.firstRunFlowRef,
          resolver: resolver,
          liveRefresh: const {SurfaceRefreshTrigger.appResume},
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      await _settleFlow(tester);
      expect(find.text('Stored'), findsOneWidget);

      final assigned = attachMeasurementPublicationBindingReference(
        flows.resolvedFlow(welcomeText: 'Assigned arm'),
        null,
        canonicalExperimentAssignment: canonicalAssignmentFixture(),
      );
      resolver.local = assigned;
      resolver.freshResult.complete(assigned);
      await _settleFlow(tester);
      expect(find.text('Assigned arm'), findsNothing);
      expect(find.text('Stored'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    for (final liveRefresh in [true, false]) {
      testWidgets(
          'late fresh content swaps in only with live refresh: '
          '$liveRefresh', (tester) async {
        final reports = <SurfaceResolutionReport>[];
        Restage.configure(
            firstLaunchWait: _wait,
            freshWindow: _wait,
            onSurfaceResolution: reports.add);
        final resolver = _FlowRacer(
          local: flows.resolvedFlow(welcomeText: 'Stored'),
        );
        await tester.pumpWidget(MaterialApp(
          home: RestageFlowGraph<flows.FirstRunResult>(
            flow: flows.firstRunFlowRef,
            resolver: resolver,
            liveRefresh: liveRefresh
                ? const {SurfaceRefreshTrigger.appResume}
                : const <SurfaceRefreshTrigger>{},
          ),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        await _settleFlow(tester);
        expect(find.text('Stored'), findsOneWidget);
        expect(reports.map((r) => r.source), [SurfaceResolutionSource.bundled]);

        final fresh = flows.resolvedFlow(welcomeText: 'Fresh');
        resolver.freshResult.complete(fresh);
        await _settleFlow(tester);
        expect(find.text('Fresh'), liveRefresh ? findsOneWidget : findsNothing);
        // The late root is adopted as handed: no second fetch.
        expect(resolver.freshCalls, hasLength(1));
        // An adopted late root is reported once, like any rendered root.
        expect(
          reports.map((r) => r.source),
          [
            SurfaceResolutionSource.bundled,
            if (liveRefresh) SurfaceResolutionSource.bundled,
          ],
        );
        expect(reports.length, liveRefresh ? 2 : 1);
        expect(
            find.text('Stored'), liveRefresh ? findsNothing : findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
    }

    testWidgets('a late flow root the gate rejects is not reported',
        (tester) async {
      final reports = <SurfaceResolutionReport>[];
      Restage.configure(
          firstLaunchWait: _wait,
          freshWindow: _wait,
          onSurfaceResolution: reports.add);
      final resolver = _FlowRacer(
        local: flows.resolvedFlow(welcomeText: 'Stored'),
      );
      await tester.pumpWidget(MaterialApp(
        home: RestageFlowGraph<flows.FirstRunResult>(
          flow: flows.firstRunFlowRef,
          resolver: resolver,
          liveRefresh: const {SurfaceRefreshTrigger.appResume},
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      await _settleFlow(tester);
      expect(reports, hasLength(1));

      // The late root is adopted, then the user moves on before it paints.
      resolver.freshResult.complete(flows.resolvedFlow(welcomeText: 'Fresh'));
      await tester.tap(find.text('Stored'));
      await _settleFlow(tester);

      expect(find.text('Fresh'), findsNothing);
      expect(reports, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('a stored flow that throws at build is forgotten',
        (tester) async {
      flows.registerThrowingWidget();
      final resolver = _FlowRacer(local: flows.throwingResolvedFlow());
      final controller = _flowController(flows.firstRunFlowRef, resolver);
      await _mountFlow(tester, controller);
      await tester.pump(const Duration(milliseconds: 300));
      await _settleFlow(tester);
      tester.takeException();
      expect(resolver.forgotten, hasLength(1));
      expect(resolver.forgotten.single.slug, flows.firstRunFlowRef.id);
      await _unmountFlow(tester, controller);
    });

    testWidgets('without a compiled flow the mount waits for fresh',
        (tester) async {
      final resolver = _FlowRacer();
      final controller = _flowController(flows.firstRunFlowRef, resolver);
      await _mountFlow(tester, controller);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('Late'), findsNothing);
      resolver.freshResult.complete(flows.resolvedFlow(welcomeText: 'Late'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.text('Late'), findsOneWidget);
      await _unmountFlow(tester, controller);
    });
  });

  group('surface load events', () {
    setUp(() => Restage.configure(
          firstLaunchWait: const Duration(seconds: 1),
          freshWindow: const Duration(milliseconds: 100),
        ));

    testWidgets('a paywall reports delivered content', (tester) async {
      final events = _listen();
      final resolver = _PaywallResolver();
      await tester.pumpWidget(_paywall(resolver));
      await tester.pump(const Duration(milliseconds: 50));
      resolver.freshResult.complete(
          labelSurfaceSource(_blob('Fresh'), SurfaceResolutionSource.fresh));
      await tester.pump();
      await tester.pump();
      expect(find.text('Fresh'), findsOneWidget);
      final completed = _onlyCompletion(events, 'pro', Surface.paywall);
      expect(completed.source, SurfaceLoadSource.delivered);
      expect(completed.firstLaunchWaitPassed, isFalse);
      expect(completed.freshWindowPassed, isFalse);
      expect(events.whereType<PaywallLoadStarted>(), hasLength(1));
      expect(events.whereType<PaywallLoadCompleted>(), hasLength(1));
    });

    testWidgets('a paywall with nothing by the wait reports the original',
        (tester) async {
      final events = _listen();
      final resolver = _PaywallResolver();
      await tester.pumpWidget(_paywall(resolver));
      await tester.pump(const Duration(milliseconds: 999));
      expect(events.whereType<SurfaceLoadCompleted>(), isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.text('Compiled'), findsOneWidget);
      resolver.freshResult.complete(
          labelSurfaceSource(_blob('Fresh'), SurfaceResolutionSource.fresh));
      await tester.pump();
      await tester.pump();
      final completed = _onlyCompletion(events, 'pro', Surface.paywall);
      expect(completed.source, SurfaceLoadSource.original);
      expect(completed.firstLaunchWaitPassed, isTrue);
      expect(completed.freshWindowPassed, isTrue);
    });

    testWidgets('a paywall reports saved content once across a late swap',
        (tester) async {
      final events = _listen();
      final resolver = _PaywallResolver(
          local: labelSurfaceSource(
              _blob('Disk'), SurfaceResolutionSource.holdLastGood));
      await tester.pumpWidget(_paywall(
        resolver,
        liveRefresh: const {SurfaceRefreshTrigger.appResume},
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text('Disk'), findsOneWidget);
      resolver.freshResult.complete(
          labelSurfaceSource(_blob('Fresh'), SurfaceResolutionSource.fresh));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('Fresh'), findsOneWidget);
      final completed = _onlyCompletion(events, 'pro', Surface.paywall);
      expect(completed.source, SurfaceLoadSource.saved);
      expect(completed.firstLaunchWaitPassed, isFalse);
      expect(completed.freshWindowPassed, isTrue);
      expect(events.whereType<PaywallLoadCompleted>(), hasLength(2));
    });

    testWidgets('a paywall that fails to load paints and reports its original',
        (tester) async {
      final events = _listen();
      final resolver = _PaywallResolver();
      await tester.pumpWidget(_paywall(resolver));
      resolver.freshResult.completeError(const RestagePaywallError(
          code: RestageErrorCodes.deliveryUnavailable, message: 'offline'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('Compiled'), findsOneWidget);
      final completed = _onlyCompletion(events, 'pro', Surface.paywall);
      expect(completed.source, SurfaceLoadSource.original);
      expect(completed.firstLaunchWaitPassed, isFalse);
      expect(events.whereType<PaywallLoadFailed>(), hasLength(1));
    });

    final screen = stringScreenFixture(text: 'Hosted screen');

    testWidgets('a screen reports delivered content', (tester) async {
      final events = _listen();
      final resolver = _ScreenResolver();
      await tester.pumpWidget(_screen(screen, resolver));
      await tester.pump(const Duration(milliseconds: 50));
      resolver.freshResult.complete(
          labelSurfaceSource(screen.hosted(), SurfaceResolutionSource.fresh));
      await tester.pump();
      await tester.pump();
      expect(find.text('Hosted screen'), findsOneWidget);
      final completed =
          _onlyCompletion(events, screen.ref.slug, screen.ref.surface);
      expect(completed.source, SurfaceLoadSource.delivered);
      expect(completed.firstLaunchWaitPassed, isFalse);
    });

    testWidgets('a screen with nothing by the wait reports the original',
        (tester) async {
      final events = _listen();
      final resolver = _ScreenResolver();
      await tester.pumpWidget(_screen(screen, resolver));
      await tester.pump(RenderDeadline.defaultFirstLaunchWait);
      await tester.pump();
      expect(find.text('Compiled screen'), findsOneWidget);
      final completed =
          _onlyCompletion(events, screen.ref.slug, screen.ref.surface);
      expect(completed.source, SurfaceLoadSource.original);
      expect(completed.firstLaunchWaitPassed, isTrue);
    });

    testWidgets('a screen reports saved content at the fresh window',
        (tester) async {
      final events = _listen();
      final resolver = _ScreenResolver(
          local: labelSurfaceSource(
              screen.bundled(), SurfaceResolutionSource.holdLastGood));
      await tester.pumpWidget(_screen(screen, resolver));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text('Hosted screen'), findsOneWidget);
      final completed =
          _onlyCompletion(events, screen.ref.slug, screen.ref.surface);
      expect(completed.source, SurfaceLoadSource.saved);
      expect(completed.firstLaunchWaitPassed, isFalse);
      expect(completed.freshWindowPassed, isTrue);
    });

    testWidgets('an onboarding flow reports delivered content', (tester) async {
      final events = _listen();
      final resolver = _FlowRacer();
      await tester.pumpWidget(_onboarding(flows.firstRunFlowRef, resolver));
      await tester.pump(const Duration(milliseconds: 50));
      resolver.freshResult.complete(labelSurfaceSource(
          flows.resolvedFlow(welcomeText: 'Fresh'),
          SurfaceResolutionSource.fresh));
      await _settleFlow(tester);
      expect(find.text('Fresh'), findsOneWidget);
      final completed =
          _onlyCompletion(events, flows.firstRunFlowRef.id, Surface.onboarding);
      expect(completed.source, SurfaceLoadSource.delivered);
      expect(completed.firstLaunchWaitPassed, isFalse);
      expect(completed.freshWindowPassed, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'an onboarding flow with nothing by the wait reports the '
        'original', (tester) async {
      final events = _listen();
      await tester
          .pumpWidget(_onboarding(nativeOfferFlowRef, _PendingFlowResolver()));
      await tester.pump(RenderDeadline.defaultFirstLaunchWait);
      await _settleFlow(tester);
      expect(find.text('Offer original'), findsOneWidget);
      final completed =
          _onlyCompletion(events, nativeOfferFlowRef.id, Surface.onboarding);
      expect(completed.source, SurfaceLoadSource.original);
      expect(completed.firstLaunchWaitPassed, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an onboarding flow reports saved content at the fresh window',
        (tester) async {
      final events = _listen();
      final resolver = _FlowRacer(
          local: labelSurfaceSource(flows.resolvedFlow(welcomeText: 'Stored'),
              SurfaceResolutionSource.holdLastGood));
      await tester.pumpWidget(_onboarding(flows.firstRunFlowRef, resolver));
      await tester.pump(const Duration(milliseconds: 100));
      await _settleFlow(tester);
      expect(find.text('Stored'), findsOneWidget);
      final completed =
          _onlyCompletion(events, flows.firstRunFlowRef.id, Surface.onboarding);
      expect(completed.source, SurfaceLoadSource.saved);
      expect(completed.firstLaunchWaitPassed, isFalse);
      expect(completed.freshWindowPassed, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('surface load events on a controller you create', () {
    setUp(_configureFast);

    List<String> loads(List<RestageEvent> events) => [
          for (final event in events)
            switch (event) {
              SurfaceLoadStarted() => 'started',
              SurfaceLoadCompleted(:final source) =>
                'completed ${source.wireName}',
              SurfaceLoadFailed(:final reason) => 'failed ${reason.wireName}',
              _ => null,
            },
        ].nonNulls.toList();

    testWidgets('a flow view completes on its first screen', (tester) async {
      final events = <RestageEvent>[];
      final resolver = _FlowRacer();
      final controller =
          _flowController(flows.firstRunFlowRef, resolver, onEvent: events.add);
      await _mountFlow(tester, controller);
      resolver.freshResult.complete(labelSurfaceSource(
          flows.resolvedFlow(welcomeText: 'Fresh'),
          SurfaceResolutionSource.fresh));
      await _settleFlow(tester);
      expect(find.text('Fresh'), findsOneWidget);
      expect(loads(events), ['started', 'completed delivered']);
      await _unmountFlow(tester, controller);
    });

    testWidgets('a screen view completes on its screen', (tester) async {
      final events = <RestageEvent>[];
      final resolver = _FlowRacer();
      final controller =
          _flowController(flows.firstRunFlowRef, resolver, onEvent: events.add);
      unawaited(controller.load());
      await tester.pumpWidget(
          MaterialApp(home: RestageScreenView(controller: controller)));
      resolver.freshResult.complete(labelSurfaceSource(
          flows.resolvedFlow(welcomeText: 'Fresh'),
          SurfaceResolutionSource.fresh));
      await _settleFlow(tester);
      expect(find.text('Fresh'), findsOneWidget);
      expect(loads(events), ['started', 'completed delivered']);
      await _unmountFlow(tester, controller);
    });

    for (final screenView in [false, true]) {
      testWidgets(
          'a failed controller under a ${screenView ? 'screen' : 'flow'} view '
          'fails its load', (tester) async {
        final events = <RestageEvent>[];
        final resolver = _FlowRacer();
        final controller = _flowController(flows.firstRunFlowRef, resolver,
            onEvent: events.add);
        unawaited(controller.load());
        await tester.pumpWidget(MaterialApp(
            home: screenView
                ? RestageScreenView(
                    controller: controller,
                    loadingBuilder: (_) => const Text('Waiting'))
                : RestageFlowView(
                    controller: controller,
                    loadingBuilder: (_) => const Text('Waiting'))));
        resolver.freshResult.completeError(const FlowUnavailableError(
            flowId: 'first_run',
            flowVersion: 1,
            reason: 'delivery_unavailable',
            message: 'offline'));
        await _settleFlow(tester);
        expect(find.text('Waiting'), findsOneWidget);
        expect(loads(events), ['started', 'failed unavailable']);
        await _unmountFlow(tester, controller);
      });
    }
  });

  group('slow measurement', () {
    late AdmittedConstructionOwnerHostTestHarness harness;
    setUp(() {
      harness = AdmittedConstructionOwnerHostTestHarness.install(
        publicationContext:
            AdmittedBundledPublicationFixture.build().publicationContextRef,
        bundledTargetProfileLoader: () =>
            Completer<BundledMeasurementTargetProfileLoadResult>().future,
      );
    });
    tearDown(() => harness.close());

    testWidgets('a paywall paints while its session is still opening',
        (tester) async {
      final resolver = _PaywallResolver();
      await tester.pumpWidget(_paywall(resolver));
      resolver.freshResult.complete(_blob('Fresh'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Fresh'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(MeasurementHostSessionController.openFailureBound);
    });

    testWidgets('a screen paints while its session is still opening',
        (tester) async {
      final fixture = stringScreenFixture(text: 'Hosted screen');
      final resolver = _ScreenResolver();
      await tester.pumpWidget(_screen(fixture, resolver));
      resolver.freshResult.complete(fixture.hosted());
      await tester.pump();
      await tester.pump();
      expect(find.text('Hosted screen'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(MeasurementHostSessionController.openFailureBound);
    });

    testWidgets('a flow paints while its session is still opening',
        (tester) async {
      final resolver = _FlowRacer();
      await tester.pumpWidget(MaterialApp(
        home: RestageFlowGraph<flows.FirstRunResult>(
          flow: flows.firstRunFlowRef,
          resolver: resolver,
        ),
      ));
      resolver.freshResult.complete(flows.resolvedFlow(welcomeText: 'Fresh'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.text('Fresh'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(MeasurementHostSessionController.openFailureBound);
    });
  });

  group('configure', () {
    // Configuring without a credential purges persisted measurement files,
    // and that purge can outlive the test that started it.
    late Directory support;
    // Configuring reads the first-launch date in the background; without a
    // store that read fails after the test that started it.
    setUp(() => SharedPreferences.setMockInitialValues({}));
    setUpAll(() {
      support = Directory.systemTemp.createTempSync('restage_deadline');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathProvider, (_) async => support.path);
    });
    tearDownAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathProvider, null);
      support.deleteSync(recursive: true);
    });

    test('the first-launch wait defaults to 3 s and the fresh window to 150 ms',
        () {
      Restage.debugReset();
      Restage.configure();
      expect(Restage.freshWindow, const Duration(milliseconds: 150));
      expect(Restage.firstLaunchWaitFor(""), const Duration(seconds: 3));
    });

    test('configure sets the render deadline', () {
      Restage.configure(firstLaunchWait: const Duration(milliseconds: 120));
      expect(Restage.firstLaunchWaitFor(""), const Duration(milliseconds: 120));
      Restage.configureWithInstalledCatalog(
        firstLaunchWait: const Duration(milliseconds: 80),
      );
      expect(Restage.firstLaunchWaitFor(""), const Duration(milliseconds: 80));
    });

    testWidgets(
        'configure prefetches the listed surfaces without an assignment key',
        (tester) async {
      final resolver = _RacedPaywallResolver();
      Restage.configure(
        firstLaunchWait: _wait,
        freshWindow: _wait,
        apiKey: 'key',
        baseUrl: 'https://example.test',
        measurementEnabled: false,
        resolver: resolver,
        surfaces: const [PaywallRef('pro')],
      );
      await _pumpPrefetch(tester);
      expect(resolver.freshCalls, [
        (
          SurfaceStoreKey(
            scope: SurfaceStoreKey.scopeFor(
              apiKey: 'key',
            ),
            surfaceType: 'paywall',
            slug: 'pro',
            contractVersion: 0,
          ),
          false,
        ),
      ]);
    });

    testWidgets('configure revalidates every stored key in its scope',
        (tester) async {
      final scope = SurfaceStoreKey.scopeFor(
        apiKey: 'key',
      );
      final stored = SurfaceStoreKey(
        scope: scope,
        surfaceType: 'paywall',
        slug: 'held',
        contractVersion: 2,
      );
      const otherScope = SurfaceStoreKey(
        scope: 'otherscope000000',
        surfaceType: 'paywall',
        slug: 'held',
        contractVersion: 2,
      );
      await Restage.surfaceArtifactStore.write(stored, _stored);
      await Restage.surfaceArtifactStore.write(otherScope, _stored);

      final resolver = _RacedPaywallResolver();
      Restage.configure(
        firstLaunchWait: _wait,
        freshWindow: _wait,
        apiKey: 'key',
        baseUrl: 'https://example.test',
        measurementEnabled: false,
        resolver: resolver,
      );
      await _pumpPrefetch(tester);
      expect(resolver.freshCalls, [(stored, false)]);
    });

    testWidgets('configure without a credential prefetches nothing',
        (tester) async {
      final resolver = _RacedPaywallResolver();
      Restage.configure(
        firstLaunchWait: _wait,
        freshWindow: _wait,
        resolver: resolver,
        surfaces: const [PaywallRef('pro')],
      );
      await _pumpPrefetch(tester);
      expect(resolver.freshCalls, isEmpty);
    });

    testWidgets('a failed prefetch stays in the background', (tester) async {
      final resolver = _RacedPaywallResolver(fail: true);
      Restage.configure(
        firstLaunchWait: _wait,
        freshWindow: _wait,
        apiKey: 'key',
        baseUrl: 'https://example.test',
        measurementEnabled: false,
        resolver: resolver,
        surfaces: const [PaywallRef('pro')],
      );
      await _pumpPrefetch(tester);
      expect(resolver.freshCalls, hasLength(1));
    });

    testWidgets('prefetch starts after the first frame', (tester) async {
      final resolver = _RacedPaywallResolver();
      Restage.configure(
        firstLaunchWait: _wait,
        freshWindow: _wait,
        apiKey: 'key',
        baseUrl: 'https://example.test',
        measurementEnabled: false,
        resolver: resolver,
        surfaces: const [PaywallRef('pro')],
      );
      await tester.idle();
      expect(resolver.freshCalls, isEmpty);
      await _pumpPrefetch(tester);
      expect(resolver.freshCalls, hasLength(1));
    });

    testWidgets('prefetch runs at most four fetches at once', (tester) async {
      final resolver = _RacedPaywallResolver(hold: true);
      Restage.configure(
        firstLaunchWait: _wait,
        freshWindow: _wait,
        apiKey: 'key',
        baseUrl: 'https://example.test',
        measurementEnabled: false,
        resolver: resolver,
        surfaces: [for (var i = 0; i < 6; i += 1) PaywallRef('p$i')],
      );
      await _pumpPrefetch(tester);
      expect(resolver.freshCalls, hasLength(4));
      resolver.release.complete();
      await _pumpPrefetch(tester);
      expect(resolver.freshCalls, hasLength(6));
    });

    testWidgets('stored flow keys without a listed reference are skipped',
        (tester) async {
      final scope = SurfaceStoreKey.scopeFor(
        apiKey: 'key',
      );
      final storedFlow = SurfaceStoreKey(
        scope: scope,
        surfaceType: 'onboarding',
        slug: 'first_run',
        contractVersion: 0,
      );
      await Restage.surfaceArtifactStore.write(storedFlow, _stored);
      final flowResolver = _FlowRacer();
      Restage.configure(
        firstLaunchWait: _wait,
        freshWindow: _wait,
        apiKey: 'key',
        baseUrl: 'https://example.test',
        measurementEnabled: false,
        flowResolver: flowResolver,
      );
      await _pumpPrefetch(tester);
      expect(flowResolver.freshCalls, isEmpty);
    });

    testWidgets('a stored flow key with a listed reference is revalidated',
        (tester) async {
      final scope = SurfaceStoreKey.scopeFor(
        apiKey: 'key',
      );
      final storedFlow = SurfaceStoreKey(
        scope: scope,
        surfaceType: 'onboarding',
        slug: 'first_run',
        contractVersion: 0,
      );
      await Restage.surfaceArtifactStore.write(storedFlow, _stored);
      final flowResolver = _FlowRacer();
      Restage.configure(
        firstLaunchWait: _wait,
        freshWindow: _wait,
        apiKey: 'key',
        baseUrl: 'https://example.test',
        measurementEnabled: false,
        flowResolver: flowResolver,
        surfaces: const [flows.firstRunFlowRef],
      );
      await _pumpPrefetch(tester);
      expect(flowResolver.freshCalls.map((c) => c.$1), [storedFlow]);
    });

    test('reset clears the stored surfaces', () async {
      const key = SurfaceStoreKey(
        scope: 'scope00000000000',
        surfaceType: 'paywall',
        slug: 'held',
        contractVersion: 1,
      );
      await Restage.surfaceArtifactStore.write(key, _stored);
      Restage.reset();
      await pumpEventQueue();
      expect(await Restage.surfaceArtifactStore.keys(), isEmpty);
    });

    test('a reset restores the default deadline', () {
      Restage.configure(firstLaunchWait: const Duration(milliseconds: 120));
      Restage.debugReset();
      expect(Restage.firstLaunchWaitFor(""),
          RenderDeadline.defaultFirstLaunchWait);
    });
  });
}

final _stored = StoredSurface(
  descriptorJson: Uint8List.fromList(const [123, 125]),
  artifactBytes: Uint8List(0),
);

final class _RacedPaywallResolver extends VariantResolver
    implements RacedSurfaceResolver<ResolvedVariant> {
  @override
  Future<void> forgetStored(SurfaceStoreKey key) async {}

  @override
  bool get freshAnswerArrived => false;

  _RacedPaywallResolver({this.fail = false, this.hold = false});

  final bool fail;
  final bool hold;
  final Completer<void> release = Completer<void>();
  final List<(SurfaceStoreKey, bool)> freshCalls = [];

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) =>
      Future.error(StateError('not used'));

  @override
  Future<ResolvedVariant?> bestLocal(SurfaceStoreKey key) async => null;

  @override
  Future<ResolvedVariant?> fresh(
    SurfaceStoreKey key, {
    required bool sendAssignmentKey,
    Future<void>? keyDeadline,
  }) async {
    freshCalls.add((key, sendAssignmentKey));
    if (hold) await release.future;
    if (fail) throw StateError('offline');
    return null;
  }
}

Uint8List _bytes(String text) => Uint8List.fromList(encodeLibraryBlob(
      parseLibraryFile('''
        import restage.core;
        widget Paywall = Text(text: "$text");
      '''),
    ));

ResolvedVariant _variant(String text) => ResolvedVariant(
      bytes: _bytes(text),
      surfaceVersion: text,
      paywallId: 'pro',
    );

ResolvedPaywallPayload _blob(String text) => BlobPaywallPayload(_variant(text));

ResolvedPaywallPayload _tappableBlob(String text) =>
    BlobPaywallPayload(ResolvedVariant(
      bytes: Uint8List.fromList(encodeLibraryBlob(parseLibraryFile('''
        import restage.core;
        widget Paywall = GestureDetector(
          onTap: event "tap" { },
          child: Text(text: "$text"),
        );
      '''))),
      surfaceVersion: text,
      paywallId: 'pro',
    ));

Widget _paywall(
  VariantResolver resolver, {
  void Function(RestageEvent event)? onEvent,
  Set<SurfaceRefreshTrigger>? liveRefresh,
}) =>
    MaterialApp(
      home: RestagePaywall(
        id: 'pro',
        resolver: resolver,
        onEvent: onEvent,
        liveRefresh: liveRefresh,
        fallbackBuilder: (_) => const Text('Compiled'),
      ),
    );

final class _PaywallResolver extends VariantResolver
    with RacedSurfaceReporting<ResolvedPaywallPayload>
    implements RacedSurfaceResolver<ResolvedPaywallPayload> {
  @override
  Future<void> forgetStored(SurfaceStoreKey key) async {}

  @override
  final SurfaceArtifactStore store = MemorySurfaceArtifactStore();

  _PaywallResolver({this.local, this.slowStorage = false});

  final ResolvedPaywallPayload? local;
  final bool slowStorage;
  final Completer<ResolvedPaywallPayload?> freshResult =
      Completer<ResolvedPaywallPayload?>();
  final List<(SurfaceStoreKey, bool, Future<void>?)> freshCalls = [];

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) =>
      Future.error(StateError('raced resolvers are not resolved directly'));

  @override
  Future<ResolvedPaywallPayload?> bestLocal(SurfaceStoreKey key) => slowStorage
      ? Completer<ResolvedPaywallPayload?>().future
      : Future.value(local);

  @override
  Future<ResolvedPaywallPayload?> fresh(
    SurfaceStoreKey key, {
    required bool sendAssignmentKey,
    Future<void>? keyDeadline,
  }) {
    freshCalls.add((key, sendAssignmentKey, keyDeadline));
    return freshResult.future;
  }
}

final class _PendingCustomResolver extends VariantResolver {
  final Completer<ResolvedVariant> completer = Completer<ResolvedVariant>();

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) =>
      completer.future;
}

final class _SwitchableCustomResolver extends VariantResolver {
  var fail = false;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    if (fail) {
      throw const RestagePaywallError(code: 'fetch_failed', message: 'no');
    }
    return _variant('First');
  }
}

Widget _screen(
  ScreenFixture<String> fixture,
  SurfaceScreenResolver resolver, {
  ValueChanged<SurfaceScreenUnavailableError>? onUnavailable,
}) =>
    MaterialApp(
      home: RestageScreen<String>(
        screen: fixture.ref,
        resolver: resolver,
        onUnavailable: onUnavailable,
        fallbackBuilder: (_) => const Text('Compiled screen'),
      ),
    );

final class _ScreenResolver
    with RacedSurfaceReporting<ResolvedSurfaceScreen>
    implements
        SurfaceScreenResolver,
        RacedSurfaceResolver<ResolvedSurfaceScreen> {
  _ScreenResolver({this.local});

  final List<SurfaceStoreKey> forgotten = [];

  @override
  final SurfaceArtifactStore store = MemorySurfaceArtifactStore();

  @override
  Future<void> forgetStored(SurfaceStoreKey key) async => forgotten.add(key);

  @override
  Surface reportSurfaceFor(SurfaceStoreKey key) => key.surfaceType == 'screen'
      ? Surface.general
      : Surface.fromWireName(key.surfaceType);

  final ResolvedSurfaceScreen? local;
  final Completer<ResolvedSurfaceScreen?> freshResult =
      Completer<ResolvedSurfaceScreen?>();
  final List<(SurfaceStoreKey, bool, Future<void>?)> freshCalls = [];

  @override
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> screen) =>
      Future.error(StateError('raced resolvers are not resolved directly'));

  @override
  Future<ResolvedSurfaceScreen?> bestLocal(SurfaceStoreKey key) async =>
      local == null
          ? null
          : labelSurfaceSource<ResolvedSurfaceScreen>(
              local!, SurfaceResolutionSource.holdLastGood);

  @override
  Future<ResolvedSurfaceScreen?> fresh(
    SurfaceStoreKey key, {
    required bool sendAssignmentKey,
    Future<void>? keyDeadline,
  }) {
    freshCalls.add((key, sendAssignmentKey, keyDeadline));
    return freshResult.future;
  }
}

final class _PendingScreenResolver implements SurfaceScreenResolver {
  final Completer<ResolvedSurfaceScreen> completer =
      Completer<ResolvedSurfaceScreen>();

  @override
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> screen) =>
      completer.future;
}

RestageFlowController<R> _flowController<R>(
  SurfaceFlowRef<R> flow,
  FlowResolver resolver, {
  void Function(RestageEvent event)? onEvent,
}) =>
    RestageFlowController<R>(
      flow: flow,
      resolver: resolver,
      actions: null,
      onEvent: onEvent ?? (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );

Future<void> _mountFlow(
  WidgetTester tester,
  RestageFlowController<Object?> controller,
) async {
  unawaited(controller.load());
  await tester.pumpWidget(MaterialApp(
    home: RestageEventDispatcher(
      onEvent: controller.handleEvent,
      child: RestageFlowView(controller: controller),
    ),
  ));
}

Future<void> _settleFlow(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _unmountFlow(
  WidgetTester tester,
  RestageFlowController<Object?> controller,
) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  controller.dispose();
}

final class _PendingFlowResolver implements FlowResolver {
  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) =>
      Completer<ResolvedFlow>().future;
}

final class _FlowRacer
    with RacedSurfaceReporting<ResolvedFlow>
    implements
        FlowResolver,
        ActiveArmFlowResolver,
        RacedSurfaceResolver<ResolvedFlow> {
  _FlowRacer({this.local});

  final List<SurfaceStoreKey> forgotten = [];

  @override
  final SurfaceArtifactStore store = MemorySurfaceArtifactStore();

  @override
  Future<void> forgetStored(SurfaceStoreKey key) async => forgotten.add(key);

  @override
  Surface reportSurfaceFor(SurfaceStoreKey key) => key.surfaceType == 'screen'
      ? Surface.general
      : Surface.fromWireName(key.surfaceType);

  ResolvedFlow? local;
  final Completer<ResolvedFlow?> freshResult = Completer<ResolvedFlow?>();
  final List<(SurfaceStoreKey, bool, Future<void>?)> freshCalls = [];

  @override
  bool get activeArmEnabled => true;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) =>
      Future.error(StateError('raced resolvers are not resolved directly'));

  @override
  Future<ResolvedFlow> resolveActiveRoot<R>(OnboardingFlowRef<R> flow) =>
      Future.error(StateError('raced resolvers are not resolved directly'));

  @override
  Future<ResolvedFlow?> bestLocal(SurfaceStoreKey key) async => local;

  @override
  Future<ResolvedFlow?> fresh(
    SurfaceStoreKey key, {
    required bool sendAssignmentKey,
    Future<void>? keyDeadline,
  }) {
    freshCalls.add((key, sendAssignmentKey, keyDeadline));
    return freshResult.future;
  }
}

List<RestageEvent> _listen() {
  final events = <RestageEvent>[];
  final subscription = Restage.events.listen(events.add);
  addTearDown(subscription.cancel);
  return events;
}

List<RestageEvent> _loads(List<RestageEvent> events) => [
      for (final event in events)
        if (event is SurfaceLoadStarted ||
            event is SurfaceLoadCompleted ||
            event is SurfaceLoadFailed)
          event,
    ];

/// Asserts one start and one completion for [id], and returns the completion.
SurfaceLoadCompleted _onlyCompletion(
  List<RestageEvent> events,
  String id,
  Surface surface,
) {
  final loads = _loads(events);
  expect(loads.map((event) => event.runtimeType),
      [SurfaceLoadStarted, SurfaceLoadCompleted]);
  final started = loads.first as SurfaceLoadStarted;
  final completed = loads.last as SurfaceLoadCompleted;
  expect((started.surfaceId, started.surface), (id, surface));
  expect((completed.surfaceId, completed.surface), (id, surface));
  return completed;
}

Widget _onboarding<R>(SurfaceFlowRef<R> flow, FlowResolver resolver) =>
    MaterialApp(
      home: RestageOnboarding<R>(
        flow: flow,
        resolver: resolver,
      ),
    );

Future<void> _pumpPrefetch(WidgetTester tester) async {
  for (var i = 0; i < 5; i += 1) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');
