import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  test('detached controller dismiss/fireEvent are no-ops', () {
    final controller = RestagePaywallController();
    expect(controller.dismiss, returnsNormally);
    expect(() => controller.fireEvent('x'), returnsNormally);
  });

  test('controller reports attachment state', () {
    final controller = RestagePaywallController();
    expect(controller.isAttached, isFalse);
  });

  test('after attachInternal, isAttached is true', () {
    final controller = RestagePaywallController()
      ..attachInternal(
        onDismiss: ({required reason}) {},
        onFireEvent: (name, {args}) {},
      );
    expect(controller.isAttached, isTrue);
  });

  test('detachInternal restores detached state', () {
    final controller = RestagePaywallController()
      ..attachInternal(
        onDismiss: ({required reason}) {},
        onFireEvent: (name, {args}) {},
      )
      ..detachInternal();
    expect(controller.isAttached, isFalse);
  });
}
