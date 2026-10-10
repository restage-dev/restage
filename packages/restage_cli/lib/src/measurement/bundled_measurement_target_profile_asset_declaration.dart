import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_shared/restage_shared.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Raised when the fixed Measurement target-profile asset cannot be declared.
final class MeasurementBundledTargetProfileAssetDeclarationException
    implements Exception {
  /// Creates a safe asset-declaration failure.
  const MeasurementBundledTargetProfileAssetDeclarationException(this.message);

  /// Safe failure detail.
  final String message;

  @override
  String toString() =>
      'MeasurementBundledTargetProfileAssetDeclarationException: $message';
}

/// Whether the package's pubspec.yaml already ships the target profile.
Future<bool> isMeasurementBundledTargetProfileAssetDeclared({
  required Directory packageRoot,
}) async {
  final source = await _readPubspec(packageRoot);
  try {
    return _addFixedTargetProfileAsset(source) == source;
  } on Object {
    return false;
  }
}

/// Adds the target-profile asset to the package's pubspec.yaml, keeping its
/// comments and layout. Returns whether the file changed.
Future<bool> ensureMeasurementBundledTargetProfileAssetDeclaration({
  required Directory packageRoot,
}) async {
  final pubspec = File(p.join(packageRoot.path, 'pubspec.yaml'));
  final source = await _readPubspec(packageRoot);

  final String updated;
  try {
    updated = _addFixedTargetProfileAsset(source);
  } on Object {
    throw const MeasurementBundledTargetProfileAssetDeclarationException(
      'The package pubspec.yaml could not declare the Measurement target '
      'profile asset.',
    );
  }
  if (updated == source) return false;

  try {
    await pubspec.writeAsString(updated, flush: true);
  } on FileSystemException {
    throw const MeasurementBundledTargetProfileAssetDeclarationException(
      'The package pubspec.yaml could not write the Measurement target '
      'profile asset declaration.',
    );
  }
  return true;
}

Future<String> _readPubspec(Directory packageRoot) async {
  try {
    return await File(p.join(packageRoot.path, 'pubspec.yaml')).readAsString();
  } on FileSystemException {
    throw const MeasurementBundledTargetProfileAssetDeclarationException(
      'The package pubspec.yaml could not be read for the Measurement target '
      'profile asset.',
    );
  }
}

String _addFixedTargetProfileAsset(String source) {
  final editor = YamlEditor(source);
  final flutter = _valueAt(editor, const <String>['flutter']);
  if (flutter == null) {
    editor.update(
      <String>['flutter'],
      <String, Object?>{
        'assets': <String>[kMeasurementBundledTargetProfileAssetPath],
      },
    );
    return editor.toString();
  }
  if (flutter is! YamlMap && flutter is! Map) {
    throw const FormatException('flutter is not a mapping');
  }

  final assets = _valueAt(editor, const <String>['flutter', 'assets']);
  if (assets == null) {
    editor.update(
      <String>['flutter', 'assets'],
      <String>[kMeasurementBundledTargetProfileAssetPath],
    );
    return editor.toString();
  }
  if (assets is! YamlList && assets is! List) {
    throw const FormatException('flutter.assets is not a list');
  }

  final values = List<Object?>.of(assets as Iterable<Object?>);
  if (values.whereType<String>().any(_declaresFixedTargetProfileAsset)) {
    return source;
  }
  editor.appendToList(<String>[
    'flutter',
    'assets',
  ], kMeasurementBundledTargetProfileAssetPath);
  return editor.toString();
}

Object? _valueAt(YamlEditor editor, List<String> path) {
  try {
    return editor.parseAt(path).value;
  } on ArgumentError {
    return null;
  }
}

bool _declaresFixedTargetProfileAsset(String asset) =>
    asset == kMeasurementBundledTargetProfileAssetPath ||
    asset == 'assets/restage/measurement/';
