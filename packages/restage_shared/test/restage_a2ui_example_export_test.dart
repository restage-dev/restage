import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  test('restage_shared exports the A2UI authoring annotations', () {
    const annotation = RestageA2uiExample(
      name: 'Default',
      asset: 'lib/a2ui_examples/card/default.json',
    );
    const dataField = RestageDataField(description: 'Card label.');

    expect(annotation.name, 'Default');
    expect(dataField.description, 'Card label.');
  });
}
