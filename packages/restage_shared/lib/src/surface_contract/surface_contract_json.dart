// The compact canonical writer keeps several short clauses on one line.
// ignore_for_file: require_trailing_commas

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';
import 'package:restage_shared/src/capability/capability_manifest.dart';

/// Internal strict JSON and canonicalization helpers shared by surface
/// publication contracts.
@internal
abstract final class SurfaceContractJson {
  static final RegExp sha256Pattern = RegExp(r'^sha256:[0-9a-f]{64}$');

  static Object? decode(String source, {required String label}) {
    try {
      return jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('Invalid $label JSON: ${error.message}');
    }
  }

  static String encode(Object? value) {
    final output = StringBuffer();
    _write(value, output);
    return output.toString();
  }

  static Uint8List utf8Bytes(Object? value) => Uint8List.fromList(
        utf8.encode(encode(value)),
      );

  static Map<String, Object?> requireObject(Object? value, String path) {
    if (value is! Map) {
      throw FormatException('Expected "$path" to be an object.');
    }
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw FormatException('Expected "$path" keys to be strings.');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  static List<Object?> requireList(Object? value, String path) {
    if (value is! List) {
      throw FormatException('Expected "$path" to be an array.');
    }
    return List<Object?>.of(value);
  }

  static void exactKeys(
    Map<String, Object?> json,
    Set<String> expected,
    String path,
  ) {
    for (final key in json.keys) {
      if (!expected.contains(key)) {
        throw FormatException('Unsupported field "$path.$key".');
      }
    }
    for (final key in expected) {
      if (!json.containsKey(key)) {
        throw FormatException('Missing required field "$path.$key".');
      }
    }
  }

  static void allowedKeys(
    Map<String, Object?> json,
    Set<String> allowed,
    String path,
  ) {
    for (final key in json.keys) {
      if (!allowed.contains(key)) {
        throw FormatException('Unsupported field "$path.$key".');
      }
    }
  }

  static Object? requiredValue(
    Map<String, Object?> json,
    String key,
    String path,
  ) {
    if (!json.containsKey(key)) {
      throw FormatException('Missing required field "$path.$key".');
    }
    final value = json[key];
    if (value == null) {
      throw FormatException('Field "$path.$key" cannot be null.');
    }
    return value;
  }

  static String requiredString(
    Map<String, Object?> json,
    String key,
    String path,
  ) {
    final value = requiredValue(json, key, path);
    if (value is! String) {
      throw FormatException('Expected "$path.$key" to be a string.');
    }
    return value;
  }

  static int requiredInt(
    Map<String, Object?> json,
    String key,
    String path,
  ) {
    final value = requiredValue(json, key, path);
    if (value is! int) {
      throw FormatException('Expected "$path.$key" to be an integer.');
    }
    return value;
  }

  static int requiredPositiveInt(
    Map<String, Object?> json,
    String key,
    String path,
  ) {
    final value = requiredInt(json, key, path);
    if (value < 1) {
      throw FormatException('Expected "$path.$key" to be positive.');
    }
    return value;
  }

  static String requireSha256(String value, String path) {
    if (!sha256Pattern.hasMatch(value)) {
      throw FormatException(
          'Expected "$path" to be sha256:<64 lowercase hex>.');
    }
    return value;
  }

  static void requireUnicodeScalars(String value, String path) {
    for (var index = 0; index < value.length; index += 1) {
      final unit = value.codeUnitAt(index);
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        if (index + 1 >= value.length) {
          throw FormatException('Unpaired UTF-16 surrogate in "$path".');
        }
        final next = value.codeUnitAt(index + 1);
        if (next < 0xDC00 || next > 0xDFFF) {
          throw FormatException('Unpaired UTF-16 surrogate in "$path".');
        }
        index += 1;
      } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
        throw FormatException('Unpaired UTF-16 surrogate in "$path".');
      }
    }
  }

  static int compareUtf8(String left, String right) {
    requireUnicodeScalars(left, 'left');
    requireUnicodeScalars(right, 'right');
    final leftBytes = utf8.encode(left);
    final rightBytes = utf8.encode(right);
    final length = leftBytes.length < rightBytes.length
        ? leftBytes.length
        : rightBytes.length;
    for (var index = 0; index < length; index += 1) {
      final comparison = leftBytes[index].compareTo(rightBytes[index]);
      if (comparison != 0) return comparison;
    }
    return leftBytes.length.compareTo(rightBytes.length);
  }

  static List<LibraryRequirement> canonicalRequirements(
    List<LibraryRequirement> requirements, {
    required String path,
  }) {
    final seen = <String>{};
    final canonical = List<LibraryRequirement>.of(requirements);
    for (final requirement in canonical) {
      if (requirement.namespace.isEmpty) {
        throw FormatException('Library namespace at "$path" cannot be empty.');
      }
      requireUnicodeScalars(requirement.namespace, '$path.namespace');
      if (requirement.minVersion < 1) {
        throw FormatException(
            'Library minVersion at "$path" must be positive.');
      }
      if (!seen.add(requirement.namespace)) {
        throw FormatException(
          'Duplicate library namespace "${requirement.namespace}".',
        );
      }
    }
    canonical
        .sort((left, right) => compareUtf8(left.namespace, right.namespace));
    return List<LibraryRequirement>.unmodifiable(canonical);
  }

  static CapabilityManifest decodeCapabilityManifest(
    Object? value, {
    required String path,
  }) {
    final json = requireObject(value, path);
    exactKeys(json, const {'builtInFloor', 'requiredLibraries'}, path);
    final builtInFloor = requiredPositiveInt(json, 'builtInFloor', path);
    final rawRequirements = requireList(
      requiredValue(json, 'requiredLibraries', path),
      '$path.requiredLibraries',
    );
    final requirements = <LibraryRequirement>[];
    for (var index = 0; index < rawRequirements.length; index += 1) {
      final requirementPath = '$path.requiredLibraries[$index]';
      final requirement =
          requireObject(rawRequirements[index], requirementPath);
      exactKeys(
          requirement, const {'namespace', 'minVersion'}, requirementPath);
      final namespace =
          requiredString(requirement, 'namespace', requirementPath);
      final minVersion = requiredPositiveInt(
        requirement,
        'minVersion',
        requirementPath,
      );
      requirements.add(
        LibraryRequirement(namespace: namespace, minVersion: minVersion),
      );
    }
    final canonical = canonicalRequirements(requirements, path: path);
    return CapabilityManifest(
      builtInFloor: builtInFloor,
      requiredLibraries: canonical,
    );
  }

  static Map<String, Object?> encodeCapabilityManifest(
    CapabilityManifest manifest, {
    required String path,
  }) {
    if (manifest.builtInFloor < 1) {
      throw FormatException('Library floor at "$path" must be positive.');
    }
    final requirements = canonicalRequirements(
      manifest.requiredLibraries,
      path: path,
    );
    return <String, Object?>{
      'builtInFloor': manifest.builtInFloor,
      'requiredLibraries': <Object?>[
        for (final requirement in requirements)
          <String, Object?>{
            'namespace': requirement.namespace,
            'minVersion': requirement.minVersion,
          },
      ],
    };
  }

  static bool requirementsEqual(
    CapabilityManifest left,
    CapabilityManifest right,
  ) {
    final leftRequirements = canonicalRequirements(
      left.requiredLibraries,
      path: 'left.requiredLibraries',
    );
    final rightRequirements = canonicalRequirements(
      right.requiredLibraries,
      path: 'right.requiredLibraries',
    );
    if (left.builtInFloor != right.builtInFloor ||
        leftRequirements.length != rightRequirements.length) {
      return false;
    }
    for (var index = 0; index < leftRequirements.length; index += 1) {
      if (leftRequirements[index] != rightRequirements[index]) return false;
    }
    return true;
  }

  static String hash(List<int> preimage) =>
      'sha256:${crypto.sha256.convert(preimage)}';

  static bool bytesEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  static String encodeBase64Url(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  static Uint8List decodeCanonicalBase64Url(String source, String path) {
    if (source.isEmpty) {
      throw FormatException(
          'Expected "$path" to be a non-empty base64url string.');
    }
    try {
      final decoded = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(source)),
      );
      if (encodeBase64Url(decoded) != source) {
        throw FormatException('Expected "$path" to be canonical base64url.');
      }
      return decoded;
    } on FormatException {
      rethrow;
    } on Object {
      throw FormatException('Expected "$path" to be canonical base64url.');
    }
  }

  static void _write(Object? value, StringBuffer output) {
    if (value == null) {
      output.write('null');
    } else if (value is String) {
      _writeString(value, output);
    } else if (value is bool || value is int) {
      output.write(value);
    } else if (value is List) {
      output.writeCharCode(0x5B);
      for (var index = 0; index < value.length; index += 1) {
        if (index != 0) output.writeCharCode(0x2C);
        _write(value[index], output);
      }
      output.writeCharCode(0x5D);
    } else if (value is Map) {
      output.writeCharCode(0x7B);
      var first = true;
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw const FormatException(
              'Canonical JSON object keys must be strings.');
        }
        if (!first) output.writeCharCode(0x2C);
        first = false;
        _writeString(entry.key as String, output);
        output.writeCharCode(0x3A);
        _write(entry.value, output);
      }
      output.writeCharCode(0x7D);
    } else {
      throw FormatException(
        'Unsupported canonical JSON value ${value.runtimeType}.',
      );
    }
  }

  static void _writeString(String value, StringBuffer output) {
    requireUnicodeScalars(value, 'JSON string');
    output.writeCharCode(0x22);
    for (var index = 0; index < value.length; index += 1) {
      final unit = value.codeUnitAt(index);
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        output.writeCharCode(unit);
        index += 1;
        output.writeCharCode(value.codeUnitAt(index));
      } else {
        switch (unit) {
          case 0x22:
            output.write(r'\"');
          case 0x5C:
            output.write(r'\\');
          case 0x08:
            output.write(r'\b');
          case 0x09:
            output.write(r'\t');
          case 0x0A:
            output.write(r'\n');
          case 0x0C:
            output.write(r'\f');
          case 0x0D:
            output.write(r'\r');
          default:
            if (unit <= 0x1F) {
              final hex = unit.toRadixString(16).padLeft(2, '0');
              output.write('\\u00$hex');
            } else {
              output.writeCharCode(unit);
            }
        }
      }
    }
    output.writeCharCode(0x22);
  }
}
