import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/runtime/first_paint_lease_guard.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'flow_test_support.dart';

const _baseUrl = 'http://127.0.0.1:1';

const _messageFlowRef = SurfaceFlowRef<FirstRunResult>(
  id: 'first_run',
  version: 1,
  minClient: 3,
  surface: Surface.message,
  decodeResult: FirstRunResult.decode,
);

const _surveyFlowRef = SurfaceFlowRef<FirstRunResult>(
  id: 'first_run',
  version: 1,
  minClient: 3,
  surface: Surface.survey,
  decodeResult: FirstRunResult.decode,
);

const _paywallFlowRef = SurfaceFlowRef<FirstRunResult>(
  id: 'first_run',
  version: 1,
  minClient: 3,
  surface: Surface.paywall,
  decodeResult: FirstRunResult.decode,
);

const _rootAssignment = FlowAssignment(
  experimentId: 'exp-root',
  variantId: 'variant-b',
  experimentEpoch: 7,
);

final class _ControlledResolver implements FlowResolver {
  _ControlledResolver(this.first, this.afterFirst);

  final Completer<ResolvedFlow> first;
  final ResolvedFlow afterFirst;
  int calls = 0;

  @override
  Future<ResolvedFlow> resolve<R>(SurfaceFlowRef<R> flow) {
    calls += 1;
    return calls == 1 ? first.future : Future<ResolvedFlow>.value(afterFirst);
  }
}

final class _MutableResolver implements FlowResolver {
  _MutableResolver(this.current);

  ResolvedFlow current;
  int calls = 0;

  @override
  Future<ResolvedFlow> resolve<R>(SurfaceFlowRef<R> flow) async {
    calls += 1;
    return current;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Restage.debugReset();
    FirstPaintLeaseTransaction.debugBeforeDescendantPaint = null;
  });
  tearDown(() {
    FirstPaintLeaseTransaction.debugBeforeDescendantPaint = null;
    Restage.debugReset();
  });

  for (final testCase in const <({
    String surface,
    SurfaceFlowRef<FirstRunResult> flow,
  })>[
    (surface: 'onboarding', flow: firstRunFlowRef),
    (surface: 'message', flow: _messageFlowRef),
    (surface: 'survey', flow: _surveyFlowRef),
    (surface: 'paywall', flow: _paywallFlowRef),
  ]) {
    testWidgets(
        '${testCase.surface} emits one assigned canonical root after paint',
        (tester) async {
      final requests = <http.Request>[];
      _configureAnalytics(requests);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RestageSurfaceFlow<FirstRunResult>(
            flow: testCase.flow,
            resolver: StaticFlowResolver(
              _withAssignment(resolvedFlow(), _rootAssignment),
            ),
            unavailable: const FlowUnavailablePolicy.hide(),
          ),
        ),
      );
      await _pumpFrames(tester);

      final events = await _capturedEvents(requests);
      final exposureEvents = events
          .where(
            (event) => const <String>{
              'surface_presented',
              'flow_started',
              'onboarding_step_viewed',
            }.contains(event['name']),
          )
          .toList();
      expect(
        exposureEvents.map((event) => event['name']),
        <String>[
          'surface_presented',
          'flow_started',
          'onboarding_step_viewed',
        ],
      );
      final presentations = events
          .where((event) => event['name'] == 'surface_presented')
          .toList();
      expect(presentations, hasLength(1));
      final presentation = presentations.single;
      expect(presentation['surface'], testCase.surface);
      expect(presentation['surfaceId'], 'first_run');
      expect(presentation['surfaceVersion'], '1');
      expect(presentation['surfaceSessionId'], isNotNull);
      expect(presentation['experimentId'], 'exp-root');
      expect(presentation['variantId'], 'variant-b');
      expect(presentation['experimentEpoch'], 7);
      for (final exposure in exposureEvents.skip(1)) {
        expect(exposure['surface'], testCase.surface);
        expect(exposure['surfaceId'], 'first_run');
        expect(exposure['surfaceVersion'], '1');
        expect(
          exposure['surfaceSessionId'],
          presentation['surfaceSessionId'],
        );
        expect(exposure['experimentId'], 'exp-root');
        expect(exposure['variantId'], 'variant-b');
        expect(exposure['experimentEpoch'], 7);
      }
    });
  }

  for (final analyticsMode in const <String>[
    'no base URL',
    'analytics disabled',
  ]) {
    testWidgets(
        '$analyticsMode leaves a no-analytics surface paint-eligible without '
        'a retry loop', (tester) async {
      Restage.debugAnalyticsHttpClient = MockClient((_) async {
        fail('a disabled analytics transport must not post');
      });
      if (analyticsMode == 'no base URL') {
        Restage.configure(apiKey: 'rs_pk_no_transport');
      } else {
        Restage.configure(
          apiKey: 'rs_pk_no_transport',
          baseUrl: _baseUrl,
          analyticsEnabled: false,
        );
      }
      final resolver = _MutableResolver(resolvedFlow());

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RestageSurfaceFlow<FirstRunResult>(
            flow: _messageFlowRef,
            resolver: resolver,
            unavailable: const FlowUnavailablePolicy.hide(),
          ),
        ),
      );
      await _pumpFrames(tester);
      final visible = find.text('Welcome').evaluate().length;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(visible, 1);
      expect(resolver.calls, 1);
    });
  }

  testWidgets('a child-frame outcome inherits the rendered root context',
      (tester) async {
    final requests = <http.Request>[];
    _configureAnalytics(requests);
    final child = childScreenFlow(text: 'Child');
    final childCompleter = Completer<ResolvedFlow>()..complete(child);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestageSurfaceFlow<FirstRunResult>(
          flow: _messageFlowRef,
          resolver: ControlledInitialSubFlowResolver(
            root: initialSubFlowRoot(
              child: child,
              assignment: _rootAssignment,
            ),
            child: childCompleter,
          ),
          unavailable: const FlowUnavailablePolicy.hide(),
        ),
      ),
    );
    await _pumpFrames(tester);
    final initialEvents = await _capturedEvents(requests);
    final presentation = initialEvents.singleWhere(
      (event) => event['name'] == 'surface_presented',
    );
    final rootSession = presentation['surfaceSessionId'];
    requests.clear();

    await tester.tap(find.text('Child'));
    await _pumpFrames(tester);

    final outcomeEvents = await _capturedEvents(requests);
    final childOutcome = outcomeEvents.firstWhere(
      (event) =>
          event['name'] == 'flow_completed' &&
          (event['properties'] as Map<String, Object?>?)?['flowId'] == null,
      orElse: () => outcomeEvents.firstWhere(
        (event) => event['name'] == 'flow_completed',
      ),
    );
    expect(childOutcome['surface'], 'message');
    expect(childOutcome['surfaceId'], 'first_run');
    expect(childOutcome['surfaceVersion'], '1');
    expect(childOutcome['surfaceSessionId'], rootSession);
    expect(childOutcome['experimentId'], 'exp-root');
    expect(childOutcome['variantId'], 'variant-b');
    expect(childOutcome['experimentEpoch'], 7);
  });

  testWidgets('an unassigned general flow emits one assignment-null root',
      (tester) async {
    final requests = <http.Request>[];
    _configureAnalytics(requests);
    final typed = resolvedFlow();
    final general = ResolvedFlow(
      document: typed.document.copyWith(deliveryMode: FlowDeliveryMode.general),
      screenBlobs: typed.screenBlobs,
      cacheHit: false,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestageSurfaceFlow<FirstRunResult>(
          flow: _messageFlowRef,
          resolver: StaticFlowResolver(general),
          unavailable: const FlowUnavailablePolicy.hide(),
        ),
      ),
    );
    await _pumpFrames(tester);

    final presentation = (await _capturedEvents(requests)).singleWhere(
      (event) => event['name'] == 'surface_presented',
    );
    expect(presentation['surface'], 'message');
    expect(presentation['surfaceId'], 'first_run');
    expect(presentation['surfaceVersion'], '1');
    expect(presentation['surfaceSessionId'], isNotNull);
    expect(presentation['experimentId'], isNull);
    expect(presentation['variantId'], isNull);
    expect(presentation['experimentEpoch'], isNull);
  });

  testWidgets('screenless and build-failed roots emit zero canonical events',
      (tester) async {
    final requests = <http.Request>[];
    _configureAnalytics(requests);
    final screenless = ResolvedFlow(
      document: const FlowDocument(
        flow: 'first_run',
        version: 1,
        schemaVersion: 1,
        minClient: 3,
        initial: 'done',
        legacyTerminalResultPassthrough: true,
        screenArtifacts: <String, ScreenArtifact>{},
        states: <String, FlowState>{
          'done': EndFlowState(result: <String, Object?>{'completed': true}),
        },
      ),
      screenBlobs: const {},
      cacheHit: false,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestageSurfaceFlow<FirstRunResult>(
          flow: _messageFlowRef,
          resolver: StaticFlowResolver(screenless),
          unavailable: const FlowUnavailablePolicy.hide(),
        ),
      ),
    );
    await _pumpFrames(tester);
    expect(
      (await _capturedEvents(requests)).where(
        (event) => const <String>{
          'surface_presented',
          'flow_started',
          'onboarding_step_viewed',
        }.contains(event['name']),
      ),
      isEmpty,
    );

    requests.clear();
    registerThrowingWidget();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestageSurfaceFlow<FirstRunResult>(
          key: const ValueKey<String>('throwing'),
          flow: _messageFlowRef,
          resolver: StaticFlowResolver(throwingResolvedFlow()),
          unavailable: const FlowUnavailablePolicy.hide(),
        ),
      ),
    );
    await _pumpFrames(tester);
    expect(
      (await _capturedEvents(requests)).where(
        (event) => const <String>{
          'surface_presented',
          'flow_started',
          'onboarding_step_viewed',
        }.contains(event['name']),
      ),
      isEmpty,
    );
  });

  testWidgets('disposal before a controlled resolve paints emits zero',
      (tester) async {
    final requests = <http.Request>[];
    _configureAnalytics(requests);
    final first = Completer<ResolvedFlow>();
    final resolver = _ControlledResolver(first, resolvedFlow());

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestageSurfaceFlow<FirstRunResult>(
          flow: _messageFlowRef,
          resolver: resolver,
          unavailable: const FlowUnavailablePolicy.hide(),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    first.complete(resolvedFlow());
    await _pumpFrames(tester);

    expect(
      (await _capturedEvents(requests))
          .where((event) => event['name'] == 'surface_presented'),
      isEmpty,
    );
  });

  testWidgets(
      'reset after paint strips old UI outcomes and remount mints a new root',
      (tester) async {
    final requests = <http.Request>[];
    _configureAnalytics(requests);
    final assigned = _withAssignment(resolvedFlow(), _rootAssignment);

    Widget surface(Key key) => Directionality(
          textDirection: TextDirection.ltr,
          child: RestageSurfaceFlow<FirstRunResult>(
            key: key,
            flow: _messageFlowRef,
            resolver: StaticFlowResolver(assigned),
            unavailable: const FlowUnavailablePolicy.hide(),
          ),
        );

    await tester.pumpWidget(surface(const ValueKey<String>('before-reset')));
    await _pumpFrames(tester);
    final before = (await _capturedEvents(requests)).singleWhere(
      (event) => event['name'] == 'surface_presented',
    );
    requests.clear();

    Restage.reset();
    await tester.tap(find.text('Welcome'));
    await _pumpFrames(tester);
    await Restage.debugFlushAnalytics();
    final oldUiOutcome = _analyticsEvents(requests).lastWhere(
      (event) => event['name'] == 'onboarding_step_viewed',
    );
    expect(oldUiOutcome['surface'], 'message');
    expect(oldUiOutcome['surfaceId'], 'first_run');
    expect(oldUiOutcome['surfaceSessionId'], isNull);
    expect(oldUiOutcome['experimentId'], isNull);
    expect(oldUiOutcome['variantId'], isNull);
    expect(oldUiOutcome['experimentEpoch'], isNull);
    requests.clear();

    await tester.pumpWidget(surface(const ValueKey<String>('after-reset')));
    await _pumpFrames(tester);
    final remounted = (await _capturedEvents(requests)).singleWhere(
      (event) => event['name'] == 'surface_presented',
    );
    expect(remounted['surfaceSessionId'], isNot(before['surfaceSessionId']));
    expect(remounted['experimentId'], 'exp-root');
    expect(remounted['variantId'], 'variant-b');
    expect(remounted['experimentEpoch'], 7);
  });

  testWidgets(
      'reset before first paint rejects the stale root and emits only the retry',
      (tester) async {
    final requests = <http.Request>[];
    _configureAnalytics(requests);
    final stale = Completer<ResolvedFlow>();
    const retryAssignment = FlowAssignment(
      experimentId: 'exp-retry',
      variantId: 'variant-new-actor',
      experimentEpoch: 12,
    );
    final resolver = _ControlledResolver(
      stale,
      _withAssignment(
        resolvedFlow(welcomeText: 'Retry actor'),
        retryAssignment,
      ),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestageSurfaceFlow<FirstRunResult>(
          flow: _messageFlowRef,
          resolver: resolver,
          unavailable: const FlowUnavailablePolicy.hide(),
        ),
      ),
    );
    await tester.pump();

    Restage.reset();
    stale.complete(
      _withAssignment(
        resolvedFlow(welcomeText: 'Stale actor'),
        _rootAssignment,
      ),
    );
    await _pumpFrames(tester);

    final presentations = (await _capturedEvents(requests))
        .where((event) => event['name'] == 'surface_presented')
        .toList();
    expect(resolver.calls, 2);
    expect(find.text('Retry actor'), findsOneWidget);
    expect(find.text('Stale actor'), findsNothing);
    expect(presentations, hasLength(1));
    expect(presentations.single['surface'], 'message');
    expect(presentations.single['surfaceId'], 'first_run');
    expect(presentations.single['surfaceVersion'], '1');
    expect(presentations.single['surfaceSessionId'], isNotNull);
    expect(presentations.single['experimentId'], 'exp-retry');
    expect(presentations.single['variantId'], 'variant-new-actor');
    expect(presentations.single['experimentEpoch'], 12);
  });

  testWidgets(
      'refresh canonical matrix: unchanged/failed/assigned-blocked emit zero '
      'and promoted emits one', (tester) async {
    final requests = <http.Request>[];
    _configureAnalytics(requests);
    final initial = resolvedFlow(welcomeText: 'Initial');
    final resolver = _MutableResolver(initial);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestageSurfaceFlow<FirstRunResult>(
          flow: _messageFlowRef,
          resolver: resolver,
          unavailable: const FlowUnavailablePolicy.hide(),
        ),
      ),
    );
    await _pumpFrames(tester);
    final initialPresentations = _canonicalEvents(
      await _capturedEvents(requests),
    );
    final initialSession = initialPresentations.isEmpty
        ? null
        : initialPresentations.first['surfaceSessionId'];

    requests.clear();
    await Restage.reloadSurfaces();
    await _pumpFrames(tester);
    final unchanged = _canonicalEvents(await _capturedEvents(requests));

    requests.clear();
    resolver.current = resolvedFlow(welcomeText: 'Promoted');
    await Restage.reloadSurfaces();
    await _pumpFrames(tester);
    final promoted = _canonicalEvents(await _capturedEvents(requests));
    final promotedVisible = find.text('Promoted').evaluate().length;

    requests.clear();
    resolver.current = _brokenFlow('Failed');
    await Restage.reloadSurfaces();
    await _pumpFrames(tester);
    final failed = _canonicalEvents(await _capturedEvents(requests));
    final retainedAfterFailure = find.text('Promoted').evaluate().length;

    requests.clear();
    resolver.current = _withAssignment(
      resolvedFlow(welcomeText: 'Assigned blocked'),
      _rootAssignment,
    );
    await Restage.reloadSurfaces();
    await _pumpFrames(tester);
    final assignedBlocked = _canonicalEvents(await _capturedEvents(requests));
    final retainedAfterAssigned = find.text('Promoted').evaluate().length;
    final assignedVisible = find.text('Assigned blocked').evaluate().length;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(initialPresentations, hasLength(1));
    expect(unchanged, isEmpty, reason: 'unchanged refresh');
    expect(promoted, hasLength(1));
    expect(promotedVisible, 1);
    expect(promoted.first['surface'], 'message');
    expect(promoted.first['surfaceId'], 'first_run');
    expect(promoted.first['surfaceVersion'], '1');
    expect(promoted.first['surfaceSessionId'], isNot(initialSession));
    expect(promoted.first['experimentId'], isNull);
    expect(promoted.first['variantId'], isNull);
    expect(promoted.first['experimentEpoch'], isNull);
    expect(retainedAfterFailure, 1);
    expect(failed, isEmpty, reason: 'failed refresh');
    expect(retainedAfterAssigned, 1);
    expect(assignedVisible, 0);
    expect(assignedBlocked, isEmpty, reason: 'assigned-blocked refresh');
  });

  testWidgets(
      'a refresh accepted at paint cannot be discarded by a newer refresh '
      'before deferred cleanup', (tester) async {
    final requests = <http.Request>[];
    _configureAnalytics(requests);
    final resolver = _MutableResolver(
      resolvedFlow(welcomeText: 'Initial A'),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestageSurfaceFlow<FirstRunResult>(
          flow: _messageFlowRef,
          resolver: resolver,
          unavailable: const FlowUnavailablePolicy.hide(),
        ),
      ),
    );
    await _pumpFrames(tester);
    final initial = _canonicalEvents(await _capturedEvents(requests)).single;
    requests.clear();

    final acceptedB = resolvedFlow(welcomeText: 'Accepted B');
    resolver.current = acceptedB;
    await Restage.reloadSurfaces();
    resolver.current = acceptedB;
    var refreshCTriggered = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      refreshCTriggered = true;
      unawaited(Restage.reloadSurfaces());
    });

    await tester.pump();
    await _pumpFrames(tester);

    final presentations = _canonicalEvents(await _capturedEvents(requests));
    expect(refreshCTriggered, isTrue);
    expect(presentations, hasLength(1));
    expect(
      presentations.single['surfaceSessionId'],
      isNot(initial['surfaceSessionId']),
    );
    expect(find.text('Accepted B'), findsOneWidget);
    expect(find.text('Initial A'), findsNothing);
  });

  testWidgets(
      'a refresh whose guarded paint fails after provisional commit retains '
      'the current root and emits no candidate presentation', (tester) async {
    final requests = <http.Request>[];
    _configureAnalytics(requests);
    final resolver = _MutableResolver(
      resolvedFlow(welcomeText: 'Retained A'),
    );
    RestageFlowController<FirstRunResult>? retainedController;
    FirstPaintLeaseTransaction? retainedTransaction;
    FirstPaintLeaseTransaction.debugBeforeDescendantPaint = (transaction) {
      retainedTransaction ??= transaction;
    };

    Widget chromeBuilder(
      BuildContext context,
      FlowChromeState state,
      Widget screen,
    ) {
      final controller =
          (context.widget as RestageFlowView<FirstRunResult>).controller;
      retainedController ??= controller;
      return screen;
    }

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestageSurfaceFlow<FirstRunResult>(
          flow: _messageFlowRef,
          resolver: resolver,
          unavailable: const FlowUnavailablePolicy.hide(),
          chromeBuilder: chromeBuilder,
        ),
      ),
    );
    await _pumpFrames(tester);
    final initial = _canonicalEvents(await _capturedEvents(requests)).single;
    requests.clear();

    _ControlledPaintFailure.paintAttempts = 0;
    resolver.current = resolvedFlow(welcomeText: 'Failed B');
    FirstPaintLeaseTransaction.debugBeforeDescendantPaint = (transaction) {
      if (identical(transaction, retainedTransaction)) return;
      FirstPaintLeaseTransaction.debugBeforeDescendantPaint = null;
      _ControlledPaintFailure.paintAttempts += 1;
      final error =
          StateError('controlled general-flow descendant paint failure');
      final failureToken = Object();
      holdFrameworkPaintErrorForTransaction(transaction, failureToken);
      commitFrameworkRenderFailureForTransaction(transaction, failureToken);
      final candidateController = tester
          .widgetList<RestageFlowView<FirstRunResult>>(
            find.byType(RestageFlowView<FirstRunResult>),
          )
          .map((view) => view.controller)
          .firstWhere(
            (controller) => !identical(controller, retainedController),
          );
      scheduleMicrotask(() => candidateController.reportRenderFailure(error));
      throw error;
    };
    await Restage.reloadSurfaces();
    await _pumpFrames(tester);
    final retainedA = find.text('Retained A').evaluate().length;
    if (retainedA == 1) {
      await tester.tap(find.text('Retained A'));
      await _pumpFrames(tester);
    }

    final events = await _capturedEvents(requests);
    final candidatePresentations = _canonicalEvents(events);
    final retainedOutcomes = events
        .where((event) => event['name'] == 'onboarding_step_viewed')
        .toList();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    tester.takeException();

    expect(_ControlledPaintFailure.paintAttempts, 1);
    expect(candidatePresentations, isEmpty);
    expect(retainedA, 1);
    expect(retainedOutcomes, hasLength(1));
    expect(retainedOutcomes.single['surface'], 'message');
    expect(retainedOutcomes.single['surfaceId'], 'first_run');
    expect(
      retainedOutcomes.single['surfaceSessionId'],
      initial['surfaceSessionId'],
    );
  });

  testWidgets(
      'cross-tier transport hashes cannot turn one canonical document into a '
      'new root presentation', (tester) async {
    final requests = <http.Request>[];
    _configureAnalytics(requests);
    final semanticA = resolvedFlow(welcomeText: 'Same document');
    final resolver = _MutableResolver(
      _withTransportHash(semanticA, '{"tier":"hosted","spacing":"compact"}'),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestageSurfaceFlow<FirstRunResult>(
          flow: _messageFlowRef,
          resolver: resolver,
          unavailable: const FlowUnavailablePolicy.hide(),
        ),
      ),
    );
    await _pumpFrames(tester);
    final initial = _canonicalEvents(await _capturedEvents(requests)).single;
    requests.clear();

    resolver.current = _withTransportHash(
      semanticA,
      '{\n  "spacing": "compact",\n  "tier": "bundled"\n}',
    );
    await Restage.reloadSurfaces();
    await _pumpFrames(tester);
    final unchanged = _canonicalEvents(await _capturedEvents(requests));
    requests.clear();

    resolver.current = _withTransportHash(
      resolvedFlow(welcomeText: 'Actually changed'),
      '{"tier":"hosted","content":"actually-changed"}',
    );
    await Restage.reloadSurfaces();
    await _pumpFrames(tester);

    final changed = _canonicalEvents(await _capturedEvents(requests));
    final changedVisible = find.text('Actually changed').evaluate().length;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(
      unchanged,
      isEmpty,
      reason: 'different transport bytes encode the same document',
    );
    expect(changed, hasLength(1));
    expect(
      changed.single['surfaceSessionId'],
      isNot(initial['surfaceSessionId']),
    );
    expect(changedVisible, 1);
  });

  testWidgets(
      'same analytics authority preserves active child attribution without a '
      'duplicate canonical root', (tester) async {
    final requests = <http.Request>[];
    _configureAnalytics(requests);
    final child = childScreenFlow(text: 'Child');

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestageSurfaceFlow<FirstRunResult>(
          flow: _messageFlowRef,
          resolver: ControlledInitialSubFlowResolver(
            root: initialSubFlowRoot(
              child: child,
              assignment: _rootAssignment,
            ),
            child: Completer<ResolvedFlow>()..complete(child),
          ),
          unavailable: const FlowUnavailablePolicy.hide(),
        ),
      ),
    );
    await _pumpFrames(tester);
    final initial = _canonicalEvents(await _capturedEvents(requests)).single;
    requests.clear();

    Restage.configure(apiKey: 'rs_pk_test', baseUrl: _baseUrl);
    await tester.tap(find.text('Child'));
    await _pumpFrames(tester);

    final events = await _capturedEvents(requests);
    expect(_canonicalEvents(events), isEmpty);
    final outcome = events.firstWhere(
      (event) => event['name'] == 'flow_completed',
    );
    expect(outcome['surface'], 'message');
    expect(outcome['surfaceId'], 'first_run');
    expect(outcome['surfaceVersion'], '1');
    expect(outcome['surfaceSessionId'], initial['surfaceSessionId']);
    expect(outcome['experimentId'], 'exp-root');
    expect(outcome['variantId'], 'variant-b');
    expect(outcome['experimentEpoch'], 7);
  });

  testWidgets('same analytics authority does not strand a pending root',
      (tester) async {
    final requests = <http.Request>[];
    _configureAnalytics(requests);
    final pending = Completer<ResolvedFlow>();
    final resolver = _ControlledResolver(
      pending,
      resolvedFlow(welcomeText: 'Unexpected retry'),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestageSurfaceFlow<FirstRunResult>(
          flow: _messageFlowRef,
          resolver: resolver,
          unavailable: const FlowUnavailablePolicy.hide(),
        ),
      ),
    );
    await tester.pump();
    Restage.configure(apiKey: 'rs_pk_test', baseUrl: _baseUrl);
    pending.complete(
      _withAssignment(
        resolvedFlow(welcomeText: 'Accepted pending'),
        _rootAssignment,
      ),
    );
    await _pumpFrames(tester);

    expect(resolver.calls, 1);
    expect(find.text('Accepted pending'), findsOneWidget);
    expect(
      _canonicalEvents(await _capturedEvents(requests)),
      hasLength(1),
    );
  });

  testWidgets(
      'changed analytics authority rejects a pending root and only its retry '
      'emits canonical presentation', (tester) async {
    final requests = <http.Request>[];
    _configureAnalytics(requests);
    final pending = Completer<ResolvedFlow>();
    const retryAssignment = FlowAssignment(
      experimentId: 'exp-new-authority',
      variantId: 'variant-new',
      experimentEpoch: 11,
    );
    final resolver = _ControlledResolver(
      pending,
      _withAssignment(
        resolvedFlow(welcomeText: 'Accepted retry'),
        retryAssignment,
      ),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestageSurfaceFlow<FirstRunResult>(
          flow: _messageFlowRef,
          resolver: resolver,
          unavailable: const FlowUnavailablePolicy.hide(),
        ),
      ),
    );
    await tester.pump();
    Restage.configure(apiKey: 'rs_pk_changed', baseUrl: _baseUrl);
    pending.complete(
      _withAssignment(
        resolvedFlow(welcomeText: 'Rejected old authority'),
        _rootAssignment,
      ),
    );
    await _pumpFrames(tester);

    final presentations = _canonicalEvents(await _capturedEvents(requests));
    expect(resolver.calls, 2);
    expect(find.text('Rejected old authority'), findsNothing);
    expect(find.text('Accepted retry'), findsOneWidget);
    expect(presentations, hasLength(1));
    expect(presentations.single['experimentId'], 'exp-new-authority');
    expect(presentations.single['variantId'], 'variant-new');
    expect(presentations.single['experimentEpoch'], 11);
  });

  testWidgets(
      'changed analytics authority anonymizes still-visible old UI until '
      'remount', (tester) async {
    final requests = <http.Request>[];
    _configureAnalytics(requests);
    final assigned = _withAssignment(resolvedFlow(), _rootAssignment);

    Widget surface(Key key) => Directionality(
          textDirection: TextDirection.ltr,
          child: RestageSurfaceFlow<FirstRunResult>(
            key: key,
            flow: _messageFlowRef,
            resolver: StaticFlowResolver(assigned),
            unavailable: const FlowUnavailablePolicy.hide(),
          ),
        );

    await tester.pumpWidget(surface(const ValueKey<String>('authority-a')));
    await _pumpFrames(tester);
    final initial = _canonicalEvents(await _capturedEvents(requests)).single;
    requests.clear();

    Restage.configure(apiKey: 'rs_pk_changed', baseUrl: _baseUrl);
    await tester.tap(find.text('Welcome'));
    await _pumpFrames(tester);
    final oldUiOutcome = (await _capturedEvents(requests)).firstWhere(
      (event) => event['name'] == 'onboarding_step_viewed',
    );
    expect(oldUiOutcome['surface'], 'message');
    expect(oldUiOutcome['surfaceId'], 'first_run');
    expect(oldUiOutcome['surfaceVersion'], isNull);
    expect(oldUiOutcome['surfaceSessionId'], isNull);
    expect(oldUiOutcome['experimentId'], isNull);
    expect(oldUiOutcome['variantId'], isNull);
    expect(oldUiOutcome['experimentEpoch'], isNull);
    requests.clear();

    await tester.pumpWidget(surface(const ValueKey<String>('authority-b')));
    await _pumpFrames(tester);
    final remounted = _canonicalEvents(await _capturedEvents(requests)).single;
    expect(remounted['surfaceSessionId'], isNot(initial['surfaceSessionId']));
    expect(remounted['experimentId'], 'exp-root');
    expect(remounted['variantId'], 'variant-b');
    expect(remounted['experimentEpoch'], 7);
  });
}

void _configureAnalytics(List<http.Request> requests) {
  Restage.debugAnalyticsHttpClient = MockClient((request) async {
    requests.add(request);
    return http.Response('', 200);
  });
  Restage.configure(apiKey: 'rs_pk_test', baseUrl: _baseUrl);
}

ResolvedFlow _withAssignment(
  ResolvedFlow flow,
  FlowAssignment assignment,
) =>
    ResolvedFlow(
      document: flow.document,
      screenBlobs: flow.screenBlobs,
      cacheHit: flow.cacheHit,
      assignment: assignment,
    );

ResolvedFlow _withTransportHash(ResolvedFlow flow, String rawDocument) =>
    ResolvedFlow(
      document: flow.document,
      screenBlobs: flow.screenBlobs,
      contentHash: FlowContentHash.computeString(rawDocument),
      cacheHit: flow.cacheHit,
      assignment: flow.assignment,
    );

Future<List<Map<String, Object?>>> _capturedEvents(
  List<http.Request> requests,
) async {
  await Restage.debugFlushAnalytics();
  return _analyticsEvents(requests);
}

List<Map<String, Object?>> _analyticsEvents(List<http.Request> requests) =>
    <Map<String, Object?>>[
      for (final request in requests)
        for (final event in (jsonDecode(request.body)
            as Map<String, Object?>)['events']! as List)
          (event! as Map).cast<String, Object?>(),
    ];

List<Map<String, Object?>> _canonicalEvents(
  List<Map<String, Object?>> events,
) =>
    events.where((event) => event['name'] == 'surface_presented').toList();

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i += 1) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

ResolvedFlow _brokenFlow(String welcomeText) {
  final good = resolvedFlow(welcomeText: welcomeText);
  return ResolvedFlow(
    document: good.document,
    screenBlobs: <String, Uint8List>{
      for (final entry in good.screenBlobs.entries)
        entry.key: entry.key == good.document.initial
            ? Uint8List.fromList(const <int>[9, 9, 9, 9])
            : entry.value,
    },
    cacheHit: false,
  );
}

abstract final class _ControlledPaintFailure {
  static int paintAttempts = 0;
}
