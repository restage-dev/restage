import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/runtime/error_boundary.dart';

/// Every Flutter error reaches the app's handler synchronously and once, and
/// mounted boundaries leave the handler chain intact however they unmount.
void main() {
  testWidgets(
      'a contained build error shows the fallback and reaches the '
      "app's handler exactly once", (tester) async {
    final binding = FlutterError.onError!;
    final appErrors = <FlutterErrorDetails>[];
    FlutterError.onError = (details) {
      appErrors.add(details);
      binding(details);
    };
    final caught = <Object>[];

    await tester.pumpWidget(
      _app(_boundary(
        onError: (error, _) => caught.add(error),
        child: const _Throws('broken surface'),
      )),
    );
    final reported = tester.takeException();
    await tester.pump();

    expect(reported, isA<StateError>());
    expect(appErrors.map((details) => details.exception), [reported]);
    expect(caught, [reported]);
    expect(find.text('fallback'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    FlutterError.onError = binding;
  });

  testWidgets(
      "a report during semantics reaches the app's handler exactly once "
      'even when containment throws', (tester) async {
    final semantics = tester.ensureSemantics();
    final binding = FlutterError.onError!;
    final appErrors = <Object>[];
    FlutterError.onError = (details) {
      appErrors.add(details.exception);
      binding(details);
    };
    final reported = StateError('semantics failed');

    await tester.pumpWidget(
      _app(_boundary(child: _ReportsDuringSemantics(reported))),
    );
    tester.takeException();
    FlutterError.onError = binding;

    // Containment trips the semantics-phase assertion, reported after.
    expect(appErrors.first, same(reported));
    expect(
        appErrors.where((error) => identical(error, reported)), hasLength(1));
    expect(appErrors.skip(1), contains(isA<AssertionError>()));

    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  group('a report reaches the test binding before reportError returns', () {
    testWidgets('with one boundary mounted', (tester) async {
      await tester.pumpWidget(_app(_boundary(child: const SizedBox())));

      _expectDeliveredSynchronously(tester);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('with nested boundaries mounted', (tester) async {
      await tester.pumpWidget(
        _app(_boundary(child: _boundary(child: const SizedBox()))),
      );

      _expectDeliveredSynchronously(tester);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('after a boundary contained an error', (tester) async {
      await tester.pumpWidget(_app(_boundary(child: const _Throws('broken'))));
      expect(tester.takeException(), isA<StateError>());
      await tester.pump();
      expect(find.text('fallback'), findsOneWidget);

      _expectDeliveredSynchronously(tester);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('a fallback prints one debug line naming the surface',
      (tester) async {
    final lines = <String?>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => lines.add(message);
    try {
      await tester.pumpWidget(
        _app(_boundary(debugLabel: 'welcome', child: const _Throws('broken'))),
      );
      tester.takeException();
      await tester.pump();
    } finally {
      debugPrint = previousDebugPrint;
    }

    expect(lines, [
      '[restage] surface "welcome" fell back after a render error: '
          'Bad state: broken',
    ]);
    await tester.pumpWidget(const SizedBox());
  });

  group('the handler chain is restored', () {
    for (final order in const [
      ['a', 'b'],
      ['b', 'a'],
    ]) {
      testWidgets('when sibling boundaries unmount ${order.join(' then ')}',
          (tester) async {
        final onError = FlutterError.onError;
        final errorBuilder = ErrorWidget.builder;
        final mounted = {'a', 'b'};
        Widget tree() => _app(
              Column(
                children: [
                  for (final id in mounted)
                    _boundary(key: ValueKey(id), child: const SizedBox()),
                ],
              ),
            );

        await tester.pumpWidget(tree());
        expect(FlutterError.onError, isNot(same(onError)));

        mounted.remove(order.first);
        await tester.pumpWidget(tree());
        _expectDeliveredSynchronously(tester);

        mounted.remove(order.last);
        await tester.pumpWidget(tree());
        expect(FlutterError.onError, same(onError));
        expect(ErrorWidget.builder, same(errorBuilder));
      });
    }

    for (final innerFirst in const [true, false]) {
      testWidgets(
          'when nested boundaries unmount '
          '${innerFirst ? 'inner first' : 'outer first'}', (tester) async {
        final onError = FlutterError.onError;
        final errorBuilder = ErrorWidget.builder;

        const inner = GlobalObjectKey('inner');
        await tester.pumpWidget(
          _app(
              _boundary(child: _boundary(key: inner, child: const SizedBox()))),
        );
        // Outer first keeps the inner boundary alive by moving it under a
        // global key.
        await tester.pumpWidget(
          _app(
            innerFirst
                ? _boundary(child: const SizedBox())
                : _boundary(key: inner, child: const SizedBox()),
          ),
        );
        _expectDeliveredSynchronously(tester);
        await tester.pumpWidget(const SizedBox());

        expect(FlutterError.onError, same(onError));
        expect(ErrorWidget.builder, same(errorBuilder));
      });
    }

    testWidgets('when a wrapper was installed after the boundary',
        (tester) async {
      final onError = FlutterError.onError;
      final errorBuilder = ErrorWidget.builder;
      await tester.pumpWidget(_app(_boundary(child: const SizedBox())));

      final installedOnError = FlutterError.onError!;
      final installedBuilder = ErrorWidget.builder;
      final wrapped = <FlutterErrorDetails>[];
      void wrapper(FlutterErrorDetails details) {
        wrapped.add(details);
        installedOnError(details);
      }

      Widget wrapperBuilder(FlutterErrorDetails details) =>
          installedBuilder(details);
      FlutterError.onError = wrapper;
      ErrorWidget.builder = wrapperBuilder;

      await tester.pumpWidget(const SizedBox());
      expect(FlutterError.onError, same(wrapper));
      expect(ErrorWidget.builder, same(wrapperBuilder));

      _expectDeliveredSynchronously(tester);
      expect(wrapped, hasLength(1));

      // An uninstalled builder hands an unguarded failure straight on.
      await tester.pumpWidget(const _Throws('unguarded'));
      expect(tester.takeException(), isA<StateError>());
      expect(find.byType(ErrorWidget), findsOneWidget);

      FlutterError.onError = onError;
      ErrorWidget.builder = errorBuilder;
      await tester.pumpWidget(const SizedBox());
    });
  });
}

Widget _boundary({
  Key? key,
  required Widget child,
  void Function(Object error, StackTrace stack)? onError,
  String? debugLabel,
}) =>
    RuntimeErrorBoundary(
      key: key,
      debugLabel: debugLabel,
      onError: onError ?? (_, __) {},
      errorReplacement: (_, __, ___) => const Text('fallback'),
      child: child,
    );

Widget _app(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

/// Reports an error the way the test binding does for a failing test, and
/// requires the binding to have recorded it before reportError returned.
void _expectDeliveredSynchronously(WidgetTester tester) {
  final details = FlutterErrorDetails(exception: StateError('test failure'));
  FlutterError.reportError(details);
  expect(tester.takeException(), same(details.exception));
}

class _Throws extends StatelessWidget {
  const _Throws(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => throw StateError(message);
}

/// Reports [error] once, owned by this render object, while semantics flush.
class _ReportsDuringSemantics extends LeafRenderObjectWidget {
  const _ReportsDuringSemantics(this.error);

  final Object error;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReportsDuringSemantics(error);
}

class _RenderReportsDuringSemantics extends RenderBox {
  _RenderReportsDuringSemantics(this.error);

  final Object error;
  bool _reported = false;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(const Size.square(20));

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..label = 'reports';
  }

  @override
  void assembleSemanticsNode(
    SemanticsNode node,
    SemanticsConfiguration config,
    Iterable<SemanticsNode> children,
  ) {
    super.assembleSemanticsNode(node, config, children);
    if (_reported) return;
    _reported = true;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        informationCollector: () => [
          DiagnosticsProperty<RenderObject>('renderObject', this),
        ],
      ),
    );
  }
}
