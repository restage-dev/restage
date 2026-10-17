import 'dart:convert';

import 'package:restage_shared/restage_shared.dart'
    show BlobSurfacePayload, SurfaceEditorState;
import 'package:restage_shared/rfw_formats.dart'
    show encodeLibraryBlob, parseLibraryFile;

/// A component version payload in the service's byte wire form: entry
/// `main` is a Container, with the declaration `inner` and one slot.
String componentPayloadWire() {
  final blob = encodeLibraryBlob(
    parseLibraryFile('''
import restage.core;

widget main = Container(child: Text(text: args.label));

widget inner = Text(text: "i");
'''),
  );
  final payload = BlobSurfacePayload(
    minClient: 1,
    blob: blob,
    editorState: SurfaceEditorState(
      meta: {
        'slots': {
          'main': {'label': 'Hello'},
        },
      },
    ).encode(),
  );
  return "decode('${base64Encode(payload.canonicalBytes)}', 'base64')";
}
