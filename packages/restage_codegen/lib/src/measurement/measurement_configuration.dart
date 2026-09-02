import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/issue.dart';

const String _restageConfigureSource =
    'package:restage/src/runtime/restage.dart';
const String _measurementEnabledName = 'measurementEnabled';

/// The resolved package Measurement setting.
@immutable
final class MeasurementConfigurationResult {
  /// Creates a resolved package setting.
  MeasurementConfigurationResult({
    required this.enabled,
    required Iterable<Issue> issues,
  }) : issues = List.unmodifiable(issues);

  /// Whether Measurement is enabled for the package.
  final bool enabled;

  /// Diagnostics that prevent the setting from being used.
  final List<Issue> issues;

  /// Whether the setting was resolved without diagnostics.
  bool get isValid => issues.isEmpty;
}

/// Registers the resolved libraries that can determine the package setting.
Future<void> registerMeasurementConfigurationDependencies(
  BuildStep buildStep,
  Iterable<AssetId> candidates,
) async {
  for (final assetId in candidates) {
    try {
      await buildStep.resolver.libraryFor(assetId, allowSyntaxErrors: true);
    } on Object {
      continue;
    }
  }
}

/// Resolves the package Measurement setting from authored Dart libraries.
Future<MeasurementConfigurationResult> resolveMeasurementConfiguration(
  BuildStep buildStep, {
  required Iterable<AssetId> candidates,
}) async {
  final issues = <Issue>[];
  final uses = <_MeasurementConfigurationUse>[];
  final inspectedLibraries = <String>{};

  for (final assetId in candidates) {
    final LibraryElement library;
    try {
      library = await buildStep.resolver.libraryFor(
        assetId,
        allowSyntaxErrors: true,
      );
    } on NonLibraryAssetException {
      continue;
    } on Object catch (error) {
      issues.add(
        Issue(
          code: IssueCode.measurementConfigurationInvalid,
          message: 'The Measurement setting in ${assetId.path} could not be '
              'resolved: $error',
          location: assetId.path,
        ),
      );
      continue;
    }
    if (!inspectedLibraries.add(library.identifier)) continue;

    final resolved = await library.session.getResolvedLibraryByElement(library);
    if (resolved is! ResolvedLibraryResult || resolved.units.isEmpty) {
      issues.add(
        Issue(
          code: IssueCode.measurementConfigurationInvalid,
          message: 'The Measurement setting in ${assetId.path} could not be '
              'resolved.',
          location: assetId.path,
        ),
      );
      continue;
    }
    for (final unit in resolved.units) {
      // Only the defining unit may set package-wide configuration.
      if (unit.libraryFragment != library.firstFragment) continue;
      final visitor = _MeasurementConfigurationVisitor(
        path: unit.path,
        lineInfo: unit.lineInfo,
      );
      unit.unit.accept(visitor);
      issues.addAll(visitor.issues);
      uses.addAll(visitor.uses);
    }
  }

  final enabledValues = uses.map((use) => use.enabled).toSet();
  if (enabledValues.length > 1) {
    final locations = uses.map((use) => use.location).join(', ');
    issues.add(
      Issue(
        code: IssueCode.measurementConfigurationInvalid,
        message: 'All Restage.configure measurementEnabled values must '
            'agree. Found conflicting values at $locations.',
        location: locations,
      ),
    );
  }

  final enabled = enabledValues.firstOrNull ?? true;
  return MeasurementConfigurationResult(enabled: enabled, issues: issues);
}

final class _MeasurementConfigurationVisitor extends RecursiveAstVisitor<void> {
  _MeasurementConfigurationVisitor({
    required this.path,
    required this.lineInfo,
  });

  final String path;
  final LineInfo lineInfo;
  final List<_MeasurementConfigurationUse> uses = [];
  final List<Issue> issues = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_isRestageConfigure(node.methodName.element)) {
      _collectSetting(node);
    } else if (node.methodName.name == 'call' &&
        _isRestageConfigure(_expressionElement(node.realTarget))) {
      _collectSetting(node);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    if (_isRestageConfigure(node.element) ||
        _isRestageConfigure(_expressionElement(node.function))) {
      _collectSetting(node);
    }
    super.visitFunctionExpressionInvocation(node);
  }

  void _collectSetting(InvocationExpression node) {
    final arguments = node.argumentList.arguments
        .whereType<NamedExpression>()
        .where(
          (argument) => argument.name.label.name == _measurementEnabledName,
        )
        .toList(growable: false);
    final location = _location(node);
    if (arguments.length > 1) {
      issues.add(
        Issue(
          code: IssueCode.measurementConfigurationInvalid,
          message: 'Restage.configure may specify measurementEnabled only '
              'once.',
          location: location,
        ),
      );
      return;
    }

    final enabled =
        arguments.isEmpty ? true : _readBoolean(arguments.single.expression);
    if (enabled == null) {
      issues.add(
        Issue(
          code: IssueCode.measurementConfigurationInvalid,
          message: 'Restage.configure measurementEnabled must be a '
              'compile-time bool literal or const bool reference.',
          location: location,
        ),
      );
      return;
    }
    uses.add((enabled: enabled, location: location));
  }

  Element? _expressionElement(Expression? expression) {
    var current = expression;
    while (current is ParenthesizedExpression) {
      current = current.expression;
    }
    return switch (current) {
      SimpleIdentifier() => current.element,
      PrefixedIdentifier() => current.identifier.element,
      PropertyAccess() => current.propertyName.element,
      _ => null,
    };
  }

  bool _isRestageConfigure(Element? element) {
    if (element is! MethodElement ||
        !element.isStatic ||
        element.name != 'configure') {
      return false;
    }
    final owner = element.enclosingElement;
    if (owner is! ClassElement || owner.name != 'Restage') return false;
    if (owner.library.identifier != _restageConfigureSource ||
        element.library.identifier != _restageConfigureSource) {
      return false;
    }
    return element.firstFragment.libraryFragment.source.uri.toString() ==
        _restageConfigureSource;
  }

  bool? _readBoolean(Expression expression) {
    var current = expression;
    while (current is ParenthesizedExpression) {
      current = current.expression;
    }
    if (current is BooleanLiteral) return current.value;

    final element = _expressionElement(current);
    final variable = switch (element) {
      VariableElement() => element,
      PropertyAccessorElement() => element.variable,
      _ => null,
    };
    if (variable == null || !variable.isConst || !_isBool(variable.type)) {
      return null;
    }
    return current.computeConstantValue()?.value?.toBoolValue();
  }

  bool _isBool(DartType type) {
    return type is InterfaceType &&
        type.element.name == 'bool' &&
        type.element.library.identifier == 'dart:core' &&
        type.nullabilitySuffix == NullabilitySuffix.none;
  }

  String _location(AstNode node) {
    final location = lineInfo.getLocation(node.offset);
    return '$path@${location.lineNumber}:${location.columnNumber}';
  }
}

typedef _MeasurementConfigurationUse = ({bool enabled, String location});
