import 'dart:typed_data';

import 'package:restage_shared/rfw_formats.dart';
import 'package:test/test.dart';

Uint8List _blob(String source) => encodeLibraryBlob(parseLibraryFile(source));

void main() {
  group('preview-only RFW reservation', () {
    test('accepts an ordinary customer marker and unrelated imports', () {
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
