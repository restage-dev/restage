import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/helper_registry.dart'
    show libraryUriMatchesOrigin;
import 'package:restage_codegen/src/restage_source_prefilter.dart';
import 'package:restage_shared/restage_shared.dart';

/// Reports direct SDK surface mounts that have no generated asset fallback.
Future<void> warnAboutUnbundledSurfaceMounts(BuildStep buildStep) async {
  final candidates = await selectRestageSurfaceMountCandidates(buildStep);
  for (final asset in candidates) {
    try {
      final library = await buildStep.resolver.libraryFor(
        asset,
        allowSyntaxErrors: true,
      );
      final resolved =
          await library.session.getResolvedLibraryByElement(library);
      if (resolved is! ResolvedLibraryResult) continue;
      for (final unit in resolved.units) {
        if (unit.path.endsWith('.g.dart')) continue;
        unit.unit.accept(_SurfaceMountVisitor(unit.path, unit.lineInfo));
      }
    } on NonLibraryAssetException {
      // The shared source prefilter also selects this part's owner.
      continue;
    }
  }
}

final class _SurfaceMountVisitor extends RecursiveAstVisitor<void> {
  _SurfaceMountVisitor(this.path, this.lineInfo);

  final String path;
  final LineInfo lineInfo;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    super.visitInstanceCreationExpression(node);
    final owner = node.constructorName.element?.enclosingElement;
    final name = owner?.name;
    if (!const {
          'RestagePaywall',
          'RestageScreen',
          'RestageFlowGraph',
          'RestageOnboarding',
        }.contains(name) ||
        !libraryUriMatchesOrigin(
          owner!.library.identifier,
          'package:restage',
        )) {
      return;
    }
    final arguments = {
      for (final argument
          in node.argumentList.arguments.whereType<NamedExpression>())
        argument.name.label.name: argument.expression,
    };
    final argumentName = switch (name) {
      'RestagePaywall' => 'id',
      'RestageScreen' => 'screen',
      _ => 'flow',
    };
    final reference = arguments[argumentName];
    if (reference == null) return;
    if (argumentName == 'flow') {
      final compiled =
          reference.computeConstantValue()?.value?.getField('compiled');
      if (_hasCompleteScreenBuilders(compiled)) return;
    }
    final unavailable = arguments['unavailable'];
    final fallback =
        unavailable?.computeConstantValue()?.value?.getField('fallbackBuilder');
    if (fallback != null && !fallback.isNull) return;
    if (unavailable is InstanceCreationExpression &&
        unavailable.constructorName.name?.name == 'fallback') {
      return;
    }
    for (final name in ['fallbackBuilder', 'errorBuilder']) {
      final type = arguments[name]?.staticType;
      if (type is FunctionType &&
          type.nullabilitySuffix == NullabilitySuffix.none) {
        return;
      }
    }
    final remedy = name == 'RestagePaywall'
        ? 'supply fallbackBuilder or errorBuilder'
        : 'supply an unavailable fallback builder';
    final location = lineInfo.getLocation(node.offset);
    log.warning(
      '$path:${location.lineNumber}:${location.columnNumber}: '
      '[restage] $name($argumentName: ${reference.toSource()}) '
      'has no generated '
      'asset fallback because bundled_runtime is false. Use the generated '
      'typed surface mount, enable bundled_runtime, or $remedy '
      'to handle unavailable delivery.',
    );
  }
}

bool _hasCompleteScreenBuilders(DartObject? compiled) {
  if (compiled == null || compiled.isNull) return false;
  final json = compiled.getField('documentJson')?.toStringValue();
  final screens = compiled.getField('screens')?.toMapValue();
  final children = compiled.getField('children')?.toMapValue();
  if (json == null || screens == null || children == null) return false;
  try {
    final document = FlowDocumentCodec.decodeJson(json);
    FlowDocumentValidation.checkValid(document);
    final screenIds = {
      for (final entry in screens.entries)
        if (entry.value != null && !entry.value!.isNull)
          entry.key?.toStringValue(),
    };
    final childFlows = {
      for (final entry in children.entries)
        entry.key?.toStringValue(): entry.value,
    };
    return document.screenArtifacts.keys.every(screenIds.contains) &&
        document.states.values.whereType<SubFlowState>().every(
              (state) => _hasCompleteScreenBuilders(childFlows[state.flow]),
            );
  } on Object {
    // Invalid constant metadata does not establish an available fallback.
    return false;
  }
}
