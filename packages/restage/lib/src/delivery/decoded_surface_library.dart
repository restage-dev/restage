import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart'
    show BlobSurfacePayload, SurfacePayload;
import 'package:rfw/rfw.dart' as rfw;

final _libraries = Expando<rfw.RemoteWidgetLibrary>('decoded surface library');

/// [blob]'s widget library, decoded once for these exact bytes.
@internal
rfw.RemoteWidgetLibrary decodedSurfaceLibrary(Uint8List blob) =>
    _libraries[blob] ??= rfw.decodeLibraryBlob(blob);

/// The widget library of [payload]'s blob, or null when it has none or it
/// cannot be decoded.
@internal
rfw.RemoteWidgetLibrary? decodePayloadLibrary(SurfacePayload payload) {
  if (payload is! BlobSurfacePayload) return null;
  try {
    return rfw.decodeLibraryBlob(payload.blob);
  } on Object {
    return null;
  }
}

/// Records [library] as decoded from [blob] elsewhere.
@internal
void noteDecodedSurfaceLibrary(
        Uint8List blob, rfw.RemoteWidgetLibrary library) =>
    _libraries[blob] = library;
