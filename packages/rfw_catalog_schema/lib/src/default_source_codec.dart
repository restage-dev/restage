/// Shared JSON codec for [DefaultValueSource] and its building blocks.
///
/// Hosting the encoder / decoder here, together with the `WireIdRef` and
/// `ThemeBindingPath` helpers it depends on, keeps default-source parsing in
/// one place for the canonical catalog codec.
///
/// These functions are library-public within `rfw_catalog_schema` but are
/// deliberately not re-exported from the package barrels; they are an
/// internal codec detail, not public API.
library;

import 'package:rfw_catalog_schema/src/catalog_codec.dart'
    show CatalogSchemaException;
import 'package:rfw_catalog_schema/src/default_value_source.dart';
import 'package:rfw_catalog_schema/src/theme_binding.dart';
import 'package:rfw_catalog_schema/src/wire_id.dart';

/// Encode a [DefaultValueSource] as a JSON object.
Map<String, dynamic> defaultSourceToJson(DefaultValueSource s) {
  return switch (s) {
    LiteralDefault(:final value) => {'kind': s.kind.name, 'value': value},
    TokenRefDefault(:final token) => {
        'kind': s.kind.name,
        'token': wireIdRefToJson(token),
      },
    ThemeBindingDefault(:final path) => {
        'kind': s.kind.name,
        'path': themeBindingToJson(path),
      },
    FlutterCtorDefault() => {'kind': s.kind.name},
  };
}

/// Decode a [DefaultValueSource] from [raw], returning `null` when [raw] is
/// `null` (the field is optional in both wire shapes).
///
/// Throws [CatalogSchemaException] on a malformed object or an unknown kind.
DefaultValueSource? defaultSourceFromJson(Object? raw, String path) {
  if (raw == null) return null;
  if (raw is! Map) {
    throw CatalogSchemaException(
      '$path: defaultSource must be an object; got ${raw.runtimeType}',
    );
  }
  final j = raw.cast<String, dynamic>();
  final rawKind = j['kind'];
  if (rawKind is! String) {
    throw CatalogSchemaException(
      '$path: defaultSource missing required string field: kind',
    );
  }
  final DefaultValueSourceKind kind;
  try {
    kind = DefaultValueSourceKind.values.byName(rawKind);
    // ArgumentError carries the unknown-enum-name detail we surface
    // through CatalogSchemaException's contract.
    // ignore: avoid_catching_errors
  } on ArgumentError {
    throw CatalogSchemaException(
      "$path: unknown defaultSource kind '$rawKind'; expected one of "
      '${DefaultValueSourceKind.values.map((k) => k.name).join(', ')}',
    );
  }
  switch (kind) {
    case DefaultValueSourceKind.literal:
      // Guard on the value itself, not just `containsKey`: an explicit JSON
      // null is present yet would throw a raw TypeError on the `Object` cast,
      // escaping the codec's CatalogSchemaException contract.
      final value = j['value'];
      if (value == null) {
        throw CatalogSchemaException(
          '$path: literal defaultSource missing required field: value',
        );
      }
      // Safe: the null guard above means this cast can never throw, so no
      // raw TypeError escapes here.
      return LiteralDefault(value as Object);
    case DefaultValueSourceKind.tokenRef:
      if (j['token'] is! Map) {
        throw CatalogSchemaException(
          '$path: tokenRef defaultSource missing required map field: token',
        );
      }
      return TokenRefDefault(
        wireIdRefFromJson(
          (j['token'] as Map).cast<String, dynamic>(),
          '$path.token',
          expectedKind: WireIdKind.designToken,
        ),
      );
    case DefaultValueSourceKind.themeBinding:
      if (j['path'] is! Map) {
        throw CatalogSchemaException(
          '$path: themeBinding defaultSource missing required map field: path',
        );
      }
      return ThemeBindingDefault(
        themeBindingFromJson(
          (j['path'] as Map).cast<String, dynamic>(),
          '$path.path',
        ),
      );
    case DefaultValueSourceKind.flutterCtorDefault:
      return const FlutterCtorDefault();
  }
}

/// Encode a [ThemeBindingPath] as a JSON object.
Map<String, dynamic> themeBindingToJson(ThemeBindingPath p) => {
      if (p.path != null) 'path': p.path,
      if (p.resolverName != null) 'resolverName': p.resolverName,
    };

/// Decode a [ThemeBindingPath] from a JSON object.
///
/// Throws [CatalogSchemaException] when neither `path` nor `resolverName` is
/// present.
ThemeBindingPath themeBindingFromJson(Map<String, dynamic> j, String path) {
  final p = j['path'] as String?;
  final r = j['resolverName'] as String?;
  if (p == null && r == null) {
    throw CatalogSchemaException(
      '$path: theme binding must carry at least one of path / resolverName',
    );
  }
  if (p != null && r != null) {
    return ThemeBindingPath.both(path: p, resolverName: r);
  }
  return p != null ? ThemeBindingPath.path(p) : ThemeBindingPath.resolver(r!);
}

/// Encode a [WireIdRef] as a JSON object.
Map<String, dynamic> wireIdRefToJson(WireIdRef ref) => {
      'library': ref.library,
      'wireId': ref.wireId.value,
    };

/// Decode a [WireIdRef] from a JSON object, optionally enforcing
/// [expectedKind] on the embedded wire ID.
WireIdRef wireIdRefFromJson(
  Map<String, dynamic> j,
  String path, {
  WireIdKind? expectedKind,
}) {
  if (j['library'] is! String) {
    throw CatalogSchemaException(
      '$path: wire ID reference missing required string field: library',
    );
  }
  return WireIdRef(
    library: j['library'] as String,
    wireId: wireIdFromJson(j, 'wireId', path, expectedKind),
  );
}

/// Read a wire ID string under [field] of [j] and parse it, optionally
/// enforcing [expectedKind].
WireId wireIdFromJson(
  Map<String, dynamic> j,
  String field,
  String path,
  WireIdKind? expectedKind,
) {
  final value = j[field];
  if (value is! String) {
    throw CatalogSchemaException(
      '$path: missing required wire ID string field: $field',
    );
  }
  return wireIdFromString(value, '$path.$field', expectedKind);
}

/// Parse [value] as a wire ID, optionally enforcing [expectedKind].
WireId wireIdFromString(
  Object? value,
  String path,
  WireIdKind? expectedKind,
) {
  if (value is! String) {
    throw CatalogSchemaException(
      '$path: expected wire ID string; got ${value.runtimeType}',
    );
  }
  try {
    final id = WireId(value);
    if (expectedKind != null && id.kind != expectedKind) {
      throw CatalogSchemaException(
        '$path: expected ${expectedKind.name} wire ID '
        '(${expectedKind.prefix}*), got ${id.value}',
      );
    }
    return id;
    // ArgumentError carries the malformed-wire-ID detail we want to
    // surface through CatalogSchemaException's contract; the decoder
    // is a stable layer between untrusted JSON input and SDK consumers.
    // ignore: avoid_catching_errors
  } on ArgumentError catch (e) {
    throw CatalogSchemaException(
      '$path: invalid wire ID: ${e.message}',
    );
  }
}
