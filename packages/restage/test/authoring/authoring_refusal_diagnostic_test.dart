import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/analytics/render_event_privacy.dart';
import 'package:restage/src/authoring/authoring_refusal_diagnostic.dart';
import 'package:restage/src/authoring/onboarding_event_dispatcher.dart'
    show RestageFlowEventRegistration;

const String _authoredSentinel = 'authored-private-value';
const String _renderingSentinel = 'authored-rendering-private-value';

final class _HostileAuthoredValue {
  @override
  String toString() => throw StateError(_renderingSentinel);
}

String _expectedRefusal(String helper, String reason) =>
    '[restage] $helper refused authored event dispatch: $reason.';

void _expectSafeRefusal(
  VoidCallback callback, {
  required String helper,
  required String reason,
}) {
  Object? failure;
  try {
    callback();
  } on Object catch (error) {
    failure = error;
  }

  expect(failure, isA<AssertionError>());
  final message = (failure! as AssertionError).message;
  expect(message, _expectedRefusal(helper, reason));
  expect(message, isNot(contains(_authoredSentinel)));
  expect(message, isNot(contains(_renderingSentinel)));
}

SurfaceEvent<Object?> _surfaceProbe() =>
    const SurfaceEvent<Object?>(_authoredSentinel);

OnboardingEvent<Object?> _onboardingProbe() =>
    const OnboardingEvent<Object?>(_authoredSentinel);

Future<
    ({
      VoidCallback callback,
      bool Function() handlerWasCalled,
      bool Function() eventWasRun,
    })> _captureControllerRefusal(
  WidgetTester tester,
  VoidCallback Function(BuildContext context) capture,
) async {
  late VoidCallback callback;
  var handlerWasCalled = false;
  var eventWasRun = false;
  final acceptedController = Object();
  final rejectedController = Object();
  late final SurfaceEventHandler handler;
  handler = (_, __) {
    handlerWasCalled = true;
    RestageFlowRenderEventPrivacyRegistry.runControllerEvent(
      controller: rejectedController,
      body: () => eventWasRun = true,
    );
  };

  await tester.pumpWidget(
    RestageEventDispatcher(
      onEvent: handler,
      child: RestageFlowEventRegistration(
        controller: acceptedController,
        registration: Object(),
        contentToken: Object(),
        associatedHandler: handler,
        isCurrent: () => true,
        mayExposeNonEmptyHostContext: () => false,
        child: Builder(
          builder: (context) {
            callback = capture(context);
            return const SizedBox();
          },
        ),
      ),
    ),
  );

  return (
    callback: callback,
    handlerWasCalled: () => handlerWasCalled,
    eventWasRun: () => eventWasRun,
  );
}

String _helperName(AuthoringHelperKind helper) => switch (helper) {
      AuthoringHelperKind.paywallEvent => 'paywallEvent',
      AuthoringHelperKind.surfaceEvent => 'surfaceEvent',
      AuthoringHelperKind.onboardingEvent => 'onboardingEvent',
      AuthoringHelperKind.surfaceEventWithContext => 'surfaceEventWithContext',
    };

String _refusalReason(AuthoringRefusalKind refusal) => switch (refusal) {
      AuthoringRefusalKind.missingDispatcher => 'no dispatcher is available',
      AuthoringRefusalKind.ambiguousDispatcher =>
        'dispatcher ownership is ambiguous',
      AuthoringRefusalKind.callbackRefused =>
        'callback dispatch is not admitted',
    };

void main() {
  group('missing dispatcher diagnostics', () {
    testWidgets('paywallEvent omits authored details', (tester) async {
      final callback = paywallEvent(
        _authoredSentinel,
        args: <String, Object?>{
          'tag': _authoredSentinel,
          'value': _HostileAuthoredValue(),
        },
      );

      _expectSafeRefusal(
        callback,
        helper: 'paywallEvent',
        reason: 'no dispatcher is available',
      );
    });

    testWidgets('surfaceEvent omits authored details', (tester) async {
      final callback = surfaceEvent(
        _surfaceProbe(),
        _HostileAuthoredValue(),
      );

      _expectSafeRefusal(
        callback,
        helper: 'surfaceEvent',
        reason: 'no dispatcher is available',
      );
    });

    testWidgets('onboardingEvent omits authored details', (tester) async {
      final callback = onboardingEvent(
        _onboardingProbe(),
        _HostileAuthoredValue(),
      );

      _expectSafeRefusal(
        callback,
        helper: 'onboardingEvent',
        reason: 'no dispatcher is available',
      );
    });

    testWidgets('surfaceEventWithContext omits authored details',
        (tester) async {
      late VoidCallback callback;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            callback = surfaceEventWithContext(
              context,
              _surfaceProbe(),
              _HostileAuthoredValue(),
            );
            return const SizedBox();
          },
        ),
      );

      _expectSafeRefusal(
        callback,
        helper: 'surfaceEventWithContext',
        reason: 'no dispatcher is available',
      );
    });
  });

  group('ambiguous dispatcher diagnostics', () {
    testWidgets('paywallEvent omits authored details', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: <Widget>[
              RestagePaywallEventDispatcher(
                onEvent: (_, __) {},
                child: const SizedBox(),
              ),
              RestagePaywallEventDispatcher(
                onEvent: (_, __) {},
                child: const SizedBox(),
              ),
            ],
          ),
        ),
      );
      final callback = paywallEvent(
        _authoredSentinel,
        args: <String, Object?>{
          'tag': _authoredSentinel,
          'value': _HostileAuthoredValue(),
        },
      );

      _expectSafeRefusal(
        callback,
        helper: 'paywallEvent',
        reason: 'dispatcher ownership is ambiguous',
      );
    });

    testWidgets('surfaceEvent omits authored details', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: <Widget>[
              RestageEventDispatcher(
                onEvent: (_, __) {},
                child: const SizedBox(),
              ),
              RestageEventDispatcher(
                onEvent: (_, __) {},
                child: const SizedBox(),
              ),
            ],
          ),
        ),
      );
      final callback = surfaceEvent(
        _surfaceProbe(),
        _HostileAuthoredValue(),
      );

      _expectSafeRefusal(
        callback,
        helper: 'surfaceEvent',
        reason: 'dispatcher ownership is ambiguous',
      );
    });

    testWidgets('onboardingEvent omits authored details', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: <Widget>[
              RestageEventDispatcher(
                onEvent: (_, __) {},
                child: const SizedBox(),
              ),
              RestageEventDispatcher(
                onEvent: (_, __) {},
                child: const SizedBox(),
              ),
            ],
          ),
        ),
      );
      final callback = onboardingEvent(
        _onboardingProbe(),
        _HostileAuthoredValue(),
      );

      _expectSafeRefusal(
        callback,
        helper: 'onboardingEvent',
        reason: 'dispatcher ownership is ambiguous',
      );
    });

    testWidgets('surfaceEventWithContext omits authored details',
        (tester) async {
      late VoidCallback callback;
      final controller = Object();
      final registration = Object();
      final content = Object();
      void mountedHandler(String _, Object? __) {}
      void differentHandler(String _, Object? __) {}

      await tester.pumpWidget(
        RestageEventDispatcher(
          onEvent: mountedHandler,
          child: RestageFlowEventRegistration(
            controller: controller,
            registration: registration,
            contentToken: content,
            associatedHandler: differentHandler,
            isCurrent: () => true,
            mayExposeNonEmptyHostContext: () => false,
            child: Builder(
              builder: (context) {
                callback = surfaceEventWithContext(
                  context,
                  _surfaceProbe(),
                  _HostileAuthoredValue(),
                );
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      _expectSafeRefusal(
        callback,
        helper: 'surfaceEventWithContext',
        reason: 'dispatcher ownership is ambiguous',
      );
    });
  });

  group('callback-time refusal diagnostics', () {
    testWidgets('paywallEvent omits authored details', (tester) async {
      late VoidCallback callback;
      await tester.pumpWidget(
        RestagePaywallEventDispatcher(
          onEvent: (_, __) {},
          child: Builder(
            builder: (_) {
              callback = paywallEvent(
                _authoredSentinel,
                args: <String, Object?>{
                  'tag': _authoredSentinel,
                  'value': _HostileAuthoredValue(),
                },
              );
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox());

      _expectSafeRefusal(
        callback,
        helper: 'paywallEvent',
        reason: 'callback dispatch is not admitted',
      );
    });

    testWidgets('surfaceEvent omits authored details', (tester) async {
      late VoidCallback callback;
      await tester.pumpWidget(
        RestageEventDispatcher(
          onEvent: (_, __) {},
          child: Builder(
            builder: (_) {
              callback = surfaceEvent(
                _surfaceProbe(),
                _HostileAuthoredValue(),
              );
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox());

      _expectSafeRefusal(
        callback,
        helper: 'surfaceEvent',
        reason: 'callback dispatch is not admitted',
      );
    });

    testWidgets('onboardingEvent omits authored details', (tester) async {
      late VoidCallback callback;
      await tester.pumpWidget(
        RestageEventDispatcher(
          onEvent: (_, __) {},
          child: Builder(
            builder: (_) {
              callback = onboardingEvent(
                _onboardingProbe(),
                _HostileAuthoredValue(),
              );
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox());

      _expectSafeRefusal(
        callback,
        helper: 'onboardingEvent',
        reason: 'callback dispatch is not admitted',
      );
    });

    testWidgets('surfaceEventWithContext omits authored details',
        (tester) async {
      late VoidCallback callback;
      await tester.pumpWidget(
        RestageEventDispatcher(
          onEvent: (_, __) {},
          child: Builder(
            builder: (context) {
              callback = surfaceEventWithContext(
                context,
                _surfaceProbe(),
                _HostileAuthoredValue(),
              );
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox());

      _expectSafeRefusal(
        callback,
        helper: 'surfaceEventWithContext',
        reason: 'callback dispatch is not admitted',
      );
    });

    testWidgets('surfaceEvent omits authored details after admission',
        (tester) async {
      final probe = await _captureControllerRefusal(
        tester,
        (_) => surfaceEvent(
          _surfaceProbe(),
          _HostileAuthoredValue(),
        ),
      );

      _expectSafeRefusal(
        probe.callback,
        helper: 'surfaceEvent',
        reason: 'callback dispatch is not admitted',
      );
      expect(probe.handlerWasCalled(), isTrue);
      expect(probe.eventWasRun(), isFalse);
    });

    testWidgets('onboardingEvent omits authored details after admission',
        (tester) async {
      final probe = await _captureControllerRefusal(
        tester,
        (_) => onboardingEvent(
          _onboardingProbe(),
          _HostileAuthoredValue(),
        ),
      );

      _expectSafeRefusal(
        probe.callback,
        helper: 'onboardingEvent',
        reason: 'callback dispatch is not admitted',
      );
      expect(probe.handlerWasCalled(), isTrue);
      expect(probe.eventWasRun(), isFalse);
    });

    testWidgets(
        'surfaceEventWithContext omits authored details after admission',
        (tester) async {
      final probe = await _captureControllerRefusal(
        tester,
        (context) => surfaceEventWithContext(
          context,
          _surfaceProbe(),
          _HostileAuthoredValue(),
        ),
      );

      _expectSafeRefusal(
        probe.callback,
        helper: 'surfaceEventWithContext',
        reason: 'callback dispatch is not admitted',
      );
      expect(probe.handlerWasCalled(), isTrue);
      expect(probe.eventWasRun(), isFalse);
    });
  });

  test('reporting uses the assertion message', () {
    for (final helper in AuthoringHelperKind.values) {
      for (final refusal in AuthoringRefusalKind.values) {
        Object? assertion;
        try {
          reportAuthoringRefusal(
            helper: helper,
            refusal: refusal,
            throwOnRefusal: true,
          );
        } on Object catch (error) {
          assertion = error;
        }

        final reports = <FlutterErrorDetails>[];
        reportAuthoringRefusal(
          helper: helper,
          refusal: refusal,
          throwOnRefusal: false,
          reportError: reports.add,
        );

        final expected = _expectedRefusal(
          _helperName(helper),
          _refusalReason(refusal),
        );
        expect(assertion, isA<AssertionError>());
        expect((assertion! as AssertionError).message, expected);
        expect(reports, hasLength(1));
        expect(reports.single.exception, isA<StateError>());
        expect((reports.single.exception as StateError).message, expected);
      }
    }
  });
}
