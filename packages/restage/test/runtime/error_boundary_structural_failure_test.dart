import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/runtime/error_boundary.dart';
import 'package:restage/src/runtime/first_paint_lease_guard.dart';

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
        escaped: null,
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
        escaped: null,
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
  Object? escaped,
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
    escaped: tester.takeException(),
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
