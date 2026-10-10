import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  const library = WidgetLibrary.custom('acme.widgets');

  group('RestageLibrary.compatibleSince', () {
    test('defaults to 1', () {
      const annotation = RestageLibrary(library: library, capabilityVersion: 3);
      expect(annotation.compatibleSince, 1);
    });

    test('accepts a value up to capabilityVersion', () {
      const annotation = RestageLibrary(
        library: library,
        capabilityVersion: 4,
        compatibleSince: 4,
      );
      expect(annotation.compatibleSince, 4);
    });

    test('rejects a value above capabilityVersion', () {
      expect(
        () => RestageLibrary(
          library: library,
          capabilityVersion: 3,
          compatibleSince: 4,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects a value below 1', () {
      expect(
        () => RestageLibrary(
          library: library,
          capabilityVersion: 3,
          compatibleSince: 0,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects a break on a library with no capabilityVersion', () {
      expect(
        () => RestageLibrary(library: library, compatibleSince: 2),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('LibraryInfo.compatibleSince', () {
    test('defaults to 1 and takes part in equality', () {
      const base = LibraryInfo(version: '1.0.0', capabilityVersion: 4);
      expect(base.compatibleSince, 1);
      const broken = LibraryInfo(
        version: '1.0.0',
        capabilityVersion: 4,
        compatibleSince: 4,
      );
      expect(broken, isNot(base));
      expect(
        broken,
        const LibraryInfo(
          version: '1.0.0',
          capabilityVersion: 4,
          compatibleSince: 4,
        ),
      );
      expect(broken.hashCode, isNot(base.hashCode));
    });
  });
}
