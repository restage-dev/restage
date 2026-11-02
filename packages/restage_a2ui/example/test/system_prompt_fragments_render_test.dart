import 'package:flutter_test/flutter_test.dart';
import 'package:restage_a2ui_example/generated/restage_a2ui_catalog.g.dart';

void main() {
  test('buildRestageCatalog carries the authored producer instructions', () {
    final catalog = buildRestageCatalog();

    expect(
      catalog.instructions,
      contains(
        'Callout: Use for a short highlighted aside around optional content.',
      ),
    );
    // SectionHeader has no usage note, so it falls back to its description.
    expect(catalog.instructions, contains('SectionHeader: '));
    expect(catalog.components.values, isNotEmpty);
  });
}
