import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('three-screen first_run fixture emits the frozen E2E contract',
      () async {
    final sources = _firstRunSources();
    final readerWriter = await _readerWriterWith(sources);

    final result = await testBuilders(
      [
        onboardingScreenBuilder(BuilderOptions.empty),
        onboardingFlowBuilder(BuilderOptions.empty),
      ],
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue);

    for (final screen in _screens) {
      final metadata = _screenMetadata[screen]!;
      final generatedScreen = _readString(
        result,
        'lib/onboarding/screens/$screen.rsscreen.g.dart',
      );
      expect(
        generatedScreen,
        allOf(
          contains("id: '${metadata.id}'"),
          contains("artifactPath: '${metadata.artifactPath}'"),
          contains('version: ${metadata.version}'),
          contains('minClient: ${metadata.minClient}'),
        ),
      );
      final rfwText = _readString(
        result,
        'assets/onboarding/screens/$screen.rfwtxt',
      );
      expect(
        rfwText,
        allOf(
          contains('widget OnboardingScreen ='),
          contains('event "${metadata.event}"'),
          contains('Text(text: "${metadata.className}")'),
        ),
      );
      if (screen == 'welcome') {
        expect(
          rfwText,
          contains(
            'event "analyticsTap" { ctaId: "primary", secret: "internal" }',
          ),
        );
      }
      final rfwBlob =
          _readBytes(result, 'assets/onboarding/screens/$screen.rfw');
      expect(rfwBlob, isNotEmpty);
      expect(
        () => fmt.decodeLibraryBlob(Uint8List.fromList(rfwBlob)),
        returnsNormally,
      );
    }

    final generatedFlow = _readString(
      result,
      'lib/onboarding/flows/first_run.rsflow.g.dart',
    );
    expect(
      generatedFlow,
      allOf([
        contains('abstract final class FirstRunFlowDescriptor'),
        contains('OnboardingFlowRef<FirstRunResult>'),
        contains("id: 'first_run'"),
        contains('version: 1'),
        contains('minClient: 3'),
        contains('decodeResult: FirstRunFlowDescriptor._decodeResult'),
        contains('final class FirstRunResult'),
        contains('final class FirstRunActions implements FlowActionRegistry'),
        contains("actionName: 'requestNotifications'"),
        contains("encodeResult: (value) => {'granted': value.granted},"),
      ]),
    );

    final flowJson = utf8.decode(
      _readBytes(result, 'assets/onboarding/flows/first_run.flow.json'),
    );
    final document = FlowDocumentCodec.decodeJson(flowJson);
    expect(document.flow, 'first_run');
    expect(document.initial, 'welcome');
    expect(
      document.states.keys,
      containsAll(['welcome', 'permissions', 'ready', 'done']),
    );
    expect(document.screenArtifacts.keys, containsAll(_screens));
    expect(document.actions.keys, ['requestNotifications']);
    expect(document.actions['requestNotifications']?.idempotent, isFalse);

    final golden = _readSharedFirstRunGolden();
    expect(
      FlowDocumentCodec.encodeCanonicalJson(document),
      FlowDocumentCodec.encodeCanonicalJson(
        FlowDocumentCodec.decodeJson(golden),
      ),
    );

    for (final entry in document.screenArtifacts.entries) {
      final blob = _readBytes(
        result,
        'assets/onboarding/screens/${entry.value.path}',
      );
      expect(
        entry.value.contentHash,
        FlowContentHash.compute(blob),
        reason: entry.key,
      );

      // Each screen emits a capability sidecar next to its blob — the wiring
      // that lets a flow publish union its screens' required libraries. The
      // sidecar is well-formed, hash-tied to the blob it describes, and (for
      // these built-in-only screens) floors at baseline with no custom
      // libraries. A custom-library screen would populate requiredLibraries
      // through the same deriveCapabilityManifest path the paywall e2e proves.
      final sidecarPath =
          'assets/onboarding/screens/${entry.value.path.replaceFirst(
        RegExp(r'\.rfw$'),
        '.capability.json',
      )}';
      final sidecar = CapabilitySidecar.fromJson(
        jsonDecode(_readString(result, sidecarPath)) as Map<String, dynamic>,
      );
      expect(
        sidecar.blobSha256,
        CapabilitySidecar.hashBlob(blob),
        reason: '${entry.key} sidecar hash must tie to its blob',
      );
      expect(sidecar.manifest.builtInFloor, kBaselineCatalogVersion);
      expect(sidecar.manifest.requiredLibraries, isEmpty);
    }

    await _assertGeneratedFixtureAnalyzes(result, sources);
  });
}

const _screens = ['welcome', 'permissions', 'ready'];

const _screenMetadata = {
  'welcome': _ScreenMetadata(
    id: 'welcome',
    artifactPath: 'welcome.rfw',
    version: 1,
    minClient: 1,
    event: 'next',
    className: 'WelcomeScreen',
  ),
  'permissions': _ScreenMetadata(
    id: 'permissions',
    artifactPath: 'permissions.rfw',
    version: 1,
    minClient: 1,
    event: 'next',
    className: 'PermissionsScreen',
  ),
  'ready': _ScreenMetadata(
    id: 'ready',
    artifactPath: 'ready.rfw',
    version: 1,
    minClient: 1,
    event: 'start',
    className: 'ReadyScreen',
  ),
};

final class _ScreenMetadata {
  const _ScreenMetadata({
    required this.id,
    required this.artifactPath,
    required this.version,
    required this.minClient,
    required this.event,
    required this.className,
  });

  final String id;
  final String artifactPath;
  final int version;
  final int minClient;
  final String event;
  final String className;
}

List<int> _readBytes(TestBuilderResult result, String path) {
  return result.readerWriter.testing.readBytes(AssetId('apps_examples', path));
}

String _readString(TestBuilderResult result, String path) {
  return result.readerWriter.testing.readString(AssetId('apps_examples', path));
}

String _readSharedFirstRunGolden() {
  const relativePath =
      'packages/restage_shared/test/flow_document/goldens/first_run.flow.json';
  var directory = Directory.current.absolute;
  while (true) {
    final candidate = File('${directory.path}/$relativePath');
    if (candidate.existsSync()) {
      return candidate.readAsStringSync();
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'Could not find $relativePath from ${Directory.current}',
      );
    }
    directory = parent;
  }
}

Future<TestReaderWriter> _readerWriterWith(Map<String, String> sources) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  for (final entry in sources.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  return readerWriter;
}

Future<void> _assertGeneratedFixtureAnalyzes(
  TestBuilderResult result,
  Map<String, String> sources,
) async {
  final resolvedSources = {
    ...sources,
    for (final screen in _screens)
      'apps_examples|lib/onboarding/screens/$screen.rsscreen.g.dart':
          _readString(result, 'lib/onboarding/screens/$screen.rsscreen.g.dart'),
    'apps_examples|lib/onboarding/flows/first_run.rsflow.g.dart':
        _readString(result, 'lib/onboarding/flows/first_run.rsflow.g.dart'),
    'apps_examples|lib/generated_consumer.dart': '''
import 'package:restage/restage.dart';

import 'onboarding/flows/first_run.dart';
import 'onboarding/screens/permissions.dart';
import 'onboarding/screens/ready.dart';
import 'onboarding/screens/welcome.dart';

void consumeGeneratedDescriptors() {
  const OnboardingFlowRef<FirstRunResult> flow = FirstRunFlowDescriptor.ref;
  const screens = [
    WelcomeScreenDescriptor.ref,
    PermissionsScreenDescriptor.ref,
    ReadyScreenDescriptor.ref,
  ];
  final result = flow.decodeResult({'completed': true});
  if (!result.completed || screens.length != 3) {
    throw StateError('generated descriptors did not compile');
  }
}
''',
  };

  await resolveSources(
    resolvedSources,
    (resolver) async {
      final library = await resolver.libraryFor(
        AssetId('apps_examples', 'lib/generated_consumer.dart'),
      );
      final resolved =
          await library.session.getResolvedLibraryByElement(library);
      if (resolved is! ResolvedLibraryResult) {
        throw StateError('Generated fixture did not resolve.');
      }
      final errors = [
        for (final unit in resolved.units)
          for (final diagnostic in unit.diagnostics)
            if (diagnostic.severity == Severity.error)
              diagnostic.problemMessage.messageText(includeUrl: false),
      ];
      expect(errors, isEmpty);
    },
    resolverFor: 'apps_examples|lib/generated_consumer.dart',
    rootPackage: 'apps_examples',
    readAllSourcesFromFilesystem: true,
  );
}

Map<String, String> _firstRunSources() => {
      'apps_examples|lib/onboarding/screens/welcome.dart':
          _welcomeScreenSource(),
      'apps_examples|lib/onboarding/screens/permissions.dart':
          _screenSource('permissions', 'PermissionsScreen', 'next'),
      'apps_examples|lib/onboarding/screens/ready.dart':
          _screenSource('ready', 'ReadyScreen', 'start'),
      'apps_examples|lib/onboarding/flows/first_run.dart': '''
import 'package:restage/restage.dart';

import '../screens/permissions.dart';
import '../screens/ready.dart';
import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

@OnboardingFlow(id: 'first_run', version: 1, minClient: 3)
final class FirstRunFlow extends RestageFlow {
  static const requestNotifications =
      FlowActionRef<void, NotificationResult>('requestNotifications');

  const FirstRunFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: WelcomeScreenDescriptor.ref,
      flowState: const {
        'completed': FlowStateDeclaration(
          type: FlowDataType.bool,
          classification: FlowStateClassification.exportable,
        ),
        'secret': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.internal,
        ),
      },
      outbound: const FlowOutboundDeclarations(
        terminalResult: FlowOutboundPayloadDeclaration(fields: {
          'completed': FlowOutboundField(
            type: FlowDataType.bool,
            ref: StateFlowOutboundRef(key: 'completed'),
          ),
        }),
        customEvents: {
          'analyticsTap': FlowOutboundPayloadDeclaration(fields: {
            'ctaId': FlowOutboundField(
              type: FlowDataType.string,
              ref: EventFlowOutboundRef(key: 'ctaId'),
            ),
          }),
        },
      ),
      states: [
        screen(WelcomeScreenDescriptor.ref)
            .on(WelcomeScreen.next)
            .goTo(PermissionsScreenDescriptor.ref),
        screen(PermissionsScreenDescriptor.ref)
            .on(PermissionsScreen.next)
            .run(requestNotifications)
            .result((result) => result.granted)
            .goTo(ReadyScreenDescriptor.ref),
        screen(ReadyScreenDescriptor.ref)
            .on(ReadyScreen.start)
            .goTo(done),
        end(done, result: {'completed': true, 'secret': 'internal'}),
      ],
    );
  }
}

final class NotificationResult {
  const NotificationResult({required this.granted});
  final bool granted;
}
''',
    };

String _welcomeScreenSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@OnboardingSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  static const next = OnboardingEvent<void>('next');
  static const analyticsTap =
      OnboardingEvent<Map<String, Object?>>('analyticsTap');

  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: onboardingEvent(
                analyticsTap,
                const {'ctaId': 'primary', 'secret': 'internal'},
              ),
              child: const Text('AnalyticsTap'),
            ),
            ElevatedButton(
              onPressed: onboardingEvent(next),
              child: const Text('WelcomeScreen'),
            ),
          ],
        ),
      );
}
''';

String _screenSource(String id, String className, String eventName) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part '$id.rsscreen.g.dart';

@OnboardingSource(id: '$id')
final class $className extends StatelessWidget {
  static const $eventName = OnboardingEvent<void>('$eventName');

  const $className({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: ElevatedButton(
          onPressed: onboardingEvent($eventName),
          child: const Text('$className'),
        ),
      );
}
''';
