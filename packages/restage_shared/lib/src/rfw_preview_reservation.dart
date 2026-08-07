import 'dart:typed_data';

import 'package:restage_shared/src/rfw_formats.dart';

/// Preview-only library namespace reserved by Restage's render hosts.
const String kReservedPreviewLibraryName = 'restage.editor';

/// Preview-only constructor reserved for authored-node geometry markers.
const String kReservedPreviewConstructorName =
    '__restage_internal_geometry_marker_v1__';

/// Rejects an RFW library blob that claims Restage's preview-only symbols.
///
/// Publish and build tooling call this before accepting customer content. The
/// full library is decoded and walked so a claim cannot hide in a nested
/// constructor, switch, loop, builder, event payload, or state value. Decode
/// failures are deliberately propagated: content that cannot be inspected is
/// not safe to publish.
void validateRfwBlobForPublish(Uint8List blob) {
  final library = decodeLibraryBlob(blob);
  _validateLibrary(library);
}

void _validateLibrary(RemoteWidgetLibrary library) {
  for (final import in library.imports) {
    if (import.name.parts.join('.') == kReservedPreviewLibraryName) {
      throw const FormatException(
        'RFW blobs must not import the reserved preview library '
        '"restage.editor".',
      );
    }
  }
  for (final widget in library.widgets) {
    if (widget.name == kReservedPreviewConstructorName) {
      throw const FormatException(
        'RFW blobs must not declare the reserved preview constructor '
        '"__restage_internal_geometry_marker_v1__".',
      );
    }
    _walk(widget.initialState);
    _walk(widget.root);
  }
}

void _walk(Object? value) {
  if (value == null) return;
  if (value is ConstructorCall) {
    if (value.name == kReservedPreviewConstructorName) {
      throw const FormatException(
        'RFW blobs must not call the reserved preview constructor '
        '"__restage_internal_geometry_marker_v1__".',
      );
    }
    _walk(value.arguments);
    return;
  }
  if (value is WidgetBuilderDeclaration) {
    _walk(value.widget);
    return;
  }
  if (value is Loop) {
    _walk(value.input);
    _walk(value.output);
    return;
  }
  if (value is Switch) {
    _walk(value.input);
    for (final entry in value.outputs.entries) {
      _walk(entry.key);
      _walk(entry.value);
    }
    return;
  }
  if (value is EventHandler) {
    _walk(value.eventArguments);
    return;
  }
  if (value is SetStateHandler) {
    _walk(value.value);
    return;
  }
  if (value is BoundArgsReference) {
    _walk(value.arguments);
    return;
  }
  if (value is BoundLoopReference) {
    _walk(value.value);
    return;
  }
  if (value is Map<Object?, Object?>) {
    for (final entry in value.entries) {
      _walk(entry.key);
      _walk(entry.value);
    }
    return;
  }
  if (value is Iterable<Object?>) {
    value.forEach(_walk);
  }
}
