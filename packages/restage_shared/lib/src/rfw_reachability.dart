import 'dart:typed_data';

import 'package:restage_shared/src/rfw_formats.dart';

/// Retains entry-reachable declarations and imports.
/// A missing entry returns [library].
RemoteWidgetLibrary retainReachableFrom(
  RemoteWidgetLibrary library,
  String entryWidgetName,
) {
  final declarations = <String, WidgetDeclaration>{
    for (final widget in library.widgets) widget.name: widget,
  };
  if (!declarations.containsKey(entryWidgetName)) {
    return library;
  }

  final reachableNames = <String>{};

  void visitDeclaration(String name) {
    if (!reachableNames.add(name)) {
      return;
    }
    final declaration = declarations[name]!;
    _walk(declaration.initialState, declarations, visitDeclaration);
    _walk(declaration.root, declarations, visitDeclaration);
  }

  visitDeclaration(entryWidgetName);
  if (reachableNames.length == declarations.length) {
    return library;
  }

  return RemoteWidgetLibrary(
    library.imports,
    library.widgets
        .where((widget) => reachableNames.contains(widget.name))
        .toList(),
  );
}

/// Uses bytes at the distinct vendored/upstream RFW type boundary.
/// Returns original bytes when no declarations are stripped.
Uint8List retainReachableFromBlob(Uint8List blob, String entryWidgetName) {
  final library = decodeLibraryBlob(blob);
  final retained = retainReachableFrom(library, entryWidgetName);
  if (identical(retained, library)) return blob;
  return encodeLibraryBlob(retained);
}

void _walk(
  Object? value,
  Map<String, WidgetDeclaration> localDeclarations,
  void Function(String) visitDeclaration,
) {
  if (value == null) return;
  if (value is ConstructorCall) {
    if (localDeclarations.containsKey(value.name)) {
      visitDeclaration(value.name);
    }
    _walk(value.arguments, localDeclarations, visitDeclaration);
    return;
  }
  if (value is WidgetBuilderDeclaration) {
    _walk(value.widget, localDeclarations, visitDeclaration);
    return;
  }
  if (value is Loop) {
    _walk(value.input, localDeclarations, visitDeclaration);
    _walk(value.output, localDeclarations, visitDeclaration);
    return;
  }
  if (value is Switch) {
    _walk(value.input, localDeclarations, visitDeclaration);
    for (final entry in value.outputs.entries) {
      _walk(entry.key, localDeclarations, visitDeclaration);
      _walk(entry.value, localDeclarations, visitDeclaration);
    }
    return;
  }
  if (value is EventHandler) {
    _walk(value.eventArguments, localDeclarations, visitDeclaration);
    return;
  }
  if (value is SetStateHandler) {
    _walk(value.value, localDeclarations, visitDeclaration);
    return;
  }
  if (value is BoundArgsReference) {
    _walk(value.arguments, localDeclarations, visitDeclaration);
    return;
  }
  if (value is BoundLoopReference) {
    _walk(value.value, localDeclarations, visitDeclaration);
    return;
  }
  if (value is Map<Object?, Object?>) {
    for (final entry in value.entries) {
      _walk(entry.key, localDeclarations, visitDeclaration);
      _walk(entry.value, localDeclarations, visitDeclaration);
    }
    return;
  }
  if (value is Iterable<Object?>) {
    for (final element in value) {
      _walk(element, localDeclarations, visitDeclaration);
    }
  }
}
