import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  test('DismissReason enum stable', () {
    expect(DismissReason.values.toSet(), {
      DismissReason.userClose,
      DismissReason.programmatic,
    });
  });

  test('DismissReason parses known wire names', () {
    expect(DismissReasonWire.fromWire('user_close'), DismissReason.userClose);
    expect(
      DismissReasonWire.fromWire('unsupported'),
      DismissReason.programmatic,
    );
  });
}
