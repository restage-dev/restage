import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/restage_shared.dart';

/// A placement definition as generated code declares it: the surface it
/// shows by default and the host contract it passes.
typedef GeneratedPlacementDefinition = ({
  Map<String, Object?> locator,
  Map<String, Object?> host,
});

/// Every `generatedPlacementDefinition(...)` call in [source] with literal
/// locator and host contract arguments, in source order.
List<GeneratedPlacementDefinition> generatedPlacementDefinitions(
  String source,
) {
  final found = <GeneratedPlacementDefinition>[];
  parseString(
    content: source,
    throwIfDiagnostics: false,
  ).unit.accept(_DefinitionCalls(found));
  return found;
}

/// The value a const literal [node] spells, or `null` when it spells none.
Object? generatedLiteralValue(Expression? node) => switch (node) {
  null => null,
  NullLiteral() => null,
  BooleanLiteral(:final value) => value,
  IntegerLiteral(:final value) => value,
  DoubleLiteral(:final value) => value,
  SimpleStringLiteral(:final value) => value,
  AdjacentStrings(:final strings) =>
    strings.map((s) => generatedLiteralValue(s)! as String).join(),
  PrefixExpression(operator: final op, :final operand) when op.lexeme == '-' =>
    -(generatedLiteralValue(operand)! as num),
  ListLiteral(:final elements) => [
    for (final e in elements) generatedLiteralValue(e as Expression),
  ],
  SetOrMapLiteral(:final elements) => <String, Object?>{
    for (final e in elements.whereType<MapLiteralEntry>())
      generatedLiteralValue(e.key)! as String: generatedLiteralValue(e.value),
  },
  ParenthesizedExpression(:final expression) => generatedLiteralValue(
    expression,
  ),
  _ => null,
};

final class _DefinitionCalls extends RecursiveAstVisitor<void> {
  _DefinitionCalls(this.found);

  final List<GeneratedPlacementDefinition> found;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'generatedPlacementDefinition') {
      Object? named(String name) {
        for (final argument in node.argumentList.arguments) {
          if (argument is NamedArgument && argument.name.lexeme == name) {
            return generatedLiteralValue(argument.argumentExpression);
          }
        }
        return null;
      }

      final locator = named('defaultSurfaceLocatorJson');
      final host = named('hostContractJson');
      if (locator is Map<String, Object?> && host is Map<String, Object?>) {
        found.add((locator: locator, host: host));
      }
    }
    super.visitMethodInvocation(node);
  }
}

// What the host contract decides; the installed capabilities are the
// device's.
const Set<SurfaceFitFailureCodeV1> _hostFailures = {
  SurfaceFitFailureCodeV1.hostingMismatch,
  SurfaceFitFailureCodeV1.missingHostField,
  SurfaceFitFailureCodeV1.incompatibleHostField,
  SurfaceFitFailureCodeV1.unhandledEvent,
  SurfaceFitFailureCodeV1.incompatibleEventShape,
  SurfaceFitFailureCodeV1.deliveryModeMismatch,
  SurfaceFitFailureCodeV1.actionMismatch,
  SurfaceFitFailureCodeV1.seedMismatch,
  SurfaceFitFailureCodeV1.signalMismatch,
  SurfaceFitFailureCodeV1.resultMismatch,
  SurfaceFitFailureCodeV1.outboundMismatch,
  SurfaceFitFailureCodeV1.missingIsland,
  SurfaceFitFailureCodeV1.changedIsland,
  SurfaceFitFailureCodeV1.unproducedHostField,
  SurfaceFitFailureCodeV1.unproducedIsland,
};

/// The host failures of each publication in [manifest] against the
/// placement the same build generates for it, read from [generatedParts].
List<Issue> placementSelfFitIssues(
  SurfacePublicationManifest manifest,
  Iterable<String> generatedParts,
) {
  final issues = <Issue>[];
  final definitions = <(String, String), List<SurfaceHostContractV1>>{};
  for (final part in generatedParts) {
    if (!part.contains('generatedPlacementDefinition')) continue;
    for (final definition in generatedPlacementDefinitions(part)) {
      try {
        final locator = DeliverySurfaceLocatorV1.fromJson(definition.locator);
        (definitions[(locator.surfaceType.value, locator.slug)] ??= []).add(
          SurfaceHostContractV1.fromJson(definition.host),
        );
      } on FormatException catch (error) {
        issues.add(
          Issue(
            code: IssueCode.surfaceDoesNotFitPlacement,
            message:
                "A generated placement can't be read, so a device can't "
                'show what is published for it: ${error.message}',
            location:
                '${definition.locator['surfaceType']}/'
                '${definition.locator['slug']}',
          ),
        );
      }
    }
  }
  final installed = InstalledCapability(
    builtInCatalogVersion: 0,
    installedLibraries: const [],
  );
  for (final entry in manifest.publications) {
    final publication = entry.publication;
    final requirement = publication.fitRequirement;
    if (requirement == null) continue;
    final hosts =
        definitions[(publication.surface.wireName, publication.slug)] ??
        const <SurfaceHostContractV1>[];
    for (final host in hosts) {
      final failures = [
        for (final failure in SurfaceFitEvaluator.evaluate(
          host: host,
          requirement: requirement,
          installed: installed,
        ).failures)
          if (_hostFailures.contains(failure.code)) failure,
      ];
      if (failures.isEmpty) continue;
      final subject =
          "The ${publication.surface.wireName} '${publication.slug}'";
      final reasons = [
        for (final failure in failures.take(3)) _reason(failure, requirement),
        if (failures.length > 3) 'and ${failures.length - 3} more',
      ];
      issues.add(
        Issue(
          code: IssueCode.surfaceDoesNotFitPlacement,
          message:
              "$subject needs what its own placement doesn't pass: "
              "${reasons.join('; ')}. A device would show the placement's "
              'fallback instead of a published version. '
              '${_fix(failures.first.code)}',
          location: '${publication.surface.wireName}/${publication.slug}',
        ),
      );
    }
  }
  return issues;
}

String _reason(SurfaceFitFailureV1 failure, SurfaceFitRequirementV1 required) {
  final name = _subject(failure.path);
  return switch (failure.code) {
    SurfaceFitFailureCodeV1.unproducedHostField =>
      'it reads `${required.requiredContext.inputs[name]?.label ?? name}` '
          "where the placement's build doesn't produce it",
    SurfaceFitFailureCodeV1.unproducedIsland =>
      'it places `${required.islandLabels[name] ?? name}` where the '
          "placement's build doesn't produce it",
    SurfaceFitFailureCodeV1.missingHostField =>
      switch (required.requiredContext.inputs[name]?.label) {
        final label? =>
          'it reads `$label` from the app, which the placement '
              "doesn't pass",
        null =>
          'it reads a value the app computes (`$name`), which the '
              "placement doesn't pass",
      },
    SurfaceFitFailureCodeV1.incompatibleHostField =>
      "it reads `$name` with a type the placement doesn't pass",
    SurfaceFitFailureCodeV1.unhandledEvent ||
    SurfaceFitFailureCodeV1.incompatibleEventShape =>
      "it sends the event `$name`, which the placement doesn't handle",
    SurfaceFitFailureCodeV1.missingIsland ||
    SurfaceFitFailureCodeV1.changedIsland =>
      'it places `${required.islandLabels[name] ?? name}`, which the '
          "placement doesn't render",
    _ => "its ${failure.code.name} doesn't match the placement's",
  };
}

// The value or island [path] names; an island's own name is dotted.
String _subject(String path) {
  for (final marker in const [
    '.requiredContext.',
    '.requiredIslands.',
    '.islands.',
  ]) {
    final at = path.indexOf(marker);
    if (at >= 0) return path.substring(at + marker.length);
  }
  return path.split('.').last;
}

String _fix(SurfaceFitFailureCodeV1 code) => switch (code) {
  SurfaceFitFailureCodeV1.unproducedHostField ||
  SurfaceFitFailureCodeV1.unproducedIsland =>
    'Try computing it before the build branches.',
  SurfaceFitFailureCodeV1.missingHostField ||
  SurfaceFitFailureCodeV1.incompatibleHostField =>
    'Try computing that value inside a widget marked `@RenderInApp()`.',
  SurfaceFitFailureCodeV1.missingIsland ||
  SurfaceFitFailureCodeV1.changedIsland =>
    'Try marking the widget that contains it `@RenderInApp()`.',
  _ => 'Try handling it where the surface is mounted.',
};
