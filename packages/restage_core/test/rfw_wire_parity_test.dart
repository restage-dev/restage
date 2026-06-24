// Cross-codec wire-format parity gate.
//
// The build-time toolchain encodes `.rfw` blobs with a vendored, pure-Dart copy
// of the rfw `formats` library (re-exported by `package:restage_shared/`), so a
// Dart-only build image does not need the Flutter SDK. The customer app runtime
// — and the editor's blob encoder — instead use the published `package:rfw`.
// `restage_shared` carries no `rfw` dependency, so the runtime's `rfw` version
// floats independently of the frozen vendored copy.
//
// Nothing else asserts that the two codecs agree. This gate closes that gap. It
// proves, for a representative library, that:
//   1. the vendored encoder and the pub encoder emit byte-identical output, and
//   2. each codec can decode the other's blob and re-encode it byte-identically.
//
// A breaking binary-format change in a future pub `rfw` minor would fail here
// rather than silently skewing a server-produced blob against a newer runtime
// decoder.

import 'package:flutter_test/flutter_test.dart';
import 'package:restage_shared/rfw_formats.dart' as vendored;
import 'package:rfw/formats.dart' as pub;

void main() {
  // A source that exercises every binary tag arm reachable in production so a
  // format divergence surfaces on at least one node kind: imports; a stateless
  // and a stateful widget (boolean initialState); hex-int, double, string, and
  // boolean scalars; list literals; nested map literals (incl. a list-of-maps);
  // args references; data-model references (data.*); a loop (...for); state
  // references (state.*); a set-state handler; an event handler with a
  // structured argument; and switches over both args and state.
  const source = '''
import core.widgets;

widget Hello = Container(
  padding: [8.0, 12.0, 8.0, 12.0],
  color: 0xFF112233,
  alignment: data.theme.alignment,
  child: Column(
    children: [
      Text(text: data.title, softWrap: true),
      ...for label in args.features: Text(text: label),
    ],
  ),
);

widget Counter { selected: false } = Container(
  decoration: {
    color: 0xFF445566,
    boxShadow: [
      { color: 0xFF000000, blurRadius: 4.0, offset: { x: 0.0, y: 2.0 } },
    ],
  },
  child: Column(
    children: [
      GestureDetector(
        onTap: set state.selected = true,
        child: Container(
          color: switch state.selected { true: 0xFF00FF00, false: 0xFFFF0000 },
          child: args.label,
        ),
      ),
      GestureDetector(
        onTap: event "restage.purchase" {
          slot: switch state.selected { true: "annual", false: "monthly" },
        },
        child: switch args.theme {
          "dark": Text(text: "dark"),
          "light": Text(text: "light"),
          default: Text(text: "default"),
        },
      ),
    ],
  ),
);
''';

  group('rfw wire-format parity: vendored restage_shared <-> pub rfw', () {
    test('the two encoders emit byte-identical output for the same source', () {
      final vendoredBytes =
          vendored.encodeLibraryBlob(vendored.parseLibraryFile(source));
      final pubBytes = pub.encodeLibraryBlob(pub.parseLibraryFile(source));

      expect(
        vendoredBytes,
        orderedEquals(pubBytes),
        reason: 'The vendored build-time encoder and the pub runtime/editor '
            'encoder must emit identical bytes. A divergence means an editor- '
            'and a codegen-published blob would differ on the wire despite the '
            'one-delivery-path invariant.',
      );
    });

    test('pub rfw decodes a vendored blob and re-encodes it byte-identically',
        () {
      final vendoredBytes =
          vendored.encodeLibraryBlob(vendored.parseLibraryFile(source));

      final decodedByPub = pub.decodeLibraryBlob(vendoredBytes);
      final reEncodedByPub = pub.encodeLibraryBlob(decodedByPub);

      expect(
        reEncodedByPub,
        orderedEquals(vendoredBytes),
        reason: 'The runtime (pub) decoder must read a build-time (vendored) '
            'blob and reproduce it exactly. This is the live skew window: a '
            'server blob is written by the vendored codec and read by pub rfw.',
      );
    });

    test('vendored decodes a pub blob and re-encodes it byte-identically', () {
      final pubBytes = pub.encodeLibraryBlob(pub.parseLibraryFile(source));

      final decodedByVendored = vendored.decodeLibraryBlob(pubBytes);
      final reEncodedByVendored = vendored.encodeLibraryBlob(decodedByVendored);

      expect(
        reEncodedByVendored,
        orderedEquals(pubBytes),
        reason: 'The build-time (vendored) decoder must read a pub-encoded '
            'blob and reproduce it exactly (the reverse direction).',
      );
    });
  });
}
