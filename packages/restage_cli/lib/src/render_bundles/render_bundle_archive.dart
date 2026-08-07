import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:restage_shared/rfw_formats.dart'
    show kReservedPreviewConstructorName, kReservedPreviewLibraryName;

/// Canonical capability manifest stored beside every render bundle.
const renderBundleCapabilityManifestPath = 'restage_bundle_manifest.json';

/// Complete client-side upload ceiling, measured on the RAW container.
const renderBundleMaxArchiveBytes = 64 * 1024 * 1024;

/// Ceiling for the bytes actually put on the wire for one upload.
///
/// The raw container is gzipped for transport, so this bounds the compressed
/// body, not the archive. It sits well under the 32 MiB single-request body
/// limit imposed by the serving platform: a raw 64 MiB archive of Flutter web
/// artifacts compresses far below this, and anything that does not is refused
/// locally with a clear error instead of a generic edge rejection.
const renderBundleMaxUploadTransferBytes = 24 * 1024 * 1024;

const _magic = <int>[0x52, 0x42, 0x53, 0x52, 0x41, 0x57, 0x31, 0x0a];

/// Conservative limits mirrored by the server-side archive parser.
final class RenderBundleArchiveLimits {
  const RenderBundleArchiveLimits({
    this.maxFiles = 512,
    this.maxPathBytes = 512,
    this.maxFileBytes = 32 * 1024 * 1024,
    this.maxManifestBytes = 1024 * 1024,
    this.maxTotalBytes = renderBundleMaxArchiveBytes,
    this.maxCapabilityManifestBytes = 1024 * 1024,
    this.maxCapabilityManifestDepth = 64,
    this.maxCapabilityManifestNodes = 20000,
  });

  final int maxFiles;
  final int maxPathBytes;
  final int maxFileBytes;
  final int maxManifestBytes;
  final int maxTotalBytes;
  final int maxCapabilityManifestBytes;
  final int maxCapabilityManifestDepth;
  final int maxCapabilityManifestNodes;
}

/// A local validation failure that is safe for callers to render generically.
final class RenderBundleArchiveException implements Exception {
  const RenderBundleArchiveException(this.reason);

  final String reason;

  @override
  String toString() => 'RenderBundleArchiveException($reason)';
}

/// Builds the deterministic raw render-bundle container from one directory.
Future<Uint8List> encodeRenderBundleDirectory(
  Directory root, {
  RenderBundleArchiveLimits limits = const RenderBundleArchiveLimits(),
}) async {
  _validateLimits(limits);
  if (!root.existsSync() ||
      await FileSystemEntity.type(root.path, followLinks: false) !=
          FileSystemEntityType.directory) {
    throw const RenderBundleArchiveException('artifact_missing');
  }
  final files = <String, Uint8List>{};
  var payloadBytes = 0;
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    final type = await FileSystemEntity.type(entity.path, followLinks: false);
    if (type == FileSystemEntityType.directory) continue;
    if (type != FileSystemEntityType.file || entity is! File) {
      throw const RenderBundleArchiveException('non_regular_file');
    }
    final relative = p.relative(entity.path, from: root.path);
    final path = p.posix.joinAll(p.split(relative));
    _validatePath(path, limits);
    if (files.containsKey(path)) {
      throw const RenderBundleArchiveException('duplicate_path');
    }
    if (files.length >= limits.maxFiles) {
      throw const RenderBundleArchiveException('file_count');
    }
    final stat = await entity.stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size > limits.maxFileBytes) {
      throw const RenderBundleArchiveException('file_too_large');
    }
    if (payloadBytes > limits.maxTotalBytes - stat.size) {
      throw const RenderBundleArchiveException('payload_too_large');
    }
    final bytes = await entity.readAsBytes();
    if (bytes.length != stat.size) {
      throw const RenderBundleArchiveException('artifact_changed');
    }
    payloadBytes += bytes.length;
    files[path] = bytes;
  }
  validateOfflineRenderBundleFiles(files);
  return encodeRenderBundleArchive(files, limits: limits);
}

/// Encodes exact file bytes into the canonical, sorted uncompressed container.
Uint8List encodeRenderBundleArchive(
  Map<String, Uint8List> files, {
  RenderBundleArchiveLimits limits = const RenderBundleArchiveLimits(),
}) {
  _validateLimits(limits);
  if (files.isEmpty || files.length > limits.maxFiles) {
    throw const RenderBundleArchiveException('file_count');
  }
  if (!files.containsKey('index.html') ||
      !files.containsKey(renderBundleCapabilityManifestPath)) {
    throw const RenderBundleArchiveException('required_file_missing');
  }

  _validateCapabilityManifest(
    files[renderBundleCapabilityManifestPath]!,
    limits,
  );
  final paths = files.keys.toList()..sort();
  final entries = <Map<String, Object?>>[];
  var payloadBytes = 0;
  for (final path in paths) {
    _validatePath(path, limits);
    final bytes = files[path]!;
    if (bytes.length > limits.maxFileBytes) {
      throw const RenderBundleArchiveException('file_too_large');
    }
    if (payloadBytes > limits.maxTotalBytes - bytes.length) {
      throw const RenderBundleArchiveException('payload_too_large');
    }
    payloadBytes += bytes.length;
    entries.add(<String, Object?>{
      'path': path,
      'type': 'file',
      'length': bytes.length,
      'sha256': crypto.sha256.convert(bytes).toString(),
    });
  }
  final manifest = Uint8List.fromList(
    utf8.encode(
      jsonEncode(<String, Object?>{'formatVersion': 1, 'files': entries}),
    ),
  );
  if (manifest.length > limits.maxManifestBytes) {
    throw const RenderBundleArchiveException('manifest_too_large');
  }
  final total = _magic.length + 4 + manifest.length + payloadBytes;
  if (total > limits.maxTotalBytes) {
    throw const RenderBundleArchiveException('archive_too_large');
  }
  final length = ByteData(4)..setUint32(0, manifest.length, Endian.big);
  final output = BytesBuilder(copy: false)
    ..add(_magic)
    ..add(length.buffer.asUint8List())
    ..add(manifest);
  for (final path in paths) {
    output.add(files[path]!);
  }
  return output.takeBytes();
}

/// Returns the exact compact capability-manifest bytes for generated catalog JSON.
Uint8List createRenderBundleCapabilityManifest(String catalogJson) {
  const limits = RenderBundleArchiveLimits();
  if (utf8.encode(catalogJson).length > limits.maxCapabilityManifestBytes) {
    throw const RenderBundleArchiveException('catalog_too_large');
  }
  _preflightJsonNesting(
    catalogJson,
    maxDepth: limits.maxCapabilityManifestDepth - 1,
  );
  final Object? decoded;
  try {
    decoded = jsonDecode(catalogJson);
  } on FormatException {
    throw const RenderBundleArchiveException('catalog_not_json');
  }
  if (decoded is! Map<Object?, Object?>) {
    throw const RenderBundleArchiveException('catalog_not_object');
  }
  final catalog = _stringMap(decoded, 'catalog');
  final manifest = Uint8List.fromList(
    utf8.encode('{"formatVersion":1,"catalog":${_canonicalJson(catalog)}}'),
  );
  _validateCapabilityManifest(manifest, limits);
  return manifest;
}

/// Verifies the artifact has no external-resource or service-worker escape.
void validateOfflineRenderBundleFiles(Map<String, Uint8List> files) {
  for (final path in files.keys) {
    final lower = path.toLowerCase();
    if (lower.contains('service_worker') ||
        lower.endsWith('serviceworker.js')) {
      throw const RenderBundleArchiveException('service_worker_forbidden');
    }
  }
  for (final entry in files.entries) {
    final lower = entry.key.toLowerCase();
    if (lower.endsWith('.html') || lower.endsWith('.css')) {
      final source = _decodeText(entry.value, 'resource_not_utf8');
      final references = <String>[];
      if (lower.endsWith('.html')) {
        final attribute = RegExp(
          r'''\b(?:src|href)\s*=\s*["']([^"']+)["']''',
          caseSensitive: false,
        );
        references.addAll(attribute.allMatches(source).map((m) => m.group(1)!));
      }
      final urls = RegExp(
        r'''url\(\s*["']?([^\s"')]+)''',
        caseSensitive: false,
      );
      references.addAll(urls.allMatches(source).map((m) => m.group(1)!));
      final imports = RegExp(
        r'''@import\s+["']([^"']+)["']''',
        caseSensitive: false,
      );
      references.addAll(imports.allMatches(source).map((m) => m.group(1)!));
      for (final reference in references) {
        final uri = Uri.tryParse(reference);
        if (uri == null ||
            uri.hasScheme ||
            uri.hasAuthority ||
            reference.startsWith('//')) {
          throw const RenderBundleArchiveException('external_resource');
        }
      }
    }
    if (lower.endsWith('.map')) {
      final Object? decoded;
      try {
        decoded = jsonDecode(_decodeText(entry.value, 'source_map_not_utf8'));
      } on FormatException {
        throw const RenderBundleArchiveException('source_map_not_json');
      }
      if (decoded is! Map<Object?, Object?> || decoded['sources'] is! List) {
        throw const RenderBundleArchiveException('source_map_shape');
      }
      for (final source in decoded['sources']! as List<dynamic>) {
        if (source is! String ||
            source.startsWith('/') ||
            source.contains(r'\') ||
            source.split('/').contains('..') ||
            Uri.tryParse(source)?.hasScheme == true) {
          throw const RenderBundleArchiveException('source_map_escape');
        }
      }
    }
  }
}

void _validateCapabilityManifest(
  Uint8List bytes,
  RenderBundleArchiveLimits limits,
) {
  if (bytes.length > limits.maxCapabilityManifestBytes) {
    throw const RenderBundleArchiveException('capability_manifest_too_large');
  }
  final source = _decodeText(bytes, 'capability_manifest_not_utf8');
  _preflightJsonNesting(source, maxDepth: limits.maxCapabilityManifestDepth);
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    throw const RenderBundleArchiveException('capability_manifest_not_json');
  }
  if (decoded is! Map<Object?, Object?> ||
      decoded.length != 2 ||
      decoded['formatVersion'] != 1 ||
      decoded['catalog'] is! Map<Object?, Object?>) {
    throw const RenderBundleArchiveException('capability_manifest_shape');
  }
  final catalog = _stringMap(
    decoded['catalog']! as Map<Object?, Object?>,
    'catalog',
  );
  _validateCapabilityCatalogGraph(catalog, limits);
  final libraries = catalog['libraries'];
  final widgets = catalog['widgets'];
  if (libraries is! Map<Object?, Object?> || widgets is! List<Object?>) {
    throw const RenderBundleArchiveException('catalog_indexes');
  }
  _validateCatalogIndexes(catalog);
}

void _validateCapabilityCatalogGraph(
  Map<String, Object?> catalog,
  RenderBundleArchiveLimits limits,
) {
  final stack = <(Object?, int)>[(catalog, 1)];
  var nodes = 0;
  while (stack.isNotEmpty) {
    final (value, depth) = stack.removeLast();
    if (depth > limits.maxCapabilityManifestDepth) {
      throw const RenderBundleArchiveException('capability_manifest_too_deep');
    }
    if (++nodes > limits.maxCapabilityManifestNodes) {
      throw const RenderBundleArchiveException(
        'capability_manifest_too_complex',
      );
    }
    if (value is Map<Object?, Object?>) {
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw const RenderBundleArchiveException('manifest_non_string_key');
        }
        final key = (entry.key! as String).toLowerCase().replaceAll(
          RegExp('[^a-z]'),
          '',
        );
        if (_credentialKeys.contains(key)) {
          throw const RenderBundleArchiveException('manifest_credential_field');
        }
        stack.add((entry.value, depth + 1));
      }
    } else if (value is List<Object?>) {
      for (final element in value) {
        stack.add((element, depth + 1));
      }
    } else if (value is num && !value.isFinite) {
      throw const RenderBundleArchiveException('manifest_non_finite');
    }
  }
}

void _preflightJsonNesting(String source, {required int maxDepth}) {
  final stack = <int>[];
  var inString = false;
  var escaped = false;
  for (final codeUnit in source.codeUnits) {
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (codeUnit == 0x5c) {
        escaped = true;
      } else if (codeUnit == 0x22) {
        inString = false;
      }
      continue;
    }
    if (codeUnit == 0x22) {
      inString = true;
    } else if (codeUnit == 0x7b || codeUnit == 0x5b) {
      stack.add(codeUnit);
      if (stack.length > maxDepth) {
        throw const RenderBundleArchiveException(
          'capability_manifest_too_deep',
        );
      }
    } else if (codeUnit == 0x7d || codeUnit == 0x5d) {
      if (stack.isEmpty ||
          stack.removeLast() != (codeUnit == 0x7d ? 0x7b : 0x5b)) {
        throw const RenderBundleArchiveException('capability_manifest_nesting');
      }
    }
  }
  if (inString || stack.isNotEmpty) {
    throw const RenderBundleArchiveException('capability_manifest_nesting');
  }
}

void _validateCatalogIndexes(Map<String, Object?> catalog) {
  final libraries = _requiredMap(catalog, 'libraries');
  if (libraries.containsKey(kReservedPreviewLibraryName)) {
    throw const RenderBundleArchiveException('catalog_reserved_library');
  }
  for (final entry in libraries.entries) {
    if (entry.key.trim().isEmpty) {
      throw const RenderBundleArchiveException('catalog_library_name');
    }
    final library = _stringMapFromValue(entry.value, 'library');
    final capabilityVersion = library['capabilityVersion'];
    if (capabilityVersion != null &&
        (capabilityVersion is! int || capabilityVersion < 1)) {
      throw const RenderBundleArchiveException('catalog_capability_version');
    }
  }

  final widgets = catalog['widgets'];
  if (widgets is! List<Object?>) {
    throw const RenderBundleArchiveException('catalog_widgets');
  }
  final identities = <String>{};
  for (final value in widgets) {
    final widget = _stringMapFromValue(value, 'widget');
    final library = _requiredNonEmptyString(widget, 'library');
    final name = _requiredNonEmptyString(widget, 'name');
    if (name == kReservedPreviewConstructorName) {
      throw const RenderBundleArchiveException('catalog_reserved_widget');
    }
    if (!libraries.containsKey(library)) {
      throw const RenderBundleArchiveException('catalog_widget_library');
    }
    final wireId = widget['wireId'];
    if (wireId != null && (wireId is! String || wireId.trim().isEmpty)) {
      throw const RenderBundleArchiveException('catalog_widget_wire_id');
    }
    if (!identities.add('$library\u0000$name')) {
      throw const RenderBundleArchiveException('catalog_widget_duplicate');
    }
  }
}

Map<String, Object?> _requiredMap(Map<String, Object?> map, String key) =>
    _stringMapFromValue(map[key], key);

Map<String, Object?> _stringMapFromValue(Object? value, String label) {
  if (value is! Map<Object?, Object?>) {
    throw RenderBundleArchiveException('${label}_not_object');
  }
  return _stringMap(value, label);
}

String _requiredNonEmptyString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw RenderBundleArchiveException('${key}_not_nonempty_string');
  }
  return value;
}

String _canonicalJson(Object? value) {
  if (value is Map<Object?, Object?>) {
    final map = _stringMap(value, 'json');
    final keys = map.keys.toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(map[key])}').join(',')}}';
  }
  if (value is List<Object?>) {
    return '[${value.map(_canonicalJson).join(',')}]';
  }
  if (value == null || value is bool || value is String || value is num) {
    if (value is num && !value.isFinite) {
      throw const RenderBundleArchiveException('json_non_finite');
    }
    return jsonEncode(value);
  }
  throw const RenderBundleArchiveException('json_value');
}

Map<String, Object?> _stringMap(Map<Object?, Object?> source, String label) {
  final result = <String, Object?>{};
  for (final entry in source.entries) {
    if (entry.key is! String) {
      throw RenderBundleArchiveException('${label}_non_string_key');
    }
    result[entry.key! as String] = entry.value;
  }
  return result;
}

String _decodeText(Uint8List bytes, String reason) {
  try {
    return utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    throw RenderBundleArchiveException(reason);
  }
}

void _validatePath(String path, RenderBundleArchiveLimits limits) {
  if (path.isEmpty ||
      path.startsWith('/') ||
      path.contains(r'\') ||
      path.contains('//') ||
      utf8.encode(path).length > limits.maxPathBytes ||
      !RegExp(r"^[A-Za-z0-9._~!$&'()+,;=@/-]+$").hasMatch(path)) {
    throw const RenderBundleArchiveException('unsafe_path');
  }
  final segments = path.split('/');
  if (segments.any(
    (segment) =>
        segment.isEmpty ||
        segment == '.' ||
        segment == '..' ||
        segment.trim() != segment,
  )) {
    throw const RenderBundleArchiveException('unsafe_path');
  }
}

void _validateLimits(RenderBundleArchiveLimits limits) {
  if (limits.maxFiles <= 0 ||
      limits.maxPathBytes <= 0 ||
      limits.maxFileBytes < 0 ||
      limits.maxManifestBytes <= 0 ||
      limits.maxTotalBytes <= 0 ||
      limits.maxCapabilityManifestBytes <= 0 ||
      limits.maxCapabilityManifestDepth <= 0 ||
      limits.maxCapabilityManifestNodes <= 0) {
    throw ArgumentError.value(limits, 'limits');
  }
}

const _credentialKeys = <String>{
  'auth',
  'csrftoken',
  'privatekey',
  'dashboardstate',
  'apikey',
  'sessionkey',
  'jwt',
  'bearer',
  'token',
  'accesstoken',
  'refreshtoken',
  'authorization',
  'authorizationheader',
  'authheader',
  'authtoken',
  'idtoken',
  'apitoken',
  'sessiontoken',
  'bearertoken',
  'cookie',
  'cookies',
  'sessioncookie',
  'authcookie',
  'credential',
  'credentials',
  'authcredential',
  'authcredentials',
  'usercredential',
  'password',
  'currentpassword',
  'newpassword',
  'secret',
  'clientsecret',
  'apisecret',
  'signingsecret',
};
