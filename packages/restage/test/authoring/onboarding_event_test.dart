import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

import '../support/static_analysis_probe.dart';

abstract final class WelcomeScreen {
  static const next = OnboardingEvent<void>('next');
  static const age = OnboardingEvent<int>('age');
  static const close = SurfaceEvent<void>('close');
}

final class _ContextBoundCallbackProbe extends StatelessWidget {
  const _ContextBoundCallbackProbe({required this.onBuilt});

  final ValueChanged<VoidCallback> onBuilt;

  @override
  Widget build(BuildContext context) {
    onBuilt(context.surfaceEvent(WelcomeScreen.close));
    return const SizedBox();
  }
}

void main() {
  test('OnboardingEvent stores the event id and type', () {
    const event = OnboardingEvent<void>('next');

    expect(event.id, 'next');
    expect(event, isA<OnboardingEvent<void>>());
  });

  test('SurfaceEvent stores the event id and keeps the event type', () {
    const event = SurfaceEvent<void>('close');

    expect(event.id, 'close');
    expect(event, isA<SurfaceEvent<void>>());
    expect(event, isA<OnboardingEvent<void>>());
  });

  testWidgets('an onboarding event dispatches through its dispatcher',
      (tester) async {
    String? receivedEventId;
    Object? receivedValue;
    VoidCallback? captured;

    await tester.pumpWidget(RestageEventDispatcher(
      onEvent: (eventId, value) {
        receivedEventId = eventId;
        receivedValue = value;
      },
      child: Builder(builder: (context) {
        captured = context.surfaceEvent(WelcomeScreen.next);
        return const SizedBox();
      }),
    ));

    captured!();

    expect(receivedEventId, 'next');
    expect(receivedValue, isNull);
  });

  testWidgets('an onboarding event dispatches a typed payload', (tester) async {
    String? receivedEventId;
    Object? receivedValue;
    VoidCallback? captured;

    await tester.pumpWidget(RestageEventDispatcher(
      onEvent: (eventId, value) {
        receivedEventId = eventId;
        receivedValue = value;
      },
      child: Builder(builder: (context) {
        captured = context.surfaceEvent(WelcomeScreen.age, 42);
        return const SizedBox();
      }),
    ));

    captured!();

    expect(receivedEventId, 'age');
    expect(receivedValue, 42);
  });

  testWidgets('context.surfaceEvent dispatches through its dispatcher',
      (tester) async {
    String? receivedEventId;
    Object? receivedValue;
    VoidCallback? captured;

    await tester.pumpWidget(RestageEventDispatcher(
      onEvent: (eventId, value) {
        receivedEventId = eventId;
        receivedValue = value;
      },
      child: Builder(builder: (context) {
        captured = context.surfaceEvent(WelcomeScreen.close);
        return const SizedBox();
      }),
    ));

    captured!();

    expect(receivedEventId, 'close');
    expect(receivedValue, isNull);
  });

  testWidgets('context-bound surface events use their nearest dispatcher',
      (tester) async {
    final routed = <String>[];
    late VoidCallback outer;
    late VoidCallback inner;
    late VoidCallback sibling;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: <Widget>[
            RestageEventDispatcher(
              onEvent: (_, __) => routed.add('outer'),
              child: Builder(
                builder: (outerContext) {
                  outer = outerContext.surfaceEvent(
                    WelcomeScreen.close,
                  );
                  return RestageEventDispatcher(
                    onEvent: (_, __) => routed.add('inner'),
                    child: Builder(
                      builder: (innerContext) {
                        inner = innerContext.surfaceEvent(
                          WelcomeScreen.close,
                        );
                        return const SizedBox();
                      },
                    ),
                  );
                },
              ),
            ),
            RestageEventDispatcher(
              onEvent: (_, __) => routed.add('sibling'),
              child: Builder(
                builder: (context) {
                  sibling = context.surfaceEvent(
                    WelcomeScreen.close,
                  );
                  return const SizedBox();
                },
              ),
            ),
          ],
        ),
      ),
    );

    outer();
    inner();
    sibling();

    expect(routed, <String>['outer', 'inner', 'sibling']);
  });

  testWidgets(
      'context-bound callbacks reach a replacement handler without a rebuild',
      (tester) async {
    final routed = <String>[];
    late StateSetter updateHost;
    late VoidCallback currentCallback;
    var handler = 'first';
    var descendantBuilds = 0;
    final child = _ContextBoundCallbackProbe(
      onBuilt: (callback) {
        descendantBuilds += 1;
        currentCallback = callback;
      },
    );

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          updateHost = setState;
          final destination = handler;
          return RestageEventDispatcher(
            onEvent: (_, __) => routed.add(destination),
            child: child,
          );
        },
      ),
    );

    currentCallback();
    updateHost(() => handler = 'second');
    await tester.pump();
    currentCallback();

    expect(routed, <String>['first', 'second']);
    // The lookup does not depend on the dispatcher, so nothing rebuilds.
    expect(descendantBuilds, 1);
  });

  testWidgets('context surface events go to the dispatcher that built them',
      (tester) async {
    late StateSetter rebuildFirst;
    VoidCallback? captured;
    var shouldCapture = false;
    final routed = <String>[];

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: <Widget>[
            RestageEventDispatcher(
              onEvent: (_, __) => routed.add('first'),
              child: StatefulBuilder(
                builder: (context, setState) {
                  rebuildFirst = setState;
                  if (shouldCapture) {
                    captured = context.surfaceEvent(WelcomeScreen.close);
                  }
                  return const SizedBox();
                },
              ),
            ),
            RestageEventDispatcher(
              onEvent: (_, __) => routed.add('second'),
              child: const SizedBox(),
            ),
          ],
        ),
      ),
    );

    shouldCapture = true;
    rebuildFirst(() {});
    await tester.pump();

    expect(captured, isNotNull);
    captured!();
    expect(routed, <String>['first']);
  });

  test('surfaceEvent rejects the wrong payload type statically', () async {
    final result = await staticAnalysisErrors(
      fileName: 'wrong_onboarding_event_payload.dart',
      source: '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

void probe(BuildContext context) {
  const age = OnboardingEvent<int>('age');
  context.surfaceEvent(age, 'forty-two');
}
''',
    );

    expect(
      result.map((d) => d.diagnosticCode.lowerCaseName),
      ['could_not_infer'],
      reason: describeDiagnostics(result),
    );
    expect(result.single.message, contains("'String'"));
    expect(result.single.message, contains("'int'"));
  }, timeout: staticAnalysisTimeout);

  testWidgets('context.surfaceEvent with no dispatcher mounted asserts/reports',
      (tester) async {
    late VoidCallback callback;
    await tester.pumpWidget(Builder(builder: (context) {
      callback = context.surfaceEvent(WelcomeScreen.next);
      return const SizedBox();
    }));

    expect(callback, isA<VoidCallback>());
    expect(callback, throwsAssertionError);
  });

  testWidgets('context.surfaceEvent refuses after its dispatcher is disposed',
      (tester) async {
    String? routedTo;
    VoidCallback? captured;

    await tester.pumpWidget(RestageEventDispatcher(
      onEvent: (eventId, value) => routedTo = 'A',
      child: Builder(builder: (context) {
        captured = context.surfaceEvent(WelcomeScreen.next);
        return const SizedBox();
      }),
    ));

    await tester.pumpWidget(RestageEventDispatcher(
      onEvent: (eventId, value) => routedTo = 'B',
      child: const SizedBox(),
    ));

    expect(captured!, throwsAssertionError);

    expect(routedTo, isNull);
  });
}
