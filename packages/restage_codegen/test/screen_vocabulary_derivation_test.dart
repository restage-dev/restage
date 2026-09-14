import 'package:build/build.dart';
import 'package:logging/logging.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The vocabulary a generated reference carries is DERIVED from the surfaces,
/// not handed to the emitter.
///
/// The emitter's own tests supply a vocabulary as a fixture, so they prove
/// only that it writes what it is given. These drive the real build.
void main() {
  test('a generated screen part names only the builders that screen draws',
      () async {
    final build = await _build(_drawnWidgetSources);
    expect(build.result.succeeded, isTrue, reason: build.logs);

    final part = build.result.readerWriter.testing.readString(
      AssetId(
        'apps_examples',
        'lib/onboarding/screens/restage.generated/welcome.restage.g.dart',
      ),
    );
    final packed = part.replaceAll(RegExp(r'\s+'), '');

    expect(packed, contains('vocabulary:constSurfaceVocabulary('));
    expect(packed, contains("'Column':buildColumn"));
    expect(packed, contains("'Text':buildText"));
    // The rest of the catalog stays out of the app: a widget the screen never
    // draws is never named.
    expect(part, isNot(contains('buildRow')));
    expect(part, isNot(contains('buildChip')));
  });

  test('two screens of one flow can share a code point', () async {
    // Icons.trending_flat and Icons.trending_neutral are both 0xe67e and
    // differ only in matchTextDirection, which the delivered vocabulary now
    // carries — so the flow that reaches both installs two entries.
    final build = await _build(_sharedCodePointIconSources);

    expect(build.result.succeeded, isTrue, reason: build.logs);
    expect(build.logs, isNot(contains('IconCodePointCollision')));

    String packedPart(String screen) => build.result.readerWriter.testing
        .readString(
          AssetId(
            'apps_examples',
            'lib/onboarding/screens/restage.generated/$screen.restage.g.dart',
          ),
        )
        .replaceAll(RegExp(r'\s+'), '');

    // The mirroring glyph fills the mirrored map, leaving families empty; the
    // ordinary one fills families and leaves the mirrored map off.
    expect(
      packedPart('welcome'),
      contains(
        "RestageIconTable.fromFamilies(families:{},mirrored:{'MaterialIcons':"
        "{0xe67e:IconData(0xe67e,fontFamily:'MaterialIcons',"
        'matchTextDirection:true),},})',
      ),
    );
    expect(
      packedPart('details'),
      contains(
        "RestageIconTable.fromFamilies(families:{'MaterialIcons':"
        "{0xe67e:IconData(0xe67e,fontFamily:'MaterialIcons'),},})",
      ),
    );
  });
}

Future<({TestBuilderResult result, String logs})> _build(
  Map<String, String> sources,
) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  for (final entry in sources.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  final records = <LogRecord>[];
  final result = await testBuilders(
    [
      onboardingScreenBuilder(BuilderOptions.empty),
      onboardingFlowBuilder(BuilderOptions.empty),
      restagePackageSurfaceCompilerBuilder(BuilderOptions.empty),
      restageGeneratedDartBuilder(BuilderOptions.empty),
    ],
    sources,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: records.add,
  );
  return (
    result: result,
    logs: records.map((record) => record.message).join('\n'),
  );
}

String _screenSource({
  required String flutterImport,
  required String id,
  required String className,
  required String body,
}) =>
    '''
import '$flutterImport';
import 'package:restage/restage.dart';

part 'restage.generated/$id.restage.g.dart';

@Screen(id: '$id', surface: Surface.general)
final class $className extends StatelessWidget {
  const $className({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => $body;
}
''';

String _flowSource(String screens, String transitions) => '''
import 'package:restage/restage.dart';

$screens

part 'restage.generated/first_run.restage.g.dart';

@FlowGraph(id: 'first_run', surface: Surface.general)
const firstRun = FlowDefinition(
  start: WelcomeScreen,
  transitions: [
$transitions
  ],
);
''';

final Map<String, String> _drawnWidgetSources = {
  'apps_examples|lib/onboarding/screens/welcome.dart': _screenSource(
    flutterImport: 'package:flutter/widgets.dart',
    id: 'welcome',
    className: 'WelcomeScreen',
    body: "const Column(children: [Text('welcome')])",
  ),
  'apps_examples|lib/onboarding/flows/first_run.dart': _flowSource(
    "import '../screens/welcome.dart';",
    '    Transition.complete(WelcomeScreen.next),',
  ),
};

final Map<String, String> _sharedCodePointIconSources = {
  'apps_examples|lib/onboarding/screens/welcome.dart': _screenSource(
    flutterImport: 'package:flutter/material.dart',
    id: 'welcome',
    className: 'WelcomeScreen',
    body: 'const Column(children: [Icon(Icons.trending_flat)])',
  ),
  'apps_examples|lib/onboarding/screens/details.dart': _screenSource(
    flutterImport: 'package:flutter/material.dart',
    id: 'details',
    className: 'DetailsScreen',
    body: 'const Column(children: [Icon(Icons.trending_neutral)])',
  ),
  'apps_examples|lib/onboarding/flows/first_run.dart': _flowSource(
    "import '../screens/details.dart';\n"
        "import '../screens/welcome.dart';",
    '    Transition(WelcomeScreen.next, to: DetailsScreen),\n'
        '    Transition.complete(DetailsScreen.next),',
  ),
};
