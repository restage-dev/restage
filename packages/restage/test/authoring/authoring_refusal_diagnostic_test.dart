import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/authoring/event_dispatch_admission.dart';
import 'package:restage/src/authoring/authoring_refusal_diagnostic.dart';
import 'package:restage/src/authoring/onboarding_event_dispatcher.dart'
    show RestageFlowEventRegistration;

const String _authoredSentinel = 'authored-private-value';
const String _renderingSentinel = 'authored-rendering-private-value';

final class _HostileAuthoredValue {
  @override
  String toString() => throw StateError(_renderingSentinel);
}

const String _contextHint = ' Try calling `context.surfaceEvent(...)` with the '
    'context of the widget that builds the button, inside the surface that '
    'handles the event.';

const String _routeHint = " On a route the surface pushes, wrap the route's "
    'content in `InheritedTheme.capture(from: context, to: '
    'Navigator.of(context).context).wrap(...)`, with the context that '
    "pushes it. A paywall's next screen that its delivered design shows "
    'keeps its push: try mounting the paywall with its generated '
    "`<Paywall>Surface`, whose copy carries the screen's events.";

// The message each refusal reports: who refused, why, and the fix.
String _expectedRefusal(AuthoringRefusalKind refusal) {
  const authored = 'context.surfaceEvent refused authored event dispatch';
  const recorded = 'A generated mount refused a recorded event';
  final (who, reason, hint) = switch (refusal) {
    AuthoringRefusalKind.missingDispatcher => (
        authored,
        'no dispatcher is available',
        '$_contextHint$_routeHint',
      ),
    AuthoringRefusalKind.ambiguousDispatcher => (
        authored,
        'dispatcher ownership is ambiguous',
        ' Try showing the generated mount in one place at a time.',
      ),
    AuthoringRefusalKind.staleCallback => (
        authored,
        'the flow step that built the callback is no longer current',
        ' Try building the callback in the step that shows it, so a later '
            "step never runs an earlier one's callback.",
      ),
    AuthoringRefusalKind.callbackRefused => (
        authored,
        'callback dispatch is not admitted',
        ' Try firing the event from a tap on the surface that shows it, not '
            "from a callback another surface's handler runs.",
      ),
    AuthoringRefusalKind.unmountedContext => (
        authored,
        'the widget that built the callback is no longer mounted',
        _contextHint,
      ),
    AuthoringRefusalKind.recordedWithoutHost => (
        recorded,
        "no surface hosts the generated mount's events",
        ' Try regenerating the mount with `dart run build_runner build`.',
      ),
    AuthoringRefusalKind.recordedHostGone => (
        recorded,
        'the surface the generated mount showed is no longer mounted',
        " Try keeping the callback only while the mount's surface is shown.",
      ),
  };
  return '[restage] $who: $reason.$hint';
}

void _expectSafeRefusal(
  VoidCallback callback, {
  required AuthoringRefusalKind refusal,
}) {
  Object? failure;
  try {
    callback();
  } on Object catch (error) {
    failure = error;
  }

  expect(failure, isA<AssertionError>());
  final message = (failure! as AssertionError).message;
  expect(message, _expectedRefusal(refusal));
  expect(message, isNot(contains(_authoredSentinel)));
  expect(message, isNot(contains(_renderingSentinel)));
}

SurfaceEvent<Object?> _surfaceProbe() =>
    const SurfaceEvent<Object?>(_authoredSentinel);

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
    RestageFlowEventDispatchRegistry.runControllerEvent(
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

void main() {
  group('missing dispatcher diagnostics', () {
    testWidgets('context.surfaceEvent omits authored details', (tester) async {
      late VoidCallback callback;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            callback = context.surfaceEvent(
              _surfaceProbe(),
              _HostileAuthoredValue(),
            );
            return const SizedBox();
          },
        ),
      );

      _expectSafeRefusal(
        callback,
        refusal: AuthoringRefusalKind.missingDispatcher,
      );
    });
  });

  group('stale flow-step diagnostics', () {
    testWidgets('context.surfaceEvent omits authored details', (tester) async {
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
            child: Builder(
              builder: (context) {
                callback = context.surfaceEvent(
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
        refusal: AuthoringRefusalKind.staleCallback,
      );
    });

    testWidgets('a step that is no longer current says so', (tester) async {
      late VoidCallback callback;
      var current = true;
      void handler(String _, Object? __) {}

      await tester.pumpWidget(
        RestageEventDispatcher(
          onEvent: handler,
          child: RestageFlowEventRegistration(
            controller: Object(),
            registration: Object(),
            contentToken: Object(),
            associatedHandler: handler,
            isCurrent: () => current,
            child: Builder(
              builder: (context) {
                callback = context.surfaceEvent(_surfaceProbe());
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      current = false;

      _expectSafeRefusal(
        callback,
        refusal: AuthoringRefusalKind.staleCallback,
      );
    });
  });

  group('callback-time refusal diagnostics', () {
    testWidgets('context.surfaceEvent omits authored details', (tester) async {
      late VoidCallback callback;
      await tester.pumpWidget(
        RestageEventDispatcher(
          onEvent: (_, __) {},
          child: Builder(
            builder: (context) {
              callback = context.surfaceEvent(
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
        refusal: AuthoringRefusalKind.unmountedContext,
      );
    });

    testWidgets('context.surfaceEvent omits authored details after admission',
        (tester) async {
      final probe = await _captureControllerRefusal(
        tester,
        (context) => context.surfaceEvent(
          _surfaceProbe(),
          _HostileAuthoredValue(),
        ),
      );

      _expectSafeRefusal(
        probe.callback,
        refusal: AuthoringRefusalKind.callbackRefused,
      );
      expect(probe.handlerWasCalled(), isTrue);
      expect(probe.eventWasRun(), isFalse);
    });
  });

  test("a generated mount's refusals name the mount, not a call", () {
    for (final refusal in AuthoringRefusalKind.values) {
      final reports = <FlutterErrorDetails>[];
      reportAuthoringRefusal(
        refusal: refusal,
        recorded: true,
        throwOnRefusal: false,
        reportError: reports.add,
      );
      final message = (reports.single.exception as StateError).message;
      expect(
        message,
        startsWith('[restage] A generated mount refused a recorded event: '),
        reason: '$refusal',
      );
      expect(message, isNot(contains('context.surfaceEvent')),
          reason: '$refusal');
      expect(message, contains(' Try '), reason: '$refusal');
    }
  });

  test('reporting uses the assertion message', () {
    {
      for (final refusal in AuthoringRefusalKind.values) {
        Object? assertion;
        try {
          reportAuthoringRefusal(
            refusal: refusal,
            throwOnRefusal: true,
          );
        } on Object catch (error) {
          assertion = error;
        }

        final reports = <FlutterErrorDetails>[];
        reportAuthoringRefusal(
          refusal: refusal,
          throwOnRefusal: false,
          reportError: reports.add,
        );

        final expected = _expectedRefusal(refusal);
        expect(assertion, isA<AssertionError>());
        expect((assertion! as AssertionError).message, expected);
        expect(reports, hasLength(1));
        expect(reports.single.exception, isA<StateError>());
        expect((reports.single.exception as StateError).message, expected);
      }
    }
  });
}
