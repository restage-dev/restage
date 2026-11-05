import 'dart:convert';
import 'dart:typed_data';

import 'package:restage_codegen/src/capability_derivation.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;

/// A `@RestageWidget` definition a surface's design delivers, as the shared
/// component version a push publishes.
final class DeliveredComponent {
  /// Creates a delivered component.
  const DeliveredComponent({
    required this.name,
    required this.declaration,
    required this.payload,
    required this.fingerprint,
    required this.parts,
  });

  /// Decodes [toJson].
  factory DeliveredComponent.fromJson(Map<String, Object?> json) =>
      DeliveredComponent(
        name: json['name']! as String,
        declaration: json['declaration']! as String,
        payload: base64Decode(json['payload']! as String),
        fingerprint: json['fingerprint']! as String,
        parts: [...(json['parts']! as List).cast<String>()],
      );

  /// The component's name: the widget's library namespace and catalog name.
  final String name;

  /// The declaration the surface's design delivers it as.
  final String declaration;

  /// The encoded component version.
  final Uint8List payload;

  /// The definition's fingerprint, as a pin records it.
  final String fingerprint;

  /// The declarations it reaches besides its own, in canonical order.
  final List<String> parts;

  /// The handoff form.
  Map<String, Object?> toJson() => {
    'name': name,
    'declaration': declaration,
    'payload': base64Encode(payload),
    'fingerprint': fingerprint,
    'parts': parts,
  };
}

/// The custom widgets of [catalog] that [blob] declares, each as a component
/// version whose requirements are derived from its own declarations.
List<DeliveredComponent> deliveredComponents(
  Uint8List blob,
  Catalog catalog,
  List<Issue> issues,
) {
  final declared = {
    for (final widget in fmt.decodeLibraryBlob(blob).widgets) widget.name,
  };
  final components = <DeliveredComponent>[];
  for (final entry in catalog.widgets) {
    final namespace = entry.library.namespace;
    if (WidgetLibrary.builtInByNamespace(namespace) != null ||
        (catalog.libraries[entry.library]?.islands ?? false)) {
      continue;
    }
    final declaration = entry.flutterType.split('#').last;
    if (!declared.contains(declaration)) continue;
    final component = componentLibraryBlob(blob, declaration, catalog: catalog);
    final derivation = deriveCapabilityManifest(
      fmt.decodeLibraryBlob(component),
      catalog,
    );
    final manifest = derivation.manifest;
    if (manifest == null) {
      issues.addAll(derivation.issues);
      continue;
    }
    final definition = componentFingerprint(blob, declaration, const {});
    components.add(
      DeliveredComponent(
        name: '$namespace.${entry.name}',
        declaration: declaration,
        payload: BlobSurfacePayload(
          minClient: manifest.builtInFloor,
          blob: component,
          requiredLibraries: manifest.requiredLibraries,
          editorState: SurfaceEditorState(
            meta: const {'slots': <String, Object?>{}},
          ).encode(),
        ).canonicalBytes,
        fingerprint: definition.fingerprint,
        parts: definition.parts,
      ),
    );
  }
  return components..sort((a, b) => a.name.compareTo(b.name));
}
