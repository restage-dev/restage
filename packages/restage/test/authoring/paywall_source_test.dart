import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  test('PaywallSource captures id', () {
    const a = PaywallSource(id: 'pro_upgrade');
    expect(a.id, 'pro_upgrade');
  });
}
