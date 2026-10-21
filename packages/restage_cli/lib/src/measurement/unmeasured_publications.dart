import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_shared/restage_shared.dart';

import '../publication/publication_manifest.dart';
import 'measurement_publication_candidate_assembler.dart'
    show restageMeasurementPublicationIndexFileName;

/// A warning that [entry] compiles unmeasured, with the build's reason, or
/// null when the Measurement index does not list it as unmeasured.
String? unmeasuredPublicationWarning(
  LoadedSurfacePublicationManifest loaded,
  SurfacePublicationManifestEntry entry,
) {
  final file = File(
    p.join(
      loaded.outputsFile.parent.path,
      restageMeasurementPublicationIndexFileName,
    ),
  );
  final Object? root;
  try {
    if (!file.existsSync()) return null;
    root = jsonDecode(file.readAsStringSync());
  } on Object {
    // The index reader refuses a broken index on its own path.
    return null;
  }
  if (root is! Map<String, Object?>) return null;
  final publication = entry.publication;
  for (final item in root['unmeasured'] as List<Object?>? ?? const []) {
    if (item is! Map<String, Object?>) continue;
    final selector = item['selector'];
    final reason = item['reason'];
    if (selector is! Map<String, Object?> || reason is! String) continue;
    if (selector['surface'] != publication.surface.wireName ||
        selector['slug'] != publication.slug ||
        selector['sourceKind'] != publication.sourceKind.wireName ||
        selector['contractVersion'] != publication.contractVersion) {
      continue;
    }
    final sentence = reason.trim().replaceFirst(RegExp(r'\.+$'), '');
    return '${publication.slug} compiles unmeasured: $sentence. '
        'Its taps and views are not counted.';
  }
  return null;
}
