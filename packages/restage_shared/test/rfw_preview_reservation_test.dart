import 'dart:typed_data';

import 'package:restage_shared/restage_shared.dart'
    show kBuilderContinuationWidgetName;
import 'package:restage_shared/rfw_formats.dart';
import 'package:test/test.dart';

Uint8List _blob(String source) => encodeLibraryBlob(parseLibraryFile(source));

void main() {
  group('preview-only RFW reservation', () {
    test('core reserves its installed library while allowing catalog metadata',
        () {
      final core = hostInstalledRfwLibrary('restage.core')!;
      expect(core.constructors, {kBuilderContinuationWidgetName});
      expect(core.reservesCatalogNamespace, isFalse);
      expect(
          kPreviewInstrumentationRfwLibrary.reservesCatalogNamespace, isTrue);
      expect(
          kMeasurementPresentationRfwLibrary.reservesCatalogNamespace, isTrue);
      expect(
        () => validateRfwBlobForPublish(_blob('''
import restage.core;
widget $kBuilderContinuationWidgetName = Text(text: "shadow");
''')),
        throwsFormatException,
      );
    });

    test('accepts an ordinary custom marker and unrelated imports', () {
      expect(
        () => validateRfwBlobForPublish(
          _blob('''
import acme.widgets;
widget Preview = marker(child: Card());
'''),
        ),
        returnsNormally,
      );
    });

    test('rejects the reserved preview import', () {
      expect(
        () => validateRfwBlobForPublish(
          _blob('''
import restage.editor;
widget Preview = Card();
'''),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains(kReservedPreviewLibraryName),
          ),
        ),
      );
    });

    test('rejects reserved declarations and deeply nested calls', () {
      for (final source in <String>[
        '''
import acme.widgets;
widget $kReservedPreviewConstructorName = Card();
''',
        '''
import acme.widgets;
widget Preview = Column(children: [
  Card(child: $kReservedPreviewConstructorName(child: Text(text: "x"))),
]);
''',
        '''
import acme.widgets;
widget Preview = switch data.kind {
  "a": Card(),
  default: $kReservedPreviewConstructorName(child: Card()),
};
''',
      ]) {
        expect(
          () => validateRfwBlobForPublish(_blob(source)),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains(kReservedPreviewConstructorName),
            ),
          ),
        );
      }
    });

    test('fails closed when the blob cannot be decoded', () {
      expect(
        () => validateRfwBlobForPublish(Uint8List.fromList(const [1, 2, 3])),
        throwsFormatException,
      );
    });
  });
}
