import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
import 'package:rfw_catalog_schema/rfw.dart' as rfw;
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;
import 'package:test/test.dart';

@rfw.Config(enabled: true)
@rfw.Config.enabled(true)
final class RfwConfiguredWidget {}

@a2ui.Config(
  enabled: true,
  usage: 'Use for the primary action.',
  writeBackValues: {'onChanged': 'value'},
)
@a2ui.Config.enabled(true)
@a2ui.Config.usage('Use for the primary action.')
@a2ui.Config.writeBackValues({'onChanged': 'value'})
final class A2uiConfiguredWidget {
  @a2ui.Config.writeBackValue('value')
  final void Function(String) onChanged = ignoreString;
}

@wb.Config(
  enabled: true,
  expansion: wb.StoryExpansion.cartesian,
  maxStories: 12,
)
@wb.Config.enabled(true)
final class WidgetbookConfiguredWidget {
  @wb.Config.values([false, true])
  final bool enabled = false;

  @wb.Config.allValues()
  final bool? selected = false;
}

void ignoreString(String _) {}

void main() {
  test('RFW config remains a const target annotation', () {
    const aggregate = rfw.Config(enabled: false);
    const enabled = rfw.Config.enabled(false);

    expect(aggregate.enabled, isFalse);
    expect(enabled.enabled, isFalse);
    expect(const rfw.Config().enabled, isNull);
    expect(RfwConfiguredWidget(), isA<RfwConfiguredWidget>());
  });

  test('A2UI aggregate and shorthand constructors expose their one key', () {
    const aggregate = a2ui.Config(
      enabled: false,
      usage: 'Use for the primary action.',
      writeBackValues: {'onChanged': 'value'},
    );
    const enabled = a2ui.Config.enabled(false);
    const usage = a2ui.Config.usage('Use for the primary action.');
    const writeBackValues = a2ui.Config.writeBackValues({'onChanged': 'value'});
    const writeBackValue = a2ui.Config.writeBackValue('value');

    expect(aggregate.usage, usage.usage);
    expect(aggregate.enabled, isFalse);
    expect(enabled.enabled, isFalse);
    expect(aggregate.writeBackValues, writeBackValues.writeBackValues);
    expect(writeBackValue.writeBackValue, 'value');
    expect(usage.writeBackValues, isNull);
    expect(writeBackValues.usage, isNull);
    expect(usage.enabled, isNull);
    expect(A2uiConfiguredWidget().onChanged, same(ignoreString));
  });

  test('Widgetbook aggregate and shorthand constructors expose exact keys', () {
    const aggregate = wb.Config(
      enabled: false,
      expansion: wb.StoryExpansion.cartesian,
      maxStories: 12,
    );
    const enabled = wb.Config.enabled(false);
    const expansion = wb.Config.expansion(wb.StoryExpansion.cartesian);
    const maxStories = wb.Config.maxStories(12);
    const values = wb.Config.values([false, true, null]);
    const emptyValues = wb.Config.values([]);
    const allValues = wb.Config.allValues();

    expect(aggregate.expansion, expansion.expansion);
    expect(aggregate.enabled, isFalse);
    expect(enabled.enabled, isFalse);
    expect(aggregate.maxStories, maxStories.maxStories);
    expect(values.storyValues, [false, true, null]);
    expect(emptyValues.storyValues, isEmpty);
    expect(allValues.allValues, isTrue);
    expect(values.allValues, isFalse);
    expect(expansion.maxStories, isNull);
    expect(expansion.enabled, isNull);
    final configured = WidgetbookConfiguredWidget();
    expect(configured.enabled, isFalse);
    expect(configured.selected, isFalse);
  });
}
