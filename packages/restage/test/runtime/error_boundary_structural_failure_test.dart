import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/library_registration.dart';
import 'package:restage/src/runtime/error_boundary.dart';
import 'package:restage/src/runtime/first_paint_lease_guard.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _rootLibrary = LibraryName(<String>['app', 'surface']);

/// Structural (layout/paint) failure ownership on a boundary configured the way
/// the SDK's own render paths configure it: `onError` + `errorReplacement`, and
/// no success notification of any kind.
///
/// The framework reports a descendant layout/paint exception instead of
/// rethrowing it, so the guard's `super.paint` returns normally. Without a
/// boundary-owned structural observer the lease cannot tell that frame apart
/// from a clean one, and would acknowledge paint on a surface that never
/// rendered.
void main() {
  testWidgets(
    'a boundary without a success callback owns a descendant paint exception',
    (tester) async {
      final observed = await _runStructuralFailureScenario(
        tester,
        phase: _StructuralFailurePhase.paint,
      );

      expect(observed, (
        committed: true,
        painted: false,
        afterCommit: false,
        errors: 1,
        isCommitted: true,
        isPaintAcknowledged: false,
        fallbacks: 1,
        reported: 'Bad state: paint failed',
      ));
    },
  );

  testWidgets(
    'a boundary without a success callback owns a descendant layout exception',
    (tester) async {
      final observed = await _runStructuralFailureScenario(
        tester,
        phase: _StructuralFailurePhase.layout,
      );

      expect(observed, (
        committed: true,
        painted: false,
        afterCommit: false,
        errors: 1,
        isCommitted: true,
        isPaintAcknowledged: false,
        fallbacks: 1,
        reported: 'Bad state: layout failed',
      ));
    },
  );

  testWidgets(
    'a boundary without a success callback still acknowledges a clean paint',
    (tester) async {
      var committed = false;
      var painted = false;
      var afterCommit = false;
      var errors = 0;
      final transaction = FirstPaintLeaseTransaction(
        canCommit: () => true,
        commit: () => committed = true,
        onPainted: () => painted = true,
        afterCommit: () => afterCommit = true,
        afterRejection: () {},
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: FirstPaintLeaseScope(
            transaction: transaction,
            child: FirstPaintLeaseGuard(
              transaction: transaction,
              armed: true,
              child: RuntimeErrorBoundary(
                onError: (_, __) => errors += 1,
                errorReplacement: (_, __, ___) => const Text('fallback'),
                child: const Center(
                  child: SizedBox.square(
                    key: ValueKey<String>('clean-child'),
                    dimension: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final observed = (
        committed: committed,
        painted: painted,
        afterCommit: afterCommit,
        errors: errors,
        isPaintAcknowledged: transaction.isPaintAcknowledged,
        childSize: tester
            .renderObject<RenderBox>(
              find.byKey(const ValueKey<String>('clean-child')),
            )
            .size,
        escaped: tester.takeException(),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(observed, (
        committed: true,
        painted: true,
        afterCommit: true,
        errors: 0,
        isPaintAcknowledged: true,
        childSize: const Size.square(20),
        escaped: null,
      ));
    },
  );

  for (final scenario in <({
    String name,
    String ratio,
    Widget Function(Widget child) host,
  })>[
    (
      name: 'division overflow',
      ratio: '1e-320',
      host: _divisionOverflowHost,
    ),
    (
      name: 'multiplication overflow',
      ratio: '1e308',
      host: _multiplicationOverflowHost,
    ),
  ]) {
    testWidgets(
      'a generated AspectRatio ${scenario.name} is owned before first paint',
      (tester) async {
        final observed = await _runGeneratedAspectFailureScenario(
          tester,
          ratio: scenario.ratio,
          host: scenario.host,
        );

        expect(observed.error, isA<FlutterError>());
        expect(
          observed.error.toString(),
          contains('AspectRatio produced a non-finite layout size.'),
        );
        expect(observed.committed, isTrue);
        expect(observed.painted, isFalse);
        expect(observed.afterCommit, isFalse);
        expect(observed.errors, 1);
        expect(observed.isCommitted, isTrue);
        expect(observed.isPaintAcknowledged, isFalse);
        expect(observed.fallbacks, 1);
        expect(observed.reports, 1);
      },
    );
  }

  testWidgets(
    'a generated finite ListView estimate failure is owned before first paint',
    (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      Set<String>? labels;
      final observed = await _runGeneratedAspectFailureScenario(
        tester,
        ratio: '1.0',
        expression: '''ListView(children: [
  SizedBox(height: 1e308, child: Text(text: "list semantics one")),
  SizedBox(height: 1e308, child: Text(text: "list semantics two")),
  SizedBox(height: 1e308, child: Text(text: "list semantics three"))
])''',
        host: (child) => SizedBox(width: 400, height: 600, child: child),
        beforeUnmount: () => labels = _semanticsLabels(tester),
      );

      expect(observed.error, isA<FlutterError>());
      expect(
        observed.error.toString(),
        contains('ListView cannot estimate a finite scroll extent'),
      );
      expect(observed.committed, isTrue);
      expect(observed.painted, isFalse);
      expect(observed.afterCommit, isFalse);
      expect(observed.errors, 1);
      expect(observed.isCommitted, isTrue);
      expect(observed.isPaintAcknowledged, isFalse);
      expect(observed.fallbacks, 1);
      expect(observed.reports, 1);
      expect(labels, contains('aspect fallback'));
      expect(labels, isNot(contains('list semantics one')));
      semantics.dispose();
    },
  );

  testWidgets(
    'a generated relayout replaces stale semantics and a new boundary resumes',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var errors = 0;
      final runtime = Runtime()
        ..update(_coreLibrary, buildCoreWidgetLibrary())
        ..update(_rootLibrary, _aspectLibrary('1.0'));
      final data = DynamicContent();

      Widget build(Key key) => Directionality(
            textDirection: TextDirection.ltr,
            child: RuntimeErrorBoundary(
              key: key,
              onError: (_, __) => errors += 1,
              errorReplacement: (_, __, ___) =>
                  const Text('replacement semantics'),
              child: _divisionOverflowHost(
                RemoteWidget(
                  runtime: runtime,
                  data: data,
                  widget: const FullyQualifiedWidgetName(
                    _rootLibrary,
                    'Surface',
                  ),
                  onEvent: (_, __) {},
                ),
              ),
            ),
          );

      await tester.pumpWidget(build(const ValueKey<String>('first-boundary')));
      final initialSemantics = _semanticsContains(tester, 'clean semantics');

      runtime.update(_rootLibrary, _aspectLibrary('1e-320'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final failureEscaped = tester.takeException();
      final replacementLabels = _semanticsLabels(tester);
      final replacementCount =
          find.text('replacement semantics').evaluate().length;
      final failedCleanCount = find.text('clean semantics').evaluate().length;

      runtime.update(_rootLibrary, _aspectLibrary('1.0'));
      await tester.pumpWidget(
        build(const ValueKey<String>('resumed-boundary')),
      );
      await tester.pump();

      final resumedEscaped = tester.takeException();
      final resumedSemantics = _semanticsContains(tester, 'clean semantics');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      semantics.dispose();

      expect(initialSemantics, isTrue);
      expect(errors, 1);
      expect(failureEscaped, isNotNull);
      expect(replacementCount, 1);
      expect(replacementLabels, contains('replacement semantics'));
      expect(failedCleanCount, 0);
      expect(resumedEscaped, isNull);
      expect(resumedSemantics, isTrue);
    },
  );

  for (final horizontal in [true, false]) {
    final name = horizontal ? 'Row' : 'Column';
    for (final allocation in [true, false]) {
      testWidgets(
          '$name owns ${allocation ? 'allocation' : 'sum'} failure before first paint',
          (tester) async {
        final semantics = tester.ensureSemantics();
        RenderFlex? failed;
        RenderBox? failedChild;
        BoxConstraints? accepted;
        bool? parentHasSize;
        bool? childHasSize;
        bool? finiteOffset;
        final dimension = horizontal ? 'width' : 'height';
        final expression = allocation
            ? '$name(children: [Expanded(flex: 3, child: SizedBox(width: 10.0, height: 10.0))])'
            : '$name(children: [SizedBox($dimension: 1e308), SizedBox($dimension: 1e308)])';
        final observed = await _runGeneratedAspectFailureScenario(
          tester,
          ratio: '1.0',
          expression: expression,
          beforeUnmount: () {
            parentHasSize = failed!.hasSize;
            childHasSize = failedChild!.hasSize;
            finiteOffset =
                (failedChild!.parentData! as FlexParentData).offset.isFinite;
            try {
              accepted = failedChild!.constraints;
            } catch (_) {}
          },
          host: (child) => _FlexConstraintHost(
            childConstraints: horizontal
                ? BoxConstraints(
                    maxWidth: allocation ? double.maxFinite : double.infinity,
                    maxHeight: 20)
                : BoxConstraints(
                    maxWidth: 20,
                    maxHeight: allocation ? double.maxFinite : double.infinity),
            onLayout: (render) {
              failed = render;
              failedChild = render.firstChild;
            },
            child: child,
          ),
        );
        expect(observed.error, isA<FlutterError>());
        expect(observed.error.toString(),
            contains(allocation ? 'allocation' : 'finite geometry'));
        expect(observed.errors, 1);
        expect(observed.committed, isTrue);
        expect(observed.painted, isFalse);
        expect(observed.afterCommit, isFalse);
        expect(observed.isPaintAcknowledged, isFalse);
        expect(observed.fallbacks, 1);
        expect(observed.reports, 1);
        expect(parentHasSize, isFalse);
        expect(childHasSize, !allocation);
        expect(finiteOffset, isTrue);
        if (allocation) expect(accepted, isNull);
        semantics.dispose();
      });
    }
  }

  testWidgets('generated Wrap owns child-only failure before first paint',
      (tester) async {
    RenderWrap? failed;
    RenderBox? failedChild;
    final observed = await _runGeneratedAspectFailureScenario(
      tester,
      ratio: '1.0',
      expression: '''Wrap(children: [
SizedBox(width: 1e308, height: 10.0),
SizedBox(width: 1e308, height: 10.0)
])''',
      beforeUnmount: () {
        expect(failed!.hasSize, isFalse);
        expect(failedChild!.hasSize, isTrue);
        expect(
          (failedChild!.parentData! as WrapParentData).offset.isFinite,
          isTrue,
        );
        expect(failedChild!.constraints.isNormalized, isTrue);
      },
      host: (child) => _WrapConstraintHost(
        onLayout: (render) {
          failed = render;
          failedChild = render.firstChild;
        },
        child: child,
      ),
    );
    expect(observed.error, isA<FlutterError>());
    expect(observed.error.toString(), contains('Wrap cannot produce finite'));
    expect(observed.errors, 1);
    expect(observed.committed, isTrue);
    expect(observed.painted, isFalse);
    expect(observed.afterCommit, isFalse);
    expect(observed.isPaintAcknowledged, isFalse);
    expect(observed.fallbacks, 1);
    expect(observed.reports, 1);
  });

  testWidgets(
      'generated Flex failure removes stale semantics and a new boundary resumes',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var errors = 0;
    final runtime = Runtime()
      ..update(_coreLibrary, buildCoreWidgetLibrary())
      ..update(_rootLibrary, parseLibraryFile('''
import restage.core;
widget Surface = Row(children: [Expanded(flex: 3, child: Text(text: "flex semantics"))]);
'''));
    Widget build(Key key, double width) => Directionality(
          textDirection: TextDirection.ltr,
          child: RuntimeErrorBoundary(
            key: key,
            onError: (_, __) => errors++,
            errorReplacement: (_, __, ___) =>
                const Text('flex replacement semantics'),
            child: _FlexConstraintHost(
              childConstraints: BoxConstraints(maxWidth: width, maxHeight: 20),
              onLayout: (_) {},
              child: RemoteWidget(
                  runtime: runtime,
                  data: DynamicContent(),
                  widget:
                      const FullyQualifiedWidgetName(_rootLibrary, 'Surface'),
                  onEvent: (_, __) {}),
            ),
          ),
        );
    const key = ValueKey('flex-boundary');
    await tester.pumpWidget(build(key, 100));
    expect(_semanticsContains(tester, 'flex semantics'), isTrue);
    await tester.pumpWidget(build(key, double.maxFinite));
    await tester.pump();
    await tester.pump();
    expect(errors, 1);
    expect(tester.takeException(), isA<FlutterError>());
    expect(_semanticsContains(tester, 'flex replacement semantics'), isTrue);
    expect(_semanticsContains(tester, 'flex semantics'), isFalse);
    await tester
        .pumpWidget(build(const ValueKey('resumed-flex-boundary'), 100));
    await tester.pump();
    expect(_semanticsContains(tester, 'flex semantics'), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });

  testWidgets(
      'generated Wrap failure removes stale semantics and a new boundary resumes',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var errors = 0;
    final runtime = Runtime()
      ..update(_coreLibrary, buildCoreWidgetLibrary())
      ..update(
        _rootLibrary,
        parseLibraryFile('''
import restage.core;
widget Surface = Wrap(children: [Text(text: "wrap semantics")]);
'''),
      );
    Widget build(Key key) => Directionality(
          textDirection: TextDirection.ltr,
          child: RuntimeErrorBoundary(
            key: key,
            onError: (_, __) => errors += 1,
            errorReplacement: (_, __, ___) =>
                const Text('wrap replacement semantics'),
            child: _WrapConstraintHost(
              onLayout: (_) {},
              child: RemoteWidget(
                runtime: runtime,
                data: DynamicContent(),
                widget: const FullyQualifiedWidgetName(
                  _rootLibrary,
                  'Surface',
                ),
                onEvent: (_, __) {},
              ),
            ),
          ),
        );
    const key = ValueKey('wrap-boundary');
    await tester.pumpWidget(build(key));
    expect(_semanticsContains(tester, 'wrap semantics'), isTrue);
    runtime.update(
      _rootLibrary,
      parseLibraryFile('''
import restage.core;
widget Surface = Wrap(children: [
SizedBox(width: 1e308, height: 10.0),
SizedBox(width: 1e308, height: 10.0)
]);
'''),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(errors, 1);
    expect(tester.takeException(), isA<FlutterError>());
    expect(_semanticsContains(tester, 'wrap replacement semantics'), isTrue);
    expect(_semanticsContains(tester, 'wrap semantics'), isFalse);
    runtime.update(
      _rootLibrary,
      parseLibraryFile('''
import restage.core;
widget Surface = Wrap(children: [Text(text: "wrap semantics")]);
'''),
    );
    await tester.pumpWidget(
      build(const ValueKey('resumed-wrap-boundary')),
    );
    await tester.pump();
    expect(_semanticsContains(tester, 'wrap semantics'), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });
}

class _FlexConstraintHost extends SingleChildRenderObjectWidget {
  const _FlexConstraintHost(
      {required this.childConstraints,
      required this.onLayout,
      required super.child});
  final BoxConstraints childConstraints;
  final void Function(RenderFlex) onLayout;

  @override
  _RenderFlexConstraintHost createRenderObject(BuildContext context) =>
      _RenderFlexConstraintHost(childConstraints, onLayout);

  @override
  void updateRenderObject(
      BuildContext context, _RenderFlexConstraintHost renderObject) {
    renderObject.childConstraints = childConstraints;
    renderObject.onLayout = onLayout;
    renderObject.markNeedsLayout();
  }
}

class _RenderFlexConstraintHost extends RenderProxyBox {
  _RenderFlexConstraintHost(this.childConstraints, this.onLayout);
  BoxConstraints childConstraints;
  void Function(RenderFlex) onLayout;

  @override
  void performLayout() {
    onLayout(child! as RenderFlex);
    child!.layout(childConstraints, parentUsesSize: true);
    size = constraints.constrain(const Size(100, 20));
  }
}

class _WrapConstraintHost extends SingleChildRenderObjectWidget {
  const _WrapConstraintHost({required this.onLayout, required super.child});

  final void Function(RenderWrap) onLayout;

  @override
  _RenderWrapConstraintHost createRenderObject(BuildContext context) =>
      _RenderWrapConstraintHost(onLayout);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderWrapConstraintHost renderObject,
  ) {
    renderObject
      ..onLayout = onLayout
      ..markNeedsLayout();
  }
}

class _RenderWrapConstraintHost extends RenderProxyBox {
  _RenderWrapConstraintHost(this.onLayout);

  void Function(RenderWrap) onLayout;

  @override
  void performLayout() {
    final render = child! as RenderWrap;
    onLayout(render);
    render.layout(const BoxConstraints(maxHeight: 20), parentUsesSize: true);
    size = constraints.constrain(const Size(100, 20));
  }
}

bool _semanticsContains(WidgetTester tester, String label) {
  return _semanticsLabels(tester).contains(label);
}

Set<String> _semanticsLabels(WidgetTester tester) {
  final labels = <String>{};
  void visit(SemanticsNode node) {
    final label = node.getSemanticsData().label;
    if (label.isNotEmpty) {
      labels.add(label);
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  for (final renderView in tester.binding.renderViews) {
    final root = renderView.owner?.semanticsOwner?.rootSemanticsNode;
    if (root != null) visit(root);
  }
  return labels;
}

RemoteWidgetLibrary _aspectLibrary(String ratio) => parseLibraryFile('''
import restage.core;
widget Surface = AspectRatio(
  aspectRatio: $ratio,
  child: Text(text: "clean semantics")
);
''');

Widget _divisionOverflowHost(Widget child) => Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[SizedBox(width: 1, child: child)],
    );

Widget _multiplicationOverflowHost(Widget child) => SizedBox(
      height: 2,
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[child]),
    );

Future<
    ({
      bool committed,
      bool painted,
      bool afterCommit,
      int errors,
      bool isCommitted,
      bool isPaintAcknowledged,
      int fallbacks,
      Object? error,
      int reports,
    })> _runGeneratedAspectFailureScenario(
  WidgetTester tester, {
  required String ratio,
  required Widget Function(Widget child) host,
  String? expression,
  VoidCallback? beforeUnmount,
}) async {
  var committed = false;
  var painted = false;
  var afterCommit = false;
  var errors = 0;
  Object? error;
  final transaction = FirstPaintLeaseTransaction(
    canCommit: () => true,
    commit: () => committed = true,
    onPainted: () => painted = true,
    afterCommit: () => afterCommit = true,
    afterRejection: () {},
  );
  final runtime = Runtime()
    ..update(_coreLibrary, buildCoreWidgetLibrary())
    ..update(
      _rootLibrary,
      parseLibraryFile('''
import restage.core;
widget Surface = ${expression ?? '''AspectRatio(
  aspectRatio: $ratio,
  child: SizedBox(width: 20.0, height: 20.0)
)'''};
'''),
    );
  final binding = FlutterError.onError!;
  final reported = <Object>[];
  FlutterError.onError = (details) {
    reported.add(details.exception);
    binding(details);
  };
  final remote = RemoteWidget(
    runtime: runtime,
    data: DynamicContent(const <String, Object?>{}),
    widget: const FullyQualifiedWidgetName(_rootLibrary, 'Surface'),
    onEvent: (_, __) {},
  );

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: FirstPaintLeaseScope(
        transaction: transaction,
        child: FirstPaintLeaseGuard(
          transaction: transaction,
          armed: true,
          child: RuntimeErrorBoundary(
            onError: (exception, _) {
              errors += 1;
              error ??= exception;
            },
            errorReplacement: (_, __, ___) => const Text('aspect fallback'),
            child: host(remote),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();

  final observed = (
    committed: committed,
    painted: painted,
    afterCommit: afterCommit,
    errors: errors,
    isCommitted: transaction.isCommitted,
    isPaintAcknowledged: transaction.isPaintAcknowledged,
    fallbacks: find.text('aspect fallback').evaluate().length,
    error: error,
    reports: reported.where((exception) => identical(exception, error)).length,
  );
  tester.takeException();

  beforeUnmount?.call();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  FlutterError.onError = binding;
  return observed;
}

enum _StructuralFailurePhase { layout, paint }

typedef _StructuralFailureObservation = ({
  bool committed,
  bool painted,
  bool afterCommit,
  int errors,
  bool isCommitted,
  bool isPaintAcknowledged,
  int fallbacks,
  String? reported,
});

Future<_StructuralFailureObservation> _runStructuralFailureScenario(
  WidgetTester tester, {
  required _StructuralFailurePhase phase,
}) async {
  var committed = false;
  var painted = false;
  var afterCommit = false;
  var errors = 0;
  final transaction = FirstPaintLeaseTransaction(
    canCommit: () => true,
    commit: () => committed = true,
    onPainted: () => painted = true,
    afterCommit: () => afterCommit = true,
    afterRejection: () {},
  );

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: FirstPaintLeaseScope(
        transaction: transaction,
        child: FirstPaintLeaseGuard(
          transaction: transaction,
          armed: true,
          // Exactly the production configuration: a failure sink and a
          // replacement, and no success notification.
          child: RuntimeErrorBoundary(
            onError: (_, __) => errors += 1,
            errorReplacement: (_, __, ___) => const Text('fallback'),
            child: _ThrowDuringStructuralPhase(phase: phase),
          ),
        ),
      ),
    ),
  );
  // One frame for the structural report to be resolved, one for the boundary's
  // post-frame failure capture to swap in the replacement.
  await tester.pump();
  await tester.pump();

  final observed = (
    committed: committed,
    painted: painted,
    afterCommit: afterCommit,
    errors: errors,
    isCommitted: transaction.isCommitted,
    isPaintAcknowledged: transaction.isPaintAcknowledged,
    fallbacks: find.text('fallback').evaluate().length,
    reported: tester.takeException()?.toString(),
  );

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  return observed;
}

final class _ThrowDuringStructuralPhase extends LeafRenderObjectWidget {
  const _ThrowDuringStructuralPhase({required this.phase});

  final _StructuralFailurePhase phase;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _StructurallyFailingRenderBox(phase);
}

final class _StructurallyFailingRenderBox extends RenderBox {
  _StructurallyFailingRenderBox(this.phase);

  final _StructuralFailurePhase phase;

  // Sizing in [performResize] keeps a thrown [performLayout] from cascading
  // into an unset-size failure in the parent, so the scenario observes the one
  // report it is about.
  @override
  bool get sizedByParent => true;

  @override
  void performResize() {
    size = constraints.constrain(const Size.square(20));
  }

  @override
  void performLayout() {
    if (phase == _StructuralFailurePhase.layout) {
      throw StateError('layout failed');
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (phase == _StructuralFailurePhase.paint) {
      throw StateError('paint failed');
    }
  }
}
