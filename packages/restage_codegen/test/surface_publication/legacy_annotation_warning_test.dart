import 'package:restage_codegen/src/restage_source_roster.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler.dart';
import 'package:restage_shared/restage_shared.dart' show Surface;
import 'package:test/test.dart';

RestageSourceDeclaration _declaration(
  RestageRosterSourceKind kind,
  String? legacyAnnotation,
) =>
    RestageSourceDeclaration(
      kind: kind,
      libraryIdentity: 'package:app/source.dart',
      libraryPath: 'lib/source.dart',
      declarationIdentity: 'package:app/source.dart#Source',
      sourcePath: 'lib/source.dart',
      explicitId: 'source',
      span: const RestageSourceSpan(
        path: 'lib/source.dart',
        startLine: 1,
        startColumn: 1,
        endLine: 1,
        endColumn: 1,
      ),
      identityClaims: const [],
      outputs: const [],
      legacyAnnotation: legacyAnnotation,
    );

void main() {
  test('names the annotation a source uses and its replacement', () {
    expect(
      legacyAnnotationWarning(
        _declaration(RestageRosterSourceKind.paywall, 'PaywallSource'),
        Surface.paywall,
        'pro',
      ),
      "The paywall 'pro' uses @PaywallSource, which is deprecated, and "
      'cannot be delivered over the air. Use @Paywall(id: ...).',
    );
    expect(
      legacyAnnotationWarning(
        _declaration(RestageRosterSourceKind.screen, 'OnboardingSource'),
        Surface.onboarding,
        'welcome',
      ),
      allOf(contains('@OnboardingSource'), contains('Use @Screen(id: ...)')),
    );
    expect(
      legacyAnnotationWarning(
        _declaration(RestageRosterSourceKind.flow, 'FlowSource'),
        Surface.survey,
        'pulse',
      ),
      allOf(
        contains('@FlowSource'),
        contains('Use @FlowGraph(id: ..., surface: Surface.survey)'),
        isNot(contains('@Paywall')),
      ),
    );
  });
}
