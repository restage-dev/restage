import 'package:restage_shared/a2ui.dart' as a2ui;
import 'package:restage_shared/rfw.dart' as rfw;
import 'package:restage_shared/widgetbook.dart' as wb;
import 'package:test/test.dart';

void main() {
  test('target config entrypoints pass through the schema API', () {
    const rfwConfig = rfw.Config.enabled(false);
    const a2uiConfig = a2ui.Config(
      enabled: false,
      usage: 'Use for the primary action.',
      writeBackValues: {'onChanged': 'value'},
    );
    const widgetbookConfig = wb.Config(
      enabled: false,
      expansion: wb.StoryExpansion.independent,
    );

    expect(rfwConfig, isA<rfw.Config>());
    expect(rfwConfig.enabled, isFalse);
    expect(a2uiConfig.enabled, isFalse);
    expect(a2uiConfig.usage, 'Use for the primary action.');
    expect(a2uiConfig.writeBackValues, {'onChanged': 'value'});
    expect(widgetbookConfig.expansion, wb.StoryExpansion.independent);
    expect(widgetbookConfig.enabled, isFalse);
  });
}
