import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  test('dual public imports expose one compatibility alias declaration', () {
    // ignore: deprecated_member_use
    const SurfaceType legacySurface = Surface.general;

    expect(legacySurface, Surface.general);
  });
}
