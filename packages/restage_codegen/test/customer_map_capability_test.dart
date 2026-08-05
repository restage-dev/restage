// A customer library whose widget renders a map slot is using a render
// capability the delivery-time floor must know about, so it MUST declare a
// capability version. An under-capable client has to fail closed at the SDK
// pre-render check rather than render a map it cannot decode.
//
// The assertion is the FAIL-LOUD on an UNDECLARING library, never the stamp on
// a declaring one: a pre-existing loop stamps every declaring library, so a
// stamp assertion is true whether or not the map branch exists at all. The
// declaring run below is a control on the fixture, not a stamp assertion — it
// establishes that the source builds cleanly when the version is present, so
// the undeclared run's failure is attributable to the omission.
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/restage_widget_walker.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final class _CollectionProbeBuilder implements Builder {
  RestageWidgetCollection? collection;
  Object? error;

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$lib$': ['map_capability_probe.txt'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    try {
      collection = await collectRestageWidgetsForPackage(buildStep);
    } on Object catch (caught) {
      error = caught;
    }
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, 'lib/map_capability_probe.txt'),
      'collected',
    );
  }
}

Future<
    ({
      RestageWidgetCollection? collection,
      Object? error,
      List<String> logs,
    })> _collect(String source) async {
  final builder = _CollectionProbeBuilder();
  final logs = <String>[];
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'restage_codegen',
  );
  readerWriter.testing.writeString(
    AssetId('apps_examples', 'lib/field_notes.dart'),
    source,
  );
  await testBuilder(
    builder,
    {'apps_examples|lib/field_notes.dart': source},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    outputs: {
      'apps_examples|lib/map_capability_probe.txt': decodedMatches('collected'),
    },
    onLog: (record) => logs.add(record.message),
  );
  return (
    collection: builder.collection,
    error: builder.error,
    logs: logs,
  );
}

/// A library whose only render capability is a map-typed widget property.
String _fixture({int? capabilityVersion}) => '''
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageLibrary(
    library: WidgetLibrary.custom('acme.design_system'),
    ${capabilityVersion == null ? '' : 'capabilityVersion: $capabilityVersion,'}
  )
  const restageLibrary = 0;

  @RestageWidget(
    name: 'FieldNotes',
    library: WidgetLibrary.custom('acme.design_system'),
    category: WidgetCategory.decoration,
    description: 'A set of annotated field notes.',
  )
  class FieldNotes {
    const FieldNotes({required this.glossary});

    @RestageProperty(description: 'The term glossary.')
    final Map<String, String> glossary;
  }
''';

void main() {
  test('a map-only library must declare a capability version', () async {
    // Control: the same source, with a version declared, builds cleanly. This
    // is what makes the undeclared failure below attributable to the missing
    // declaration rather than to anything else in the fixture.
    final declaredRun = await _collect(_fixture(capabilityVersion: 3));
    expect(
      declaredRun.error,
      isNull,
      reason: 'the fixture must build when the version is declared; got '
          '${declaredRun.error}',
    );

    final undeclaredRun = await _collect(_fixture());

    expect(undeclaredRun.error, isA<StateError>());
    final matchingIssues = undeclaredRun.logs.where(
      (message) =>
          message.contains(
            IssueCode.customLibraryMissingCapabilityVersion.name,
          ) &&
          message.contains('acme.design_system'),
    );
    expect(
      matchingIssues,
      hasLength(1),
      reason: 'the raise must name its own issue code and the offending '
          'namespace; got ${undeclaredRun.logs}',
    );
  });
}
