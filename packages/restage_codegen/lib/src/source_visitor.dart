import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/source_state.dart';

/// One paywall source class discovered by the visitor.
@immutable
@internal
final class PaywallSourceFound {
  /// Creates a record of one discovered paywall source. The [id] and
  /// [className] must be non-empty (asserted in debug).
  const PaywallSourceFound({
    required this.id,
    required this.slot,
    required this.className,
    required this.assetId,
    required this.build,
  })  : assert(id.length > 0, 'PaywallSourceFound.id must not be empty'),
        assert(
          className.length > 0,
          'PaywallSourceFound.className must not be empty',
        );

  /// `@PaywallSource(id:)` value.
  final String id;

  /// `@PaywallSource(slot:)` value, or null if not provided.
  final String? slot;

  /// Class name (for diagnostics).
  final String className;

  /// Asset where this class is declared.
  final AssetId assetId;

  /// The effective root build expression plus optional root state.
  final SourceBuildBlueprint build;

  /// The single returned `Expression` from the effective `build()`.
  Expression get rootExpression => build.rootExpression;
}

/// Result of walking a library for `@PaywallSource` classes.
@immutable
final class VisitorResult {
  /// Constructor. Both lists are wrapped in [List.unmodifiable] to honour
  /// the [@immutable] contract.
  VisitorResult({
    required List<PaywallSourceFound> sources,
    required List<Issue> issues,
  })  : sources = List.unmodifiable(sources),
        issues = List.unmodifiable(issues);

  /// Successfully discovered paywall sources (unmodifiable).
  final List<PaywallSourceFound> sources;

  /// Diagnostic issues collected during the walk (unmodifiable).
  final List<Issue> issues;
}

/// Walks [library] for classes annotated with `@PaywallSource`. For each:
/// - Validates it extends `StatelessWidget` or a supported `StatefulWidget`.
/// - Locates the effective `build()` method.
/// - Validates the body is a single returned `Expression`.
/// - Returns the resolved `@PaywallSource` metadata + root `Expression`.
///
/// The build-method body is extracted from the *resolved* library so that
/// element references on identifier nodes (e.g. `Icons.bolt_rounded`) are
/// populated and the expression translator can resolve static const
/// references to their underlying values at codegen time.
///
/// Detects within-library duplicate ids at the end and drops duplicate
/// occurrences from `sources` while emitting `duplicateId` issues.
Future<VisitorResult> visitPaywallSources(
  LibraryElement library,
  AssetId assetId,
) async {
  final sources = <PaywallSourceFound>[];
  final issues = <Issue>[];

  for (final cls in library.classes) {
    final annotation = firstAnnotation(cls, 'PaywallSource');
    if (annotation == null) continue;

    final className = cls.name ?? '<unnamed>';
    final location = '${assetId.path}#$className';
    final value = annotation.computeConstantValue();
    if (value == null) {
      issues.add(
        Issue(
          code: IssueCode.annotationEvaluationFailed,
          message: '@PaywallSource on $className could not be const-evaluated.',
          location: location,
        ),
      );
      continue;
    }

    final id = value.getField('id')?.toStringValue();
    if (id == null) {
      issues.add(
        Issue(
          code: IssueCode.annotationEvaluationFailed,
          message:
              '@PaywallSource.id is required and must be a String literal.',
          location: location,
        ),
      );
      continue;
    }
    final slot = value.getField('slot')?.toStringValue();

    if (!_extendsSupportedSourceWidget(cls)) {
      final supertypeName = cls.supertype?.element.name ?? 'Object';
      issues.add(
        Issue(
          code: IssueCode.unsupportedBaseClass,
          message: 'Paywall classes must extend StatelessWidget or a '
              'supported StatefulWidget. '
              'Found: extends $supertypeName. '
              'Refactor to a supported root widget subclass.',
          location: location,
        ),
      );
      continue;
    }

    final build = await extractSourceBuildBlueprint(
      sourceClass: cls,
      library: library,
      astNodeFor: _astNodeFor(library),
      issues: issues,
      location: location,
    );
    if (build == null) continue;

    sources.add(
      PaywallSourceFound(
        id: id,
        slot: slot,
        className: className,
        assetId: assetId,
        build: build,
      ),
    );
  }

  // Within-library duplicate-id detection (single-pass).
  final seen = <String>{};
  final duplicateIds = <String>{};
  for (final s in sources) {
    if (!seen.add(s.id)) {
      duplicateIds.add(s.id);
    }
  }
  if (duplicateIds.isNotEmpty) {
    final byId = <String, List<PaywallSourceFound>>{};
    for (final s in sources) {
      byId.putIfAbsent(s.id, () => []).add(s);
    }
    for (final id in duplicateIds) {
      final classes = byId[id]!.map((s) => s.className).join(', ');
      issues.add(
        Issue(
          code: IssueCode.duplicateId,
          message: 'Multiple @PaywallSource classes share id "$id": $classes.',
          location: assetId.path,
        ),
      );
    }
    sources.removeWhere((s) => duplicateIds.contains(s.id));
  }

  return VisitorResult(sources: sources, issues: issues);
}

bool _extendsSupportedSourceWidget(ClassElement cls) {
  var current = cls.supertype;
  while (current != null) {
    if (current.element.name == 'StatelessWidget') return true;
    if (current.element.name == 'StatefulWidget') return true;
    current = current.element.supertype;
  }
  return false;
}

Future<AstNode?> Function(Fragment fragment) _astNodeFor(
  LibraryElement library,
) {
  Future<ResolvedLibraryResult?>? resolved;
  Future<ResolvedLibraryResult?> resolvedLibrary() async {
    final cached = resolved;
    if (cached != null) return cached;
    return resolved = library.session
        .getResolvedLibraryByElement(library)
        .then((result) => result is ResolvedLibraryResult ? result : null);
  }

  return (fragment) async {
    final libraryResult = await resolvedLibrary();
    return libraryResult?.getFragmentDeclaration(fragment)?.node;
  };
}
