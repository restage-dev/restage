import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/widget_constructor_facts.dart';

const _a2uiConfigOrigin =
    'package:rfw_catalog_schema/src/annotations/a2ui_config.dart';

/// Resolved A2UI configuration for one customer widget class.
@immutable
final class A2uiTargetConfigFacts {
  /// Creates resolved A2UI facts.
  A2uiTargetConfigFacts({
    required this.usage,
    required Map<String, String> writeBackValues,
    required List<Issue> issues,
  })  : writeBackValues = Map.unmodifiable(writeBackValues),
        issues = List.unmodifiable(issues);

  /// Producer-facing usage guidance, or `null` when absent.
  final String? usage;

  /// Callback property name to value property name pairings.
  final Map<String, String> writeBackValues;

  /// Configuration diagnostics.
  final List<Issue> issues;
}

/// Selects the explicit consumer set for A2UI configuration facts.
enum A2uiTargetConfigConsumer {
  /// Reads every A2UI key for the A2UI backend.
  a2ui,

  /// Reads only human-facing `usage` for Widgetbook's metadata mirror.
  widgetbookMetadata,
}

/// Resolves A2UI configuration.
A2uiTargetConfigFacts readA2uiTargetConfig(
  ClassElement cls,
  AssetId assetId, {
  Iterable<WidgetConstructorInput>? constructorInputs,
  A2uiTargetConfigConsumer consumer = A2uiTargetConfigConsumer.a2ui,
}) {
  final issues = <Issue>[];
  final owner = cls.name ?? '<unnamed>';
  final baseLocation = '${assetId.path}#$owner';
  _Sourced<String>? usage;
  final pairings = <String, _Sourced<String>>{};
  final readsWriteBackConfig = consumer == A2uiTargetConfigConsumer.a2ui;

  var configIndex = 0;
  for (final annotation in cls.metadata.annotations) {
    if (!_isConfig(annotation, _a2uiConfigOrigin)) continue;
    final location = '$baseLocation@a2ui.Config[$configIndex]';
    configIndex++;
    final value = annotation.computeConstantValue();
    if (value == null) {
      issues.add(_evaluationIssue('a2ui.Config', location));
      continue;
    }
    final writeBackValue = value.getField('writeBackValue');
    if (readsWriteBackConfig &&
        writeBackValue != null &&
        !writeBackValue.isNull) {
      issues.add(
        Issue(
          code: IssueCode.invalidTargetConfigPlacement,
          message: 'a2ui.Config.writeBackValue is legal only on a callback '
              'field.',
          location: location,
        ),
      );
    }
    final candidateUsage = value.getField('usage')?.toStringValue();
    if (candidateUsage != null) {
      usage = _mergeValue(
        key: 'usage',
        current: usage,
        next: _Sourced(candidateUsage, location),
        equals: (left, right) => left == right,
        issues: issues,
      );
    }
    final map = value.getField('writeBackValues')?.toMapValue();
    if (readsWriteBackConfig && map != null) {
      for (final entry in map.entries) {
        final callback = entry.key?.toStringValue();
        final target = entry.value?.toStringValue();
        if (callback == null || target == null) {
          issues.add(
            Issue(
              code: IssueCode.missingAnnotationField,
              message: 'a2ui.Config.writeBackValues must contain only '
                  'compile-time String keys and values.',
              location: location,
            ),
          );
          continue;
        }
        _mergePairing(pairings, callback, target, location, issues);
      }
    }
  }

  if (readsWriteBackConfig) {
    final configFields = <FieldElement>{...cls.fields}..addAll(
        constructorInputs?.map((input) => input.field) ??
            const <FieldElement>[],
      );
    for (final field in configFields) {
      final fieldName = field.name ?? '<unnamed>';
      final fieldLocation = '$baseLocation.$fieldName';
      var fieldConfigIndex = 0;
      for (final annotation in field.metadata.annotations) {
        if (!_isConfig(annotation, _a2uiConfigOrigin)) continue;
        final location = '$fieldLocation@a2ui.Config[$fieldConfigIndex]';
        fieldConfigIndex++;
        final value = annotation.computeConstantValue();
        if (value == null) {
          issues.add(_evaluationIssue('a2ui.Config', location));
          continue;
        }
        if (_hasClassOnlyA2uiKey(value)) {
          issues.add(
            Issue(
              code: IssueCode.invalidTargetConfigPlacement,
              message: 'a2ui.Config usage and writeBackValues are legal only '
                  'on a widget class.',
              location: location,
            ),
          );
        }
        final target = value.getField('writeBackValue')?.toStringValue();
        if (target != null) {
          _mergePairing(pairings, fieldName, target, location, issues);
        }
      }
    }

    if (constructorInputs != null) {
      _validateA2uiPairings(pairings, constructorInputs, owner, issues);
    }
  }

  final trimmedUsage = usage?.value.trim();
  return A2uiTargetConfigFacts(
    usage: trimmedUsage == null || trimmedUsage.isEmpty ? null : trimmedUsage,
    writeBackValues: {
      for (final entry in pairings.entries) entry.key: entry.value.value,
    },
    issues: issues,
  );
}

void _validateA2uiPairings(
  Map<String, _Sourced<String>> pairings,
  Iterable<WidgetConstructorInput> constructorInputs,
  String owner,
  List<Issue> issues,
) {
  final inputsByName = {
    for (final input in constructorInputs) input.name: input,
  };
  for (final entry in pairings.entries) {
    final callback = inputsByName[entry.key];
    final target = inputsByName[entry.value.value];
    if (callback == null) {
      issues.add(
        Issue(
          code: IssueCode.invalidTargetConfigReference,
          message: 'A2UI write-back callback "${entry.key}" is not an input '
              'of the unnamed generative constructor on $owner.',
          location: entry.value.location,
        ),
      );
    } else if (callback.type is! FunctionType) {
      issues.add(
        Issue(
          code: IssueCode.invalidTargetConfigReference,
          message: 'A2UI write-back callback "${entry.key}" on $owner must '
              'resolve to a callback constructor input.',
          location: entry.value.location,
        ),
      );
    }
    if (target == null) {
      issues.add(
        Issue(
          code: IssueCode.invalidTargetConfigReference,
          message: 'A2UI write-back value "${entry.value.value}" is not an '
              'input of the unnamed generative constructor on $owner.',
          location: entry.value.location,
        ),
      );
    } else if (target.type is FunctionType) {
      issues.add(
        Issue(
          code: IssueCode.invalidTargetConfigReference,
          message: 'A2UI write-back value "${entry.value.value}" on $owner '
              'must resolve to a non-callback constructor input.',
          location: entry.value.location,
        ),
      );
    }
  }
}

bool _isConfig(ElementAnnotation annotation, String expectedOrigin) {
  final element = annotation.element;
  if (element is! ConstructorElement) return false;
  final owner = element.enclosingElement;
  return owner.name == 'Config' && owner.library.identifier == expectedOrigin;
}

bool _hasClassOnlyA2uiKey(DartObject value) {
  final usage = value.getField('usage');
  final writeBackValues = value.getField('writeBackValues');
  return (usage != null && !usage.isNull) ||
      (writeBackValues != null && !writeBackValues.isNull);
}

Issue _evaluationIssue(String annotation, String location) => Issue(
      code: IssueCode.missingAnnotationField,
      message: '$annotation could not be const-evaluated.',
      location: location,
    );

void _mergePairing(
  Map<String, _Sourced<String>> pairings,
  String callback,
  String target,
  String location,
  List<Issue> issues,
) {
  final current = pairings[callback];
  if (current == null) {
    pairings[callback] = _Sourced(target, location);
    return;
  }
  final duplicate = current.value == target;
  final message = duplicate
      ? 'Duplicate A2UI write-back pairing for "$callback" -> "$target" at '
          '${current.location} and $location.'
      : 'Conflicting A2UI write-back pairing for "$callback": '
          '"${current.value}" at ${current.location} and "$target" at '
          '$location.';
  final code = duplicate
      ? IssueCode.duplicateTargetConfig
      : IssueCode.conflictingTargetConfig;
  issues
    ..add(Issue(code: code, message: message, location: current.location))
    ..add(Issue(code: code, message: message, location: location));
}

_Sourced<T> _mergeValue<T>({
  required String key,
  required _Sourced<T>? current,
  required _Sourced<T> next,
  required bool Function(T left, T right) equals,
  required List<Issue> issues,
}) {
  if (current == null) return next;
  if (equals(current.value, next.value)) return current;
  final message = 'Conflicting target configuration for $key at '
      '${current.location} and ${next.location}.';
  issues
    ..add(
      Issue(
        code: IssueCode.conflictingTargetConfig,
        message: message,
        location: current.location,
      ),
    )
    ..add(
      Issue(
        code: IssueCode.conflictingTargetConfig,
        message: message,
        location: next.location,
      ),
    );
  return current;
}

@immutable
final class _Sourced<T> {
  const _Sourced(this.value, this.location);

  final T value;
  final String location;
}
