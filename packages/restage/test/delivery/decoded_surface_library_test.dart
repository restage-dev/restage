import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/delivery/decoded_surface_library.dart';
import 'package:rfw/formats.dart';

void main() {
  Uint8List blob() =>
      encodeLibraryBlob(parseLibraryFile('widget root = Text(text: "Hello");'));

  test('one decode serves every lookup of the same bytes', () {
    final bytes = blob();
    final first = decodedSurfaceLibrary(bytes);
    expect(first.widgets.single.name, 'root');
    expect(decodedSurfaceLibrary(bytes), same(first));
    // Equal bytes in another buffer are decoded on their own.
    expect(decodedSurfaceLibrary(blob()), isNot(same(first)));
  });

  test('a library decoded elsewhere is used without decoding again', () {
    final noted = decodedSurfaceLibrary(blob());
    // These bytes are not a blob, so only the noted library can answer.
    final bytes = Uint8List.fromList([0, 1, 2, 3]);
    noteDecodedSurfaceLibrary(bytes, noted);
    expect(decodedSurfaceLibrary(bytes), same(noted));
  });
}
