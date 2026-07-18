import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/runtime/error_boundary.dart';
import 'package:restage/src/runtime/first_paint_lease_guard.dart';

void main() {
  testWidgets(
      'a descendant paint exception does not register the transaction '
      'afterCommit callback', (tester) async {
    var committed = false;
    var afterCommit = false;
    final transaction = FirstPaintLeaseTransaction(
      canCommit: () => true,
      commit: () => committed = true,
      afterCommit: () => afterCommit = true,
      afterRejection: () {},
    );

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: FirstPaintLeaseGuard(
        transaction: transaction,
        armed: true,
        child: RuntimeErrorBoundary(
          onError: (_, __) {},
          errorReplacement: (_, __, ___) => const SizedBox.shrink(),
          child: const _ThrowDuringPaint(),
        ),
      ),
    ));
    final paintError = tester.takeException();

    expect(committed, isTrue);
    expect(transaction.isCommitted, isTrue);
    expect(paintError, isA<StateError>());
    expect(afterCommit, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    tester.takeException();
  });
}

final class _ThrowDuringPaint extends LeafRenderObjectWidget {
  const _ThrowDuringPaint();

  @override
  RenderObject createRenderObject(BuildContext context) => _ThrowingRenderBox();
}

final class _ThrowingRenderBox extends RenderBox {
  @override
  void performLayout() {
    size = constraints.constrain(const Size.square(20));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    throw StateError('paint failed');
  }
}
