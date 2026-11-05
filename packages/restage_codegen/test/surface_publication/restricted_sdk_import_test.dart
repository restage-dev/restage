import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

// A screen library whose SDK import leaves out a name the generated part
// writes fails the build, naming every such name; with them shown, the part
// analyzes clean.
const _base =
    'Screen, Surface, SurfaceScreenRef, SurfaceScreenEventContract, '
    'CapabilityManifest, LibraryRequirement';
const _written = [
  'RestageBundleEntryRole',
  'RestageWidgetLibraries',
  'SurfaceScreenBundleEntryReference',
  'SurfaceScreenBundleLocator',
  'SurfaceScreenRuntimeProvenance',
  'SurfaceVocabulary',
  'buildColumn',
  'buildText',
];

String _screen(String show) =>
    '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart' show $show;

part 'restage.generated/mounted.restage.g.dart';

@Screen(id: 'mounted', surface: Surface.general)
final class Mounted extends StatelessWidget {
  const Mounted({super.key});
  @override
  Widget build(BuildContext context) => Column(children: [Text('Pro')]);
}
''';

Future<({List<String> errors, String? part})> _compile(String source) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final result = await testBuilders(
    [
      restageSourceRosterBuilder(
        const BuilderOptions({'bundled_runtime': true}, isRoot: true),
      ),
      userCatalogJsonBuilder(BuilderOptions.empty),
      restagePackageSurfaceCompilerBuilder(
        const BuilderOptions({'bundled_runtime': true}, isRoot: true),
      ),
      restageGeneratedDartBuilder(
        const BuilderOptions({'bundled_runtime': true}),
      ),
    ],
    {'apps_examples|lib/mounted.dart': source},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  final part = AssetId(
    'apps_examples',
    'lib/restage.generated/mounted.restage.g.dart',
  );
  return (
    errors: [for (final error in result.errors) '$error'],
    part: result.succeeded ? readerWriter.testing.readString(part) : null,
  );
}

void main() {
  test('a show list leaving out generated names fails, naming them all', () async {
    final out = await _compile(_screen(_base));
    expect(out.part, isNull);
    expect(
      out.errors.join('\n'),
      contains(
        'lib/mounted.dart imports `package:restage/restage.dart` with a `show` '
        'or `hide` list that leaves out '
        '${_written.map((name) => '`$name`').join(', ')}, which the generated '
        'code uses.',
      ),
    );
  });

  test('with those names shown the generated part analyzes clean', () async {
    final source = _screen('$_base, ${_written.join(', ')}');
    final out = await _compile(source);
    expect(out.errors, isEmpty);
    await resolveWorkspaceSources(
      {
        'apps_examples|lib/mounted.dart': source,
        'apps_examples|lib/restage.generated/mounted.restage.g.dart': out.part!,
      },
      (resolver) async {
        final library = await resolver.libraryFor(
          AssetId('apps_examples', 'lib/mounted.dart'),
        );
        final resolved = await library.session.getResolvedLibraryByElement(
          library,
        );
        expect(resolved, isA<ResolvedLibraryResult>());
        expect([
          for (final unit in (resolved as ResolvedLibraryResult).units)
            for (final diagnostic in unit.diagnostics)
              if (diagnostic.severity == Severity.error)
                diagnostic.problemMessage.messageText(includeUrl: false),
        ], isEmpty);
      },
      resolverFor: 'apps_examples|lib/mounted.dart',
      rootPackage: 'apps_examples',
    );
  });
}
