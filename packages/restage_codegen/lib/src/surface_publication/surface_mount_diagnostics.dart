import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/dot_shorthand_expansion.dart';
import 'package:restage_codegen/src/helper_registry.dart'
    show libraryUriMatchesOrigin;
import 'package:restage_codegen/src/restage_source_prefilter.dart';
import 'package:restage_shared/restage_shared.dart';

/// Reports direct SDK surface mounts that have no generated asset fallback
/// when the package is not [bundled], and flows whose steps need screen
/// builders the mount does not bind.
Future<void> warnAboutUnbundledSurfaceMounts(
  BuildStep buildStep, {
  bool bundled = false,
}) async {
  final candidates = await selectRestageSurfaceMountCandidates(buildStep);
  for (final asset in candidates) {
    try {
      final library = await buildStep.resolver.libraryFor(
        asset,
        allowSyntaxErrors: true,
      );
      final resolved = await resolveLibraryInLongForm(library);
      if (resolved is! ResolvedLibraryResult) continue;
      for (final unit in resolved.units) {
        if (unit.path.endsWith('.g.dart')) continue;
        // Messages name the file relative to its package.
        final uri = unit.unit.declaredFragment?.source.uri;
        final relative =
            uri?.scheme == 'package' && uri!.pathSegments.length > 1
            ? 'lib/${uri.pathSegments.skip(1).join('/')}'
            : asset.path;
        unit.unit.accept(
          _SurfaceMountVisitor(
            unit.lineInfo,
            bundled: bundled,
            relativePath: relative,
          ),
        );
      }
    } on NonLibraryAssetException {
      // The shared source prefilter also selects this part's owner.
      continue;
    }
  }
}

final class _SurfaceMountVisitor extends RecursiveAstVisitor<void> {
  _SurfaceMountVisitor(
    this.lineInfo, {
    required this.bundled,
    required this.relativePath,
  });

  final String relativePath;

  final LineInfo lineInfo;
  final bool bundled;

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
          in node.argumentList.arguments.whereType<NamedArgument>())
        argument.name.lexeme: argument.argumentExpression,
    };
    final argumentName = switch (name) {
      'RestagePaywall' => 'id',
      'RestageScreen' => 'screen',
      _ => 'flow',
    };
    final reference = arguments[argumentName];
    if (reference == null) return;
    if (argumentName == 'flow') {
      final ref = reference.computeConstantValue()?.value;
      final compiled = ref?.getField('compiled');
      final unbound = _unboundStepMounts(ref);
      if (unbound.isNotEmpty) {
        final location = lineInfo.getLocation(node.offset);
        // The generated reference names the widget generated for it.
        final flow = ref?.getField('surfaceWidget')?.toStringValue();
        log.warning(
          '`$relativePath:${location.lineNumber}:${location.columnNumber}`: '
          '`$name(flow: ${reference.toSource()})` shows steps that need the '
          "app's code: ${unbound.map((step) => '`$step`').join(', ')}. No "
          'screen builder is bound for them.'
          '${flow == null ? '' : ' Try using the generated `$flow` widget '
                    'instead.'}',
        );
      }
      if (_hasCompleteScreenBuilders(compiled)) return;
    }
    if (bundled) return;
    // Only a fallback widget handles unavailable delivery here: a direct
    // mount has no original, and an error builder shows error UI instead.
    final fallback = arguments['fallbackBuilder']?.staticType;
    if (fallback is FunctionType &&
        fallback.nullabilitySuffix == NullabilitySuffix.none) {
      return;
    }
    const remedy = 'pass a fallbackBuilder';
    final location = lineInfo.getLocation(node.offset);
    log.warning(
      '$relativePath:${location.lineNumber}:${location.columnNumber}: '
      '[restage] $name($argumentName: ${reference.toSource()}) '
      'has no generated '
      'asset fallback because bundled_runtime is false. Use the generated '
      'typed surface mount, enable bundled_runtime, or $remedy '
      'to handle unavailable delivery.',
    );
  }
}

/// The step classes of [ref] with a mount whose screen builder is not bound.
List<String> _unboundStepMounts(DartObject? ref) {
  final mounts = ref
      ?.getField('vocabulary')
      ?.getField('stepMounts')
      ?.toMapValue();
  final screens = ref?.getField('compiled')?.getField('screens')?.toMapValue();
  if (mounts == null || mounts.isEmpty) return const [];
  final bound = {
    for (final key in screens?.keys ?? const <DartObject?>[])
      key?.toStringValue(),
  };
  return [
    for (final entry in mounts.entries)
      if (entry.key?.toStringValue() case final id? when !bound.contains(id))
        _stepClass(entry.value, id),
  ]..sort();
}

// The @Screen class whose step [id] the mount function [mount] renders, as
// written; the id when it cannot be found.
String _stepClass(DartObject? mount, String id) {
  final library = mount?.toFunctionValue()?.library;
  if (library == null) return id;
  final stem = p.basenameWithoutExtension(library.uri.path);
  for (final declaration in library.classes) {
    final value = firstAnnotationFromOriginAny(
      declaration,
      const {'Screen'},
      'package:restage',
    )?.computeConstantValue();
    if (value == null) continue;
    final explicit = value.getField('id')?.toStringValue();
    if ((explicit ?? stem) == id) return declaration.name ?? id;
  }
  return id;
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
