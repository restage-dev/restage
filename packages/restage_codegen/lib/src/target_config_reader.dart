import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/enum_constant_identity.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/widget_constructor_facts.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' show StoryExpansion;

const _a2uiConfigOrigin =
    'package:rfw_catalog_schema/src/annotations/a2ui_config.dart';
const _widgetbookConfigOrigin =
    'package:rfw_catalog_schema/src/annotations/widgetbook_config.dart';

/// Resolved finite-state configuration for one Widgetbook property.
@immutable
final class WidgetbookPropertyTargetConfigFacts {
  /// Creates resolved property configuration.
  WidgetbookPropertyTargetConfigFacts({
    required List<DartObject>? storyValues,
    required this.allValues,
    required this.storyValuesLocation,
    required this.allValuesLocation,
  }) : storyValues = storyValues == null
            ? null
            : List<DartObject>.unmodifiable(storyValues);

  /// Authored values in declaration order, or `null` when absent.
  final List<DartObject>? storyValues;

  /// Whether every finite value of this property was requested.
  final bool allValues;

  /// Source path for [storyValues], when present.
  final String? storyValuesLocation;

  /// Source path for [allValues], when present.
  final String? allValuesLocation;
}

/// Resolved Widgetbook configuration for one customer widget class.
@immutable
final class WidgetbookTargetConfigFacts {
  /// Creates resolved Widgetbook facts.
  WidgetbookTargetConfigFacts({
    required this.expansion,
    required this.maxStories,
    required Map<String, WidgetbookPropertyTargetConfigFacts> properties,
    required List<Issue> issues,
  })  : properties = Map.unmodifiable(properties),
        issues = List.unmodifiable(issues);

  /// Explicit expansion policy, or `null` for the default policy.
  final StoryExpansion? expansion;

  /// Explicit per-widget story limit, or `null` for the package default.
  final int? maxStories;

  /// Configured properties keyed by exact admitted constructor-input name.
  final Map<String, WidgetbookPropertyTargetConfigFacts> properties;

  /// Configuration diagnostics.
  final List<Issue> issues;
}

/// Resolves Widgetbook configuration by exact annotation constructor identity.
WidgetbookTargetConfigFacts readWidgetbookTargetConfig(
  ClassElement cls,
  AssetId assetId, {
  Iterable<WidgetConstructorInput>? constructorInputs,
}) {
  final issues = <Issue>[];
  final owner = cls.name ?? '<unnamed>';
  final baseLocation = '${assetId.path}#$owner';
  _Sourced<StoryExpansion>? expansion;
  _Sourced<int>? maxStories;
  final properties = <String, _MutableWidgetbookPropertyConfig>{};
  final inspectedFormals = Set<FormalParameterElement>.identity();

  var configIndex = 0;
  for (final annotation in cls.metadata.annotations) {
    if (!_isConfig(annotation, _widgetbookConfigOrigin)) continue;
    final location = '$baseLocation@wb.Config[$configIndex]';
    configIndex++;
    final value = annotation.computeConstantValue();
    if (value == null) {
      issues.add(_evaluationIssue('wb.Config', location));
      continue;
    }
    if (_hasFieldOnlyWidgetbookKey(value)) {
      issues.add(
        Issue(
          code: IssueCode.invalidTargetConfigPlacement,
          message: 'wb.Config storyValues and allValues are legal only on a '
              'constructor property field.',
          location: location,
        ),
      );
    }
    final expansionValue = value.getField('expansion');
    if (expansionValue != null && !expansionValue.isNull) {
      final parsed = _readStoryExpansion(expansionValue, location, issues);
      if (parsed != null) {
        expansion = _mergeValue(
          key: 'expansion',
          current: expansion,
          next: _Sourced(parsed, location),
          equals: (left, right) => left == right,
          issues: issues,
        );
      }
    }
    final maxStoriesValue = value.getField('maxStories');
    if (maxStoriesValue != null && !maxStoriesValue.isNull) {
      final parsed = maxStoriesValue.toIntValue();
      if (parsed == null) {
        issues.add(
          Issue(
            code: IssueCode.missingAnnotationField,
            message: 'wb.Config maxStories must be a compile-time int.',
            location: location,
          ),
        );
      } else {
        maxStories = _mergeValue(
          key: 'maxStories',
          current: maxStories,
          next: _Sourced(parsed, location),
          equals: (left, right) => left == right,
          issues: issues,
        );
      }
    }
  }

  for (final constructor in cls.constructors) {
    for (final formal in constructor.formalParameters) {
      for (final declaration in widgetConstructorFormalChain(formal)) {
        _rejectWidgetbookFormalConfig(
          declaration,
          assetId,
          inspectedFormals,
          issues,
        );
      }
    }
  }

  final hasConstructorFacts = constructorInputs != null;
  final inputs = constructorInputs?.toList(growable: false) ??
      const <WidgetConstructorInput>[];
  for (final input in inputs) {
    for (final formal in input.formalChain) {
      _rejectWidgetbookFormalConfig(
        formal,
        assetId,
        inspectedFormals,
        issues,
      );
    }
  }
  final configFields = <FieldElement>{...cls.fields};
  for (final supertype in cls.thisType.allSupertypes) {
    configFields.addAll(supertype.element.fields);
  }
  configFields.addAll(inputs.map((input) => input.field));
  for (final field in configFields) {
    final fieldName = field.name ?? '<unnamed>';
    final fieldOwner = field.enclosingElement;
    final ownerName = fieldOwner is ClassElement
        ? fieldOwner.name ?? '<unnamed>'
        : '<unnamed>';
    var fieldConfigIndex = 0;
    for (final annotation in field.metadata.annotations) {
      if (!_isConfig(annotation, _widgetbookConfigOrigin)) continue;
      final location = '${_annotationSourcePath(annotation, assetId)}#'
          '$ownerName.$fieldName@wb.Config[$fieldConfigIndex]';
      fieldConfigIndex++;
      final input = _exactInputForField(field, inputs);
      if (!hasConstructorFacts || input == null) {
        issues.add(
          Issue(
            code: IssueCode.invalidTargetConfigPlacement,
            message: !hasConstructorFacts
                ? 'wb.Config on $ownerName.$fieldName cannot be validated '
                    'because constructor facts are unavailable. Property '
                    'configuration is legal only on the exact backing field '
                    'of an admitted unnamed-constructor input.'
                : 'wb.Config on $ownerName.$fieldName is not on the exact '
                    'backing field of an admitted unnamed-constructor input. '
                    'Property configuration cannot admit a field by name.',
            location: location,
          ),
        );
        continue;
      }
      final value = annotation.computeConstantValue();
      if (value == null) {
        issues.add(_evaluationIssue('wb.Config', location));
        continue;
      }
      if (_hasClassOnlyWidgetbookKey(value)) {
        issues.add(
          Issue(
            code: IssueCode.invalidTargetConfigPlacement,
            message: 'wb.Config expansion and maxStories are legal only on '
                'a widget class.',
            location: location,
          ),
        );
      }
      final property = properties.putIfAbsent(
        input.name,
        _MutableWidgetbookPropertyConfig.new,
      );
      final values = value.getField('storyValues')?.toListValue();
      if (values != null) {
        property.mergeStoryValues(
          _canonicalStoryValues(values, input),
          location,
          issues,
        );
      }
      if (value.getField('allValues')?.toBoolValue() ?? false) {
        property.mergeAllValues(location, issues);
      }
    }
  }

  return WidgetbookTargetConfigFacts(
    expansion: expansion?.value,
    maxStories: maxStories?.value,
    properties: {
      for (final entry in properties.entries)
        if (entry.value.hasConfiguration) entry.key: entry.value.freeze(),
    },
    issues: issues,
  );
}

void _rejectWidgetbookFormalConfig(
  FormalParameterElement formal,
  AssetId contextAsset,
  Set<FormalParameterElement> inspected,
  List<Issue> issues,
) {
  final declaration = formal.baseElement;
  if (!inspected.add(declaration)) return;
  final constructor = declaration.enclosingElement;
  if (constructor is! ConstructorElement) {
    throw StateError(
      'Could not resolve the constructor that defines formal '
      "'${declaration.name ?? '<unnamed>'}'.",
    );
  }
  final owner = constructor.enclosingElement;
  if (owner is! ClassElement) {
    throw StateError(
      'Could not resolve the class that defines constructor formal '
      "'${declaration.name ?? '<unnamed>'}'.",
    );
  }
  final selector = switch (constructor.name) {
    null || '' || 'new' => 'new',
    final name => name,
  };
  final formalName = declaration.name ?? '<unnamed>';
  var configIndex = 0;
  for (final annotation in declaration.metadata.annotations) {
    if (!_isConfig(annotation, _widgetbookConfigOrigin)) continue;
    final location = '${_annotationSourcePath(annotation, contextAsset)}#'
        '${owner.name ?? '<unnamed>'}.$selector.$formalName'
        '@wb.Config[$configIndex]';
    configIndex++;
    issues.add(
      Issue(
        code: IssueCode.invalidTargetConfigPlacement,
        message: 'wb.Config is not legal on a constructor formal. Put '
            'expansion or maxStories on the widget class, and put '
            'storyValues or allValues on the exact admitted backing field.',
        location: location,
      ),
    );
  }
}

WidgetConstructorInput? _exactInputForField(
  FieldElement field,
  List<WidgetConstructorInput> inputs,
) {
  WidgetConstructorInput? result;
  for (final input in inputs) {
    if (!identical(input.field, field)) continue;
    if (result != null) {
      throw StateError(
        "Field '${field.name ?? '<unnamed>'}' backs more than one admitted "
        'constructor input.',
      );
    }
    result = input;
  }
  return result;
}

String _annotationSourcePath(
  ElementAnnotation annotation,
  AssetId contextAsset,
) {
  final source = annotation.libraryFragment.source;
  final uri = source.uri;
  if (uri.scheme == 'package' || uri.scheme == 'asset') {
    final asset = AssetId.resolve(uri);
    return asset.package == contextAsset.package ? asset.path : uri.toString();
  }
  if (uri.scheme == 'file') return source.fullName;
  if (uri.hasScheme) return uri.toString();
  throw StateError(
    'Could not resolve an absolute defining source for wb.Config.',
  );
}

bool _hasClassOnlyWidgetbookKey(DartObject value) {
  final expansion = value.getField('expansion');
  final maxStories = value.getField('maxStories');
  return expansion != null && !expansion.isNull ||
      maxStories != null && !maxStories.isNull;
}

bool _hasFieldOnlyWidgetbookKey(DartObject value) {
  final storyValues = value.getField('storyValues');
  return storyValues != null && !storyValues.isNull ||
      (value.getField('allValues')?.toBoolValue() ?? false);
}

StoryExpansion? _readStoryExpansion(
  DartObject value,
  String location,
  List<Issue> issues,
) {
  final type = value.type;
  final enumElement = type is InterfaceType ? type.element : null;
  final isExpectedIdentity = enumElement is EnumElement &&
      enumElement.name == 'StoryExpansion' &&
      enumElement.library.identifier == _widgetbookConfigOrigin;
  final canonical = isExpectedIdentity
      ? canonicalAnalyzerEnumConstant(value, enumElement)
      : null;
  if (canonical == null) {
    issues.add(
      Issue(
        code: IssueCode.unknownEnumValue,
        message: 'wb.Config expansion must resolve to StoryExpansion from '
            'package:rfw_catalog_schema/widgetbook.dart.',
        location: location,
      ),
    );
    return null;
  }
  return switch (canonical.identity.member) {
    'independent' => StoryExpansion.independent,
    'cartesian' => StoryExpansion.cartesian,
    _ => null,
  };
}

List<DartObject> _canonicalStoryValues(
  List<DartObject> values,
  WidgetConstructorInput input,
) {
  final type = input.type;
  final expected = type is InterfaceType ? type.element : null;
  if (expected is! EnumElement) return values;
  return [
    for (final value in values)
      canonicalAnalyzerEnumConstant(value, expected)?.value ?? value,
  ];
}

final class _MutableWidgetbookPropertyConfig {
  _Sourced<List<DartObject>>? _storyValues;
  _Sourced<bool>? _allValues;

  bool get hasConfiguration => _storyValues != null || _allValues != null;

  void mergeStoryValues(
    List<DartObject> values,
    String location,
    List<Issue> issues,
  ) {
    final next = _Sourced(List<DartObject>.unmodifiable(values), location);
    final current = _storyValues;
    if (current == null) {
      _storyValues = next;
    } else {
      _storyValues = _mergeValue(
        key: 'storyValues',
        current: current,
        next: next,
        equals: _sameDartObjectList,
        issues: issues,
      );
    }
    _reportMutuallyExclusive(issues);
  }

  void mergeAllValues(String location, List<Issue> issues) {
    _allValues ??= _Sourced(true, location);
    _reportMutuallyExclusive(issues);
  }

  void _reportMutuallyExclusive(List<Issue> issues) {
    final storyValues = _storyValues;
    final allValues = _allValues;
    if (storyValues == null || allValues == null) return;
    final message = 'wb.Config storyValues and allValues are mutually '
        'exclusive at ${storyValues.location} and ${allValues.location}.';
    if (issues.any(
      (issue) =>
          issue.code == IssueCode.conflictingTargetConfig &&
          issue.message == message,
    )) {
      return;
    }
    issues
      ..add(
        Issue(
          code: IssueCode.conflictingTargetConfig,
          message: message,
          location: storyValues.location,
        ),
      )
      ..add(
        Issue(
          code: IssueCode.conflictingTargetConfig,
          message: message,
          location: allValues.location,
        ),
      );
  }

  WidgetbookPropertyTargetConfigFacts freeze() =>
      WidgetbookPropertyTargetConfigFacts(
        storyValues: _storyValues?.value,
        allValues: _allValues?.value ?? false,
        storyValuesLocation: _storyValues?.location,
        allValuesLocation: _allValues?.location,
      );
}

bool _sameDartObjectList(List<DartObject> left, List<DartObject> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

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
    if (!readsWriteBackConfig && !_writesA2uiUsage(annotation)) continue;
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

bool _writesA2uiUsage(ElementAnnotation annotation) {
  final element = annotation.element;
  if (element is! ConstructorElement) return false;
  if (element.name == 'usage') return true;
  if (element.name != null &&
      element.name!.isNotEmpty &&
      element.name != 'new') {
    return false;
  }

  // The annotation is already locked to the genuine A2UI Config declaration.
  // Inspect its argument labels before const evaluation so an A2UI-only key
  // that cannot evaluate cannot become a Widgetbook failure. An aggregate
  // that explicitly carries `usage` remains one Widgetbook-consumed unit.
  final parsed = parseString(
    content: '${annotation.toSource()} class _UsageProbe {}',
    throwIfDiagnostics: false,
  ).unit;
  final declaration = parsed.declarations.whereType<ClassDeclaration>().first;
  final arguments = declaration.metadata.single.arguments?.arguments;
  return arguments?.whereType<NamedExpression>().any(
            (argument) => argument.name.label.name == 'usage',
          ) ??
      false;
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
