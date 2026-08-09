import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
import 'package:rfw_catalog_schema/rfw.dart' as rfw;
import 'package:test/test.dart';

@rfw.Config()
final class RfwConfiguredWidget {}

@a2ui.Config(
  usage: 'Use for the primary action.',
  writeBackValues: {'onChanged': 'value'},
)
@a2ui.Config.usage('Use for the primary action.')
@a2ui.Config.writeBackValues({'onChanged': 'value'})
final class A2uiConfiguredWidget {
  @a2ui.Config.writeBackValue('value')
  final void Function(String) onChanged = ignoreString;
}

void ignoreString(String _) {}

void main() {
  test('RFW config remains a const target annotation', () {
    expect(const rfw.Config(), isA<rfw.Config>());
    expect(RfwConfiguredWidget(), isA<RfwConfiguredWidget>());
  });

  test('A2UI aggregate and shorthand constructors expose their one key', () {
    const aggregate = a2ui.Config(
      usage: 'Use for the primary action.',
      writeBackValues: {'onChanged': 'value'},
    );
    const usage = a2ui.Config.usage('Use for the primary action.');
    const writeBackValues = a2ui.Config.writeBackValues({'onChanged': 'value'});
    const writeBackValue = a2ui.Config.writeBackValue('value');

    expect(aggregate.usage, usage.usage);
    expect(aggregate.writeBackValues, writeBackValues.writeBackValues);
    expect(writeBackValue.writeBackValue, 'value');
    expect(usage.writeBackValues, isNull);
    expect(writeBackValues.usage, isNull);
    expect(A2uiConfiguredWidget().onChanged, same(ignoreString));
  });
}
