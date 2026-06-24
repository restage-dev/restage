// The task requires static parse/compute helpers as the public API.
// ignore_for_file: prefer_constructors_over_static_methods

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';

/// SHA-256 content hash for flow document artifacts.
@immutable
final class FlowContentHash {
  const FlowContentHash._(this.value);

  static final RegExp _sha256Pattern = RegExp(r'^sha256:[0-9a-f]{64}$');

  /// Wire value in `sha256:<64 lowercase hex chars>` format.
  final String value;

  /// Parses a canonical SHA-256 content hash.
  static FlowContentHash parse(String source) {
    if (!_sha256Pattern.hasMatch(source)) {
      throw FormatException(
        'Expected sha256:<64 lowercase hex chars> content hash.',
        source,
      );
    }
    return FlowContentHash._(source);
  }

  /// Computes a SHA-256 content hash over exact bytes.
  static FlowContentHash compute(List<int> bytes) {
    return FlowContentHash._('sha256:${crypto.sha256.convert(bytes)}');
  }

  /// Computes a SHA-256 content hash over UTF-8 text.
  static FlowContentHash computeString(String source) {
    return compute(utf8.encode(source));
  }

  /// Returns a diagnostic string for an artifact hash mismatch.
  String diagnosticForMismatch({
    required String path,
    required FlowContentHash actual,
  }) {
    return 'Artifact hash mismatch for $path: expected $value, '
        'actual ${actual.value}.';
  }

  @override
  bool operator ==(Object other) {
    return other is FlowContentHash && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
