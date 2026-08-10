import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/widget_constructor_facts.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart' show EmitTarget;

const _rfwConfigOrigin =
    'package:rfw_catalog_schema/src/annotations/rfw_config.dart';
const _a2uiConfigOrigin =
    'package:rfw_catalog_schema/src/annotations/a2ui_config.dart';
const _widgetbookConfigOrigin =
    'package:rfw_catalog_schema/src/annotations/widgetbook_config.dart';

/// Resolved class-level participation in one customer-widget emit target.
@immutable
final class WidgetTargetRoutingFacts {
  /// Creates resolved routing facts.
  WidgetTargetRoutingFacts({
    required this.enabled,
    required List<String> configuredLocations,
    required List<Issue> issues,
  })  : configuredLocations = List.unmodifiable(configuredLocations),
        issues = List.unmodifiable(issues);

  /// Whether the widget participates in this target.
  final bool enabled;

  /// Source locations that explicitly supplied the `enabled` key.
  final List<String> configuredLocations;

  /// Routing diagnostics.
  final List<Issue> issues;

  /// Whether all routing annotations were valid.
  bool get valid => issues.isEmpty;
}

/// Reads one target's class-level `Config.enabled` values by resolved identity.
WidgetTargetRoutingFacts readWidgetTargetRouting(
  ClassElement cls,
  AssetId assetId, {
  required EmitTarget target,
}) {
  final issues = <Issue>[];
  final owner = cls.name ?? '<unnamed>';
  final annotationName = _annotationName(target);
  final origin = _configOrigin(target);
  final configuredLocations = <String>[];
  ({bool value, String location})? resolved;

  var classConfigIndex = 0;
  for (final annotation in cls.metadata.annotations) {
    if (!_isConfig(annotation, origin)) continue;
    if (!_writesEnabled(annotation)) continue;
    final location = '${_annotationSourcePath(annotation, assetId)}#$owner'
        '@$annotationName.Config[$classConfigIndex]';
    classConfigIndex++;
    configuredLocations.add(location);
    final value = annotation.computeConstantValue();
    if (value == null) {
      issues.add(
        Issue(
          code: IssueCode.missingAnnotationField,
          message: '$annotationName.Config could not be const-evaluated.',
          location: location,
        ),
      );
      continue;
    }
    final enabledValue = value.getField('enabled');
    if (enabledValue == null || enabledValue.isNull) continue;
    final enabled = enabledValue.toBoolValue();
    if (enabled == null) {
      issues.add(
        Issue(
          code: IssueCode.missingAnnotationField,
          message: '$annotationName.Config enabled must be a compile-time '
              'bool.',
          location: location,
        ),
      );
      continue;
    }
    final current = resolved;
    if (current == null) {
      resolved = (value: enabled, location: location);
    } else if (current.value != enabled) {
      final message = 'Conflicting $annotationName.Config enabled values: '
          '${current.value} at ${current.location} and $enabled at $location.';
      if (!issues.any(
        (issue) =>
            issue.code == IssueCode.conflictingTargetConfig &&
            issue.location == current.location,
      )) {
        issues.add(
          Issue(
            code: IssueCode.conflictingTargetConfig,
            message: message,
            location: current.location,
          ),
        );
      }
      issues.add(
        Issue(
          code: IssueCode.conflictingTargetConfig,
          message: message,
          location: location,
        ),
      );
    }
  }

  final inspectedPlacements = Set<Element>.identity();
  void inspectPlacement(Element element, String member) {
    final declaration = element.baseElement;
    if (!inspectedPlacements.add(declaration)) return;
    _rejectEnabledPlacement(
      declaration,
      owner: owner,
      member: member,
      assetId: assetId,
      annotationName: annotationName,
      origin: origin,
      issues: issues,
    );
  }

  for (final field in cls.fields) {
    inspectPlacement(field, field.name ?? '<unnamed>');
  }
  for (final constructor in cls.constructors) {
    for (final formal in constructor.formalParameters) {
      final member = formal.name ?? '<unnamed>';
      inspectPlacement(formal, member);
      for (final inherited in widgetConstructorFormalChain(formal)) {
        inspectPlacement(inherited, member);
        if (inherited is FieldFormalParameterElement) {
          final field = inherited.field;
          if (field != null) inspectPlacement(field, member);
        }
      }
    }
  }

  return WidgetTargetRoutingFacts(
    enabled: resolved?.value ?? true,
    configuredLocations: configuredLocations,
    issues: issues,
  );
}

void _rejectEnabledPlacement(
  Element element, {
  required String owner,
  required String member,
  required AssetId assetId,
  required String annotationName,
  required String origin,
  required List<Issue> issues,
}) {
  var index = 0;
  for (final annotation in element.metadata.annotations) {
    if (!_isConfig(annotation, origin)) continue;
    if (!_writesEnabled(annotation)) continue;
    final location = '${_annotationSourcePath(annotation, assetId)}#'
        '$owner.$member@$annotationName.Config[$index]';
    index++;
    issues.add(
      Issue(
        code: IssueCode.invalidTargetConfigPlacement,
        message: '$annotationName.Config enabled is legal only on a '
            '@RestageWidget class.',
        location: location,
      ),
    );
  }
}

bool _isConfig(ElementAnnotation annotation, String origin) {
  final element = annotation.element;
  if (element is! ConstructorElement) return false;
  final owner = element.enclosingElement;
  return owner.name == 'Config' && owner.library.identifier == origin;
}

bool _writesEnabled(ElementAnnotation annotation) {
  final element = annotation.element;
  if (element is! ConstructorElement) return false;
  if (element.name == 'enabled') return true;
  if (element.name != null &&
      element.name!.isNotEmpty &&
      element.name != 'new') {
    return false;
  }

  // Recognition is already locked to the resolved Config declaration above.
  // Parse only that genuine annotation's argument labels so a malformed,
  // unrelated Config key cannot block a widget that an earlier annotation
  // disabled before target-config lowering.
  final parsed = parseString(
    content: '${annotation.toSource()} class _RoutingProbe {}',
    throwIfDiagnostics: false,
  ).unit;
  final declaration = parsed.declarations.whereType<ClassDeclaration>().first;
  final arguments = declaration.metadata.single.arguments?.arguments;
  return arguments?.whereType<NamedExpression>().any(
            (argument) => argument.name.label.name == 'enabled',
          ) ??
      false;
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
    'Could not resolve an absolute defining source for target routing.',
  );
}

String _configOrigin(EmitTarget target) => switch (target) {
      EmitTarget.rfw => _rfwConfigOrigin,
      EmitTarget.a2ui => _a2uiConfigOrigin,
      EmitTarget.widgetbook => _widgetbookConfigOrigin,
    };

String _annotationName(EmitTarget target) => switch (target) {
      EmitTarget.rfw => 'rfw',
      EmitTarget.a2ui => 'a2ui',
      EmitTarget.widgetbook => 'wb',
    };
