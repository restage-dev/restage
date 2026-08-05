import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

import 'flow_test_support.dart';

const _messageFlowRef = SurfaceFlowRef<FirstRunResult>(
  id: 'first_run',
  version: 1,
  minClient: 3,
  surfaceType: SurfaceType.message,
  decodeResult: FirstRunResult.decode,
);

const _surveyFlowRef = SurfaceFlowRef<FirstRunResult>(
  id: 'first_run',
  version: 1,
  minClient: 3,
  surfaceType: SurfaceType.survey,
  decodeResult: FirstRunResult.decode,
);

const _messageSecondFlowRef = SurfaceFlowRef<FirstRunResult>(
  id: 'second_run',
  version: 1,
  minClient: 3,
  surfaceType: SurfaceType.message,
  decodeResult: FirstRunResult.decode,
);

const _surveySecondFlowRef = SurfaceFlowRef<FirstRunResult>(
  id: 'second_run',
  version: 1,
  minClient: 3,
  surfaceType: SurfaceType.survey,
  decodeResult: FirstRunResult.decode,
);

final class _RecordingResolver implements FlowResolver {
  _RecordingResolver(this.resolved);

  final ResolvedFlow resolved;
  final requested = <SurfaceFlowRef<Object?>>[];

  @override
  Future<ResolvedFlow> resolve<R>(SurfaceFlowRef<R> flow) async {
    requested.add(flow);
    return resolved;
  }
}

final class _RecordingChannel implements SurfaceUpdateChannel {
  final watched = <SurfaceRef>[];

  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) {
    watched.add(surface);
    return const Stream<SurfaceUpdate>.empty();
  }
}

final class _ControlledChannel implements SurfaceUpdateChannel {
  final watches = <_ControlledWatch>[];

  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) {
    final watch = _ControlledWatch(surface);
    watches.add(watch);
    return watch;
  }

  void completeCancellations() {
    for (final watch in watches) {
      watch.completeCancellation();
    }
  }
}

final class _ControlledWatch extends Stream<SurfaceUpdate> {
  _ControlledWatch(this.surface);

  final SurfaceRef surface;
  _ControlledSubscription? _subscription;

  bool get cancellationRequested =>
      _subscription?.cancellationRequested ?? false;

  void emit() {
    _subscription?.emit(SurfaceUpdate(surface));
  }

  void completeCancellation() {
    _subscription?.completeCancellation();
  }

  @override
  StreamSubscription<SurfaceUpdate> listen(
    void Function(SurfaceUpdate event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final subscription = _ControlledSubscription(onData);
    _subscription = subscription;
    return subscription;
  }
}

final class _ControlledSubscription
    implements StreamSubscription<SurfaceUpdate> {
  _ControlledSubscription(this._onData);

  void Function(SurfaceUpdate event)? _onData;
  bool cancellationRequested = false;
  bool _isPaused = false;
  bool _acceptQueuedEvents = true;

  void emit(SurfaceUpdate update) {
    if (_acceptQueuedEvents) _onData?.call(update);
  }

  void completeCancellation() {
    _acceptQueuedEvents = false;
  }

  @override
  Future<void> cancel() {
    cancellationRequested = true;
    return Future<void>.value();
  }

  @override
  bool get isPaused => _isPaused;

  @override
  void onData(void Function(SurfaceUpdate data)? handleData) {
    _onData = handleData;
  }

  @override
  void onError(Function? handleError) {}

  @override
  void onDone(void Function()? handleDone) {}

  @override
  void pause([Future<void>? resumeSignal]) {
    _isPaused = true;
    resumeSignal?.whenComplete(resume);
  }

  @override
  void resume() {
    _isPaused = false;
  }

  @override
  Future<E> asFuture<E>([E? futureValue]) async {
    return futureValue as E;
  }
}

void main() {
  setUp(Restage.debugReset);

  test('RestageSurfaceFlow exposes the neutral public configuration surface',
      () {
    final resolver = _RecordingResolver(resolvedFlow());
    final widget = RestageSurfaceFlow<FirstRunResult>(
      flow: _messageFlowRef,
      initialState: null,
      unavailable: const FlowUnavailablePolicy.hide(),
      actions: null,
      installedSignalNames: const {'signal'},
      resolver: resolver,
      onFlowUnavailable: (_) {},
      onComplete: (_) {},
      loadingBuilder: (_) => const Text('loading'),
      transition: null,
      systemBack: SystemBackPolicy.popHost,
      enableSkip: true,
      chromeTheme: null,
      persistentChrome: false,
      backBuilder: null,
      skipBuilder: null,
      chromeBuilder: null,
      persistentChromeBuilder: null,
      priceQueries: const {},
      liveRefresh: const {},
    );

    expect(widget.flow, _messageFlowRef);
    expect(widget.resolver, same(resolver));
    expect(widget.installedSignalNames, {'signal'});
    expect(widget.enableSkip, isTrue);
    expect(widget.persistentChrome, isFalse);
  });

  for (final testCase in const [
    (surface: SurfaceType.message, ref: _messageFlowRef),
    (surface: SurfaceType.survey, ref: _surveyFlowRef),
  ]) {
    testWidgets(
        'RestageSurfaceFlow renders a ${testCase.surface.wireName} descriptor '
        'through the supplied resolver', (tester) async {
      final resolver = _RecordingResolver(
        resolvedFlow(welcomeText: '${testCase.surface.wireName} welcome'),
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RestageSurfaceFlow<FirstRunResult>(
            flow: testCase.ref,
            resolver: resolver,
            unavailable: const FlowUnavailablePolicy.hide(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('${testCase.surface.wireName} welcome'),
        findsOneWidget,
      );
      expect(resolver.requested.single, same(testCase.ref));
      expect(resolver.requested.single.surfaceType, testCase.surface);
    });
  }

  testWidgets('equal flow slugs keep message and survey refresh identity apart',
      (tester) async {
    final channel = _RecordingChannel();
    final resolver = _RecordingResolver(resolvedFlow());
    Restage.configure(
      apiKey: 'rs_pk_test',
      analyticsEnabled: false,
      flowResolver: resolver,
      liveRefresh: const {SurfaceRefreshTrigger.updateChannel},
      updateChannel: channel,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            RestageSurfaceFlow<FirstRunResult>(
              flow: _messageFlowRef,
              unavailable: const FlowUnavailablePolicy.hide(),
            ),
            RestageSurfaceFlow<FirstRunResult>(
              flow: _surveyFlowRef,
              unavailable: const FlowUnavailablePolicy.hide(),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      channel.watched,
      const [
        SurfaceRef(surfaceType: 'message', slug: 'first_run'),
        SurfaceRef(surfaceType: 'survey', slug: 'first_run'),
      ],
    );
  });

  testWidgets(
      'retained host replaces and fences refresh on same-surface slug change',
      (tester) async {
    final channel = _ControlledChannel();
    addTearDown(channel.completeCancellations);
    final resolver = _RecordingResolver(resolvedFlow());
    var flow = _messageFlowRef;
    late StateSetter updateHost;
    Restage.configure(
      apiKey: 'rs_pk_test',
      analyticsEnabled: false,
      flowResolver: resolver,
      liveRefresh: const {SurfaceRefreshTrigger.updateChannel},
      updateChannel: channel,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return RestageSurfaceFlow<FirstRunResult>(
              flow: flow,
              unavailable: const FlowUnavailablePolicy.hide(),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(resolver.requested, [_messageFlowRef]);

    updateHost(() => flow = _messageSecondFlowRef);
    await tester.pumpAndSettle();

    expect(
      channel.watches.map((watch) => watch.surface),
      const [
        SurfaceRef(surfaceType: 'message', slug: 'first_run'),
        SurfaceRef(surfaceType: 'message', slug: 'second_run'),
      ],
    );
    expect(channel.watches.first.cancellationRequested, isTrue);
    expect(resolver.requested, [_messageFlowRef, _messageSecondFlowRef]);

    channel.watches.first.emit();
    await tester.pumpAndSettle();
    expect(resolver.requested, [_messageFlowRef, _messageSecondFlowRef]);

    channel.watches.last.emit();
    await tester.pumpAndSettle();
    expect(
      resolver.requested,
      [_messageFlowRef, _messageSecondFlowRef, _messageSecondFlowRef],
    );
  });

  testWidgets(
      'retained host replaces and fences refresh across surface and slug',
      (tester) async {
    final channel = _ControlledChannel();
    addTearDown(channel.completeCancellations);
    final resolver = _RecordingResolver(resolvedFlow());
    var flow = _messageFlowRef;
    late StateSetter updateHost;
    Restage.configure(
      apiKey: 'rs_pk_test',
      analyticsEnabled: false,
      flowResolver: resolver,
      liveRefresh: const {SurfaceRefreshTrigger.updateChannel},
      updateChannel: channel,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return RestageSurfaceFlow<FirstRunResult>(
              flow: flow,
              unavailable: const FlowUnavailablePolicy.hide(),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    updateHost(() => flow = _surveySecondFlowRef);
    await tester.pumpAndSettle();

    expect(
      channel.watches.map((watch) => watch.surface),
      const [
        SurfaceRef(surfaceType: 'message', slug: 'first_run'),
        SurfaceRef(surfaceType: 'survey', slug: 'second_run'),
      ],
    );
    channel.watches.first.emit();
    await tester.pumpAndSettle();
    expect(resolver.requested, [_messageFlowRef, _surveySecondFlowRef]);

    channel.watches.last.emit();
    await tester.pumpAndSettle();
    expect(
      resolver.requested,
      [_messageFlowRef, _surveySecondFlowRef, _surveySecondFlowRef],
    );
  });

  testWidgets(
      'retained host keeps equal slugs separated across surface replacement',
      (tester) async {
    final channel = _ControlledChannel();
    addTearDown(channel.completeCancellations);
    final resolver = _RecordingResolver(resolvedFlow());
    var flow = _messageFlowRef;
    late StateSetter updateHost;
    Restage.configure(
      apiKey: 'rs_pk_test',
      analyticsEnabled: false,
      flowResolver: resolver,
      liveRefresh: const {SurfaceRefreshTrigger.updateChannel},
      updateChannel: channel,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return RestageSurfaceFlow<FirstRunResult>(
              flow: flow,
              unavailable: const FlowUnavailablePolicy.hide(),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    updateHost(() => flow = _surveyFlowRef);
    await tester.pumpAndSettle();

    expect(
      channel.watches.map((watch) => watch.surface),
      const [
        SurfaceRef(surfaceType: 'message', slug: 'first_run'),
        SurfaceRef(surfaceType: 'survey', slug: 'first_run'),
      ],
    );
    channel.watches.first.emit();
    await tester.pumpAndSettle();
    expect(resolver.requested, [_messageFlowRef, _surveyFlowRef]);
  });

  testWidgets('retained host replaces refresh when live triggers change',
      (tester) async {
    final channel = _ControlledChannel();
    addTearDown(channel.completeCancellations);
    final resolver = _RecordingResolver(resolvedFlow());
    var liveRefresh = const {SurfaceRefreshTrigger.updateChannel};
    late StateSetter updateHost;
    Restage.configure(
      apiKey: 'rs_pk_test',
      analyticsEnabled: false,
      flowResolver: resolver,
      updateChannel: channel,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return RestageSurfaceFlow<FirstRunResult>(
              flow: _messageFlowRef,
              liveRefresh: liveRefresh,
              unavailable: const FlowUnavailablePolicy.hide(),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    updateHost(() => liveRefresh = const {});
    await tester.pumpAndSettle();
    expect(channel.watches, hasLength(1));
    expect(channel.watches.first.cancellationRequested, isTrue);

    channel.watches.first.emit();
    await tester.pumpAndSettle();
    expect(resolver.requested, [_messageFlowRef]);

    updateHost(
      () => liveRefresh = const {SurfaceRefreshTrigger.updateChannel},
    );
    await tester.pumpAndSettle();
    expect(channel.watches, hasLength(2));

    channel.watches.last.emit();
    await tester.pumpAndSettle();
    expect(resolver.requested, [_messageFlowRef, _messageFlowRef]);
  });

  testWidgets('retained host replaces refresh when stampability changes',
      (tester) async {
    final channel = _ControlledChannel();
    addTearDown(channel.completeCancellations);
    final defaultResolver = _RecordingResolver(resolvedFlow());
    final customResolver = _RecordingResolver(resolvedFlow());
    FlowResolver? widgetResolver;
    late StateSetter updateHost;
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'https://surfaces.example.com',
      analyticsEnabled: false,
      flowResolver: defaultResolver,
      liveRefresh: const {SurfaceRefreshTrigger.updateChannel},
      updateChannel: channel,
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return RestageSurfaceFlow<FirstRunResult>(
              flow: _messageFlowRef,
              resolver: widgetResolver,
              unavailable: const FlowUnavailablePolicy.hide(),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    updateHost(() => widgetResolver = customResolver);
    await tester.pumpAndSettle();

    expect(channel.watches, hasLength(2));
    expect(channel.watches.first.cancellationRequested, isTrue);
    expect(defaultResolver.requested, [_messageFlowRef]);
    expect(customResolver.requested, [_messageFlowRef]);

    channel.watches.first.emit();
    await tester.pumpAndSettle();
    expect(defaultResolver.requested, [_messageFlowRef]);
    expect(customResolver.requested, [_messageFlowRef]);

    channel.watches.last.emit();
    await tester.pumpAndSettle();
    expect(customResolver.requested, [_messageFlowRef, _messageFlowRef]);
  });

  testWidgets(
      'RestageOnboarding rejects a message descriptor once with fallback and '
      'does no resolver or refresh work', (tester) async {
    final channel = _RecordingChannel();
    final resolver = _RecordingResolver(resolvedFlow());
    var unavailableCalls = 0;
    var completionCalls = 0;
    Restage.configure(
      apiKey: 'rs_pk_test',
      analyticsEnabled: false,
      liveRefresh: const {SurfaceRefreshTrigger.updateChannel},
      updateChannel: channel,
    );

    Widget host() => Directionality(
          textDirection: TextDirection.ltr,
          child: RestageOnboarding<FirstRunResult>(
            flow: _messageFlowRef,
            resolver: resolver,
            unavailable: FlowUnavailablePolicy.fallback(
              builder: (_, error) => Text(error.reason),
            ),
            onFlowUnavailable: (error) {
              unavailableCalls++;
              expect(error.reason, 'unsupported_surface_type');
            },
            onComplete: (_) => completionCalls++,
          ),
        );

    await tester.pumpWidget(host());
    await tester.pump();

    expect(find.text('unsupported_surface_type'), findsOneWidget);
    expect(unavailableCalls, 1);
    expect(completionCalls, 0);
    expect(resolver.requested, isEmpty);
    expect(channel.watched, isEmpty);

    await tester.pumpWidget(host());
    await tester.pump();

    expect(unavailableCalls, 1);
    expect(resolver.requested, isEmpty);
    expect(channel.watched, isEmpty);
  });

  testWidgets('RestageOnboarding rejects a survey descriptor with hide',
      (tester) async {
    final resolver = _RecordingResolver(resolvedFlow());
    FlowUnavailableError? unavailable;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RestageOnboarding<FirstRunResult>(
          flow: _surveyFlowRef,
          resolver: resolver,
          unavailable: const FlowUnavailablePolicy.hide(),
          onFlowUnavailable: (error) => unavailable = error,
        ),
      ),
    );
    await tester.pump();

    expect(unavailable?.reason, 'unsupported_surface_type');
    expect(find.byType(SizedBox), findsOneWidget);
    expect(resolver.requested, isEmpty);
  });

  testWidgets(
      'unsupported A to B to A before callback drain reports final A once',
      (tester) async {
    final calls = <String>[];
    final resolver = _RecordingResolver(resolvedFlow());
    SurfaceFlowRef<FirstRunResult> flow = firstRunFlowRef;
    late StateSetter updateHost;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return _facade(
              flow,
              resolver: resolver,
              onUnavailable: calls.add,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    updateHost(() => flow = _messageFlowRef);
    tester.binding.drawFrame();
    updateHost(() => flow = _surveyFlowRef);
    tester.binding.drawFrame();
    updateHost(() => flow = _messageFlowRef);
    tester.binding.drawFrame();
    await tester.idle();

    expect(calls, ['message/first_run']);
    expect(resolver.requested, [firstRunFlowRef]);
  });

  testWidgets('unsupported to supported before drain invalidates callback',
      (tester) async {
    final calls = <String>[];
    final resolver = _RecordingResolver(resolvedFlow());
    SurfaceFlowRef<FirstRunResult> flow = firstRunFlowRef;
    late StateSetter updateHost;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return _facade(
              flow,
              resolver: resolver,
              onUnavailable: calls.add,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    updateHost(() => flow = _messageFlowRef);
    tester.binding.drawFrame();
    updateHost(() => flow = firstRunFlowRef);
    tester.binding.drawFrame();
    await tester.idle();
    await tester.pumpAndSettle();

    expect(calls, isEmpty);
    expect(resolver.requested, [firstRunFlowRef, firstRunFlowRef]);
  });

  testWidgets('unmount before unsupported callback drain invalidates callback',
      (tester) async {
    final calls = <String>[];
    final resolver = _RecordingResolver(resolvedFlow());
    var show = true;
    SurfaceFlowRef<FirstRunResult> flow = firstRunFlowRef;
    late StateSetter updateHost;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return show
                ? _facade(
                    flow,
                    resolver: resolver,
                    onUnavailable: calls.add,
                  )
                : const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    updateHost(() => flow = _messageFlowRef);
    tester.binding.drawFrame();
    updateHost(() => show = false);
    tester.binding.drawFrame();
    await tester.idle();

    expect(calls, isEmpty);
    expect(resolver.requested, [firstRunFlowRef]);
  });

  testWidgets(
      'same unsupported identity uses replacement callback without duplicate',
      (tester) async {
    final firstCalls = <String>[];
    final replacementCalls = <String>[];
    final resolver = _RecordingResolver(resolvedFlow());
    SurfaceFlowRef<FirstRunResult> flow = firstRunFlowRef;
    void Function(String identity)? callback;
    late StateSetter updateHost;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return _facade(
              flow,
              resolver: resolver,
              onUnavailable: callback,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    updateHost(() {
      flow = _messageFlowRef;
      callback = firstCalls.add;
    });
    tester.binding.drawFrame();
    updateHost(() => callback = replacementCalls.add);
    tester.binding.drawFrame();
    await tester.idle();
    updateHost(() => callback = replacementCalls.add);
    tester.binding.drawFrame();
    await tester.idle();

    expect(firstCalls, isEmpty);
    expect(replacementCalls, ['message/first_run']);
  });

  testWidgets('delivered unsupported identity change reports each presentation',
      (tester) async {
    final calls = <String>[];
    final resolver = _RecordingResolver(resolvedFlow());
    SurfaceFlowRef<FirstRunResult> flow = firstRunFlowRef;
    late StateSetter updateHost;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return _facade(
              flow,
              resolver: resolver,
              onUnavailable: calls.add,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    updateHost(() => flow = _messageFlowRef);
    tester.binding.drawFrame();
    await tester.idle();
    updateHost(() => flow = _surveySecondFlowRef);
    tester.binding.drawFrame();
    await tester.idle();

    expect(calls, ['message/first_run', 'survey/second_run']);
  });

  testWidgets(
      'supported and unsupported transitions isolate resolver and refresh work',
      (tester) async {
    final calls = <String>[];
    final channel = _ControlledChannel();
    addTearDown(channel.completeCancellations);
    final resolver = _RecordingResolver(resolvedFlow());
    SurfaceFlowRef<FirstRunResult> flow = firstRunFlowRef;
    late StateSetter updateHost;
    Restage.configure(
      apiKey: 'rs_pk_test',
      analyticsEnabled: false,
      liveRefresh: const {SurfaceRefreshTrigger.updateChannel},
      updateChannel: channel,
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return _facade(
              flow,
              resolver: resolver,
              onUnavailable: calls.add,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(resolver.requested, [firstRunFlowRef]);
    expect(channel.watches, hasLength(1));

    updateHost(() => flow = _messageFlowRef);
    tester.binding.drawFrame();
    await tester.idle();
    expect(calls, ['message/first_run']);
    expect(resolver.requested, [firstRunFlowRef]);
    expect(channel.watches, hasLength(1));
    expect(channel.watches.single.cancellationRequested, isTrue);

    updateHost(() => flow = firstRunFlowRef);
    tester.binding.drawFrame();
    await tester.pumpAndSettle();

    expect(resolver.requested, [firstRunFlowRef, firstRunFlowRef]);
    expect(channel.watches, hasLength(2));
    channel.watches.last.emit();
    await tester.pumpAndSettle();
    expect(
      resolver.requested,
      [firstRunFlowRef, firstRunFlowRef, firstRunFlowRef],
    );
  });
}

RestageOnboarding<FirstRunResult> _facade(
  SurfaceFlowRef<FirstRunResult> flow, {
  FlowResolver? resolver,
  void Function(String identity)? onUnavailable,
}) {
  return RestageOnboarding<FirstRunResult>(
    flow: flow,
    resolver: resolver,
    unavailable: const FlowUnavailablePolicy.hide(),
    onFlowUnavailable: (error) {
      onUnavailable?.call('${flow.surfaceType.wireName}/${flow.id}');
    },
  );
}
