import 'package:flutter_test/flutter_test.dart';
import 'package:restage/a2ui.dart' as a2ui;
import 'package:restage/rfw.dart' as rfw;
import 'package:restage/widgetbook.dart' as wb;

void main() {
  test('target config entrypoints are reachable from the SDK package', () {
    const rfwConfig = rfw.Config();
    const a2uiConfig = a2ui.Config.writeBackValue('value');
    const widgetbookConfig = wb.Config.values([false, true]);

    expect(rfwConfig, isA<rfw.Config>());
    expect(a2uiConfig.writeBackValue, 'value');
    expect(widgetbookConfig.storyValues, [false, true]);
  });
}
