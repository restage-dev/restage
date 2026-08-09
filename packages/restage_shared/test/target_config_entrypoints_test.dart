import 'package:restage_shared/a2ui.dart' as a2ui;
import 'package:restage_shared/rfw.dart' as rfw;
import 'package:test/test.dart';

void main() {
  test('target config entrypoints pass through the schema API', () {
    const rfwConfig = rfw.Config();
    const a2uiConfig = a2ui.Config(
      usage: 'Use for the primary action.',
      writeBackValues: {'onChanged': 'value'},
    );

    expect(rfwConfig, isA<rfw.Config>());
    expect(a2uiConfig.usage, 'Use for the primary action.');
    expect(a2uiConfig.writeBackValues, {'onChanged': 'value'});
  });
}
