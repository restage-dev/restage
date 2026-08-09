import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  test('Dart and RFW identifier policies remain distinct', () {
    for (final name in [r'$source', r'on$Retry']) {
      expect(
        isPublicDartIdentifier(
          name,
          position: DartIdentifierPosition.namedArgument,
        ),
        isTrue,
        reason: '$name is a valid public Dart identifier',
      );
      expect(
        isRfwIdentifier(name),
        isFalse,
        reason: '$name must be quoted when emitted as an RFW key or path part',
      );
    }

    expect(isRfwIdentifier('source_name9'), isTrue);
  });
}
