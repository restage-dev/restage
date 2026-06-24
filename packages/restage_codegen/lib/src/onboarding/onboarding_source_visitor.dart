// Internal visitor records are consumed only by onboarding builders.
// ignore_for_file: public_member_api_docs

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/source_state.dart';

const String _kSdkLibraryOrigin = 'package:restage';

@immutable
final class OnboardingScreenSourceFound {
  const OnboardingScreenSourceFound({
    required this.id,
    required this.version,
    required this.minClient,
    required this.className,
    required this.assetId,
    required this.build,
  });

  final String id;
  final int version;
  final int minClient;
  final String className;
  final AssetId assetId;
  final SourceBuildBlueprint build;

  Expression get rootExpression => build.rootExpression;
}

@immutable
final class OnboardingVisitorResult {
  OnboardingVisitorResult({
    required List<OnboardingScreenSourceFound> sources,
    required List<Issue> issues,
  })  : sources = List.unmodifiable(sources),
        issues = List.unmodifiable(issues);

  final List<OnboardingScreenSourceFound> sources;
  final List<Issue> issues;
}

/// Walks `@ScreenSource` (and the deprecated `@OnboardingSource` alias) classes
/// using the same resolved build-expression substrate as paywall codegen.
Future<OnboardingVisitorResult> visitOnboardingSources(
  LibraryElement library,
  AssetId assetId,
) async {
  final sources = <OnboardingScreenSourceFound>[];
  final issues = <Issue>[];

  for (final cls in library.classes) {
    final annotation = firstAnnotationFromOriginAny(
      cls,
      const {'ScreenSource', 'OnboardingSource'},
      _kSdkLibraryOrigin,
    );
    if (annotation == null) continue;

    final className = cls.name ?? '<unnamed>';
    final location = '${assetId.path}#$className';
    final value = annotation.computeConstantValue();
    if (value == null) {
      issues.add(
        Issue(
          code: IssueCode.annotationEvaluationFailed,
          message: '@ScreenSource on $className could not be const-evaluated.',
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
          message: '@ScreenSource.id is required and must be a String literal.',
          location: location,
        ),
      );
      continue;
    }

    if (!_extendsSupportedSourceWidget(cls)) {
      final supertypeName = cls.supertype?.element.name ?? 'Object';
      issues.add(
        Issue(
          code: IssueCode.unsupportedBaseClass,
          message: 'Flow screens must extend StatelessWidget or a '
              'supported StatefulWidget. '
              'Found: extends $supertypeName.',
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
      OnboardingScreenSourceFound(
        id: id,
        version: value.getField('version')?.toIntValue() ?? 1,
        minClient: value.getField('minClient')?.toIntValue() ?? 3,
        className: className,
        assetId: assetId,
        build: build,
      ),
    );
  }

  final seen = <String>{};
  final duplicates = <String>{};
  for (final source in sources) {
    if (!seen.add(source.id)) duplicates.add(source.id);
  }
  if (duplicates.isNotEmpty) {
    for (final id in duplicates) {
      final classes = sources
          .where((source) => source.id == id)
          .map((source) => source.className)
          .join(', ');
      issues.add(
        Issue(
          code: IssueCode.duplicateId,
          message: 'Multiple @ScreenSource classes share id "$id": '
              '$classes.',
          location: assetId.path,
        ),
      );
    }
    sources.removeWhere((source) => duplicates.contains(source.id));
  }

  return OnboardingVisitorResult(sources: sources, issues: issues);
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
