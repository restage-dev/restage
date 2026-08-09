import 'package:flutter_test/flutter_test.dart';
import 'package:restage/a2ui.dart' as a2ui;
import 'package:restage/rfw.dart' as rfw;

void main() {
  test('target config entrypoints are reachable from the SDK package', () {
    const rfwConfig = rfw.Config();
    const a2uiConfig = a2ui.Config.writeBackValue('value');

    expect(rfwConfig, isA<rfw.Config>());
    expect(a2uiConfig.writeBackValue, 'value');
  });
}
