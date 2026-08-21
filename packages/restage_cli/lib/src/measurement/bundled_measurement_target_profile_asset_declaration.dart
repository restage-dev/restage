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

/// Ensures Flutter packages the one fixed Measurement target-profile asset.
///
/// The target itself remains only inside the backend-finalized profile bytes.
/// This writes no target value, configuration knob, or per-widget declaration:
/// it adds the fixed asset key only when the bundled-runtime publication path
/// has already produced that exact profile.
Future<void> ensureMeasurementBundledTargetProfileAssetDeclaration({
  required Directory packageRoot,
}) async {
  final pubspec = File(p.join(packageRoot.path, 'pubspec.yaml'));
  final String source;
  try {
    source = await pubspec.readAsString();
  } on FileSystemException {
    throw const MeasurementBundledTargetProfileAssetDeclarationException(
      'The package pubspec.yaml could not be read for the Measurement target '
      'profile asset.',
    );
  }

  final String updated;
  try {
    updated = _addFixedTargetProfileAsset(source);
  } on Object {
    throw const MeasurementBundledTargetProfileAssetDeclarationException(
      'The package pubspec.yaml could not declare the Measurement target '
      'profile asset.',
    );
  }
  if (updated == source) return;

  try {
    await pubspec.writeAsString(updated, flush: true);
  } on FileSystemException {
    throw const MeasurementBundledTargetProfileAssetDeclarationException(
      'The package pubspec.yaml could not write the Measurement target '
      'profile asset declaration.',
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
  values.add(kMeasurementBundledTargetProfileAssetPath);
  editor.update(<String>['flutter', 'assets'], values);
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
