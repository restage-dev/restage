import 'dart:convert';

import 'package:rfw_catalog_schema/src/constraint_keywords.dart';
import 'package:rfw_catalog_schema/src/restage_constraints.dart';

/// Returns the first target-neutral value-contract issue in [constraints].
///
/// The returned `pathSuffix` is relative to a consumer-owned property or
/// constraints path. Consumers retain their own target vocabulary and error
/// type by combining that suffix with `message`.
({String pathSuffix, String message})? validateRestageConstraintValues(
  RestageConstraints constraints,
) {
  if (constraints.minimum != null && constraints.exclusiveMinimum != null) {
    return (
      pathSuffix: '',
      message: 'minimum and exclusiveMinimum are mutually exclusive',
    );
  }
  if (constraints.maximum != null && constraints.exclusiveMaximum != null) {
    return (
      pathSuffix: '',
      message: 'maximum and exclusiveMaximum are mutually exclusive',
    );
  }

  for (final entry in <String, num?>{
    'minimum': constraints.minimum,
    'exclusiveMinimum': constraints.exclusiveMinimum,
    'maximum': constraints.maximum,
    'exclusiveMaximum': constraints.exclusiveMaximum,
  }.entries) {
    final value = entry.value;
    if (value != null && !value.isFinite) {
      return (pathSuffix: '.${entry.key}', message: 'must be finite');
    }
  }

  final lower = constraints.minimum ?? constraints.exclusiveMinimum;
  final upper = constraints.maximum ?? constraints.exclusiveMaximum;
  if (lower != null && upper != null) {
    final equalWithExclusive = lower == upper &&
        (constraints.exclusiveMinimum != null ||
            constraints.exclusiveMaximum != null);
    if (lower > upper || equalWithExclusive) {
      return (
        pathSuffix: '',
        message: 'contradictory numeric lower and upper bounds',
      );
    }
  }

  final allowedValues = constraints.allowedValues;
  if (allowedValues != null) {
    if (allowedValues.isEmpty) {
      return (pathSuffix: '.allowedValues', message: 'must not be empty');
    }
    for (var index = 0; index < allowedValues.length; index++) {
      final value = allowedValues[index];
      final suffix = '.allowedValues[$index]';
      if (value is! String &&
          value is! num &&
          value is! bool &&
          value != null) {
        return (
          pathSuffix: suffix,
          message: 'must be a JSON scalar; got ${value.runtimeType}',
        );
      }
      if (value is num && !value.isFinite) {
        return (
          pathSuffix: suffix,
          message: 'numeric values must be finite',
        );
      }
      for (var previous = 0; previous < index; previous++) {
        if (allowedValues[previous] == value) {
          return (pathSuffix: suffix, message: 'duplicate value $value');
        }
      }
    }
  }

  final lengthIssue = _nonNegativePairIssue(
    constraints.minLength,
    constraints.maxLength,
    minimumName: 'minLength',
    maximumName: 'maxLength',
  );
  if (lengthIssue != null) return lengthIssue;
  final itemIssue = _nonNegativePairIssue(
    constraints.minItems,
    constraints.maxItems,
    minimumName: 'minItems',
    maximumName: 'maxItems',
  );
  if (itemIssue != null) return itemIssue;

  for (final entry in constraints.extensions.entries) {
    final suffix = '.extensions[${jsonEncode(entry.key)}]';
    if (restageConstraintWireKeywords.contains(entry.key)) {
      return (
        pathSuffix: suffix,
        message: 'collides with a known keyword',
      );
    }
    final issue = _jsonSafeValueIssue(entry.value, suffix);
    if (issue != null) return issue;
  }
  return null;
}

({String pathSuffix, String message})? _nonNegativePairIssue(
  int? minimum,
  int? maximum, {
  required String minimumName,
  required String maximumName,
}) {
  if (minimum != null && minimum < 0) {
    return (pathSuffix: '.$minimumName', message: 'must be non-negative');
  }
  if (maximum != null && maximum < 0) {
    return (pathSuffix: '.$maximumName', message: 'must be non-negative');
  }
  if (minimum != null && maximum != null && minimum > maximum) {
    return (
      pathSuffix: '',
      message: '$minimumName must not exceed $maximumName',
    );
  }
  return null;
}

({String pathSuffix, String message})? _jsonSafeValueIssue(
  Object? value,
  String pathSuffix,
) {
  if (value == null || value is String || value is bool) return null;
  if (value is num) {
    return value.isFinite
        ? null
        : (pathSuffix: pathSuffix, message: 'numeric values must be finite');
  }
  if (value is List) {
    for (var index = 0; index < value.length; index++) {
      final issue = _jsonSafeValueIssue(value[index], '$pathSuffix[$index]');
      if (issue != null) return issue;
    }
    return null;
  }
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key is! String) {
        return (
          pathSuffix: pathSuffix,
          message: 'JSON objects require string keys',
        );
      }
      final issue = _jsonSafeValueIssue(
        entry.value,
        '$pathSuffix[${jsonEncode(entry.key)}]',
      );
      if (issue != null) return issue;
    }
    return null;
  }
  return (
    pathSuffix: pathSuffix,
    message: 'value of type ${value.runtimeType} is not JSON-safe',
  );
}
