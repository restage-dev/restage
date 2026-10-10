import 'dart:convert';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/src/generated_dart_builder.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_codegen/src/surface_publication/surface_list_builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('lists every generated screen and flow reference of the package',
      () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/announcement.restage.g.dart';

@Screen(surface: Surface.general)
final class FeatureAnnouncement extends StatelessWidget {
  const FeatureAnnouncement({super.key});

  static const dismiss = SurfaceEvent<void>('dismiss');

  @override
  Widget build(BuildContext context) => const Text('Announcement');
}
''';
    const flow = '''
import 'package:restage/restage.dart';

import '../features/announcement.dart';

part 'restage.generated/launch.restage.g.dart';

@FlowGraph(surface: Surface.general)
const launch = FlowDefinition(
  start: FeatureAnnouncement,
  transitions: [
    Transition.complete(FeatureAnnouncement.dismiss),
  ],
);
''';
    final sources = <String, String>{
      'apps_examples|lib/features/announcement.dart': screen,
      'apps_examples|lib/journeys/launch.dart': flow,
    };
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    for (final builder in <Builder>[
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      RestageGeneratedDartBuilder(BuilderOptions.empty),
      const RestageSurfaceListBuilder(),
    ]) {
      final result = await testBuilder(
        builder,
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    }

    final list = readerWriter.testing.readString(
      AssetId('apps_examples', kRestageSurfaceListPath),
    );
    expect(
      list,
      contains(
        "import 'package:apps_examples/features/announcement.dart' as s0;",
      ),
    );
    expect(
      list,
      contains("import 'package:apps_examples/journeys/launch.dart' as s1;"),
    );
    expect(
      list,
      contains('    s0.featureAnnouncementPlacementDefinition(),\n'),
    );
    expect(list, contains('    s1.launchPlacementDefinition(),\n'));
    expect(list, isNot(contains('PaywallRef')));
  });

  test('placement roster carries all four mounts and category-scoped defaults',
      () async {
    const sourceId = 'apps_examples|lib/mounts.dart';
    const partPath = 'lib/restage.generated/mounts.restage.g.dart';
    const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/mounts.restage.g.dart';

@Paywall(id: 'shared', presentation: SurfacePresentationRequirement.inline)
final class PremiumOffer extends StatelessWidget {
  const PremiumOffer(this.placement, [this.restagePlacementId = 'authored-id']);
  final String placement;
  final String restagePlacementId;
  @override
  Widget build(BuildContext context) => Text(placement);
}

@Screen(id: 'shared', surface: Surface.general)
final class Notice extends StatelessWidget {
  const Notice({this.title, super.key});
  final String? title;
  static const dismiss = SurfaceEvent<void>('dismiss');
  @override
  Widget build(BuildContext context) => const Text('Notice');
}

@Screen(id: 'profile')
final class ProfileStep extends StatelessWidget {
  const ProfileStep(this.name, {super.key});
  final String name;
  static const submit = SurfaceEvent<void>('submit');
  @override
  Widget build(BuildContext context) => Text(name);
}

const journeyCount = SeedableFlowStateRef<int>('count', defaultValue: 7);

@FlowGraph(id: 'typed_journey', surface: Surface.onboarding)
const typedJourney = FlowDefinition(
  start: ProfileStep,
  state: [journeyCount],
  transitions: [Transition.complete(ProfileStep.submit, result: {'count': 7})],
  outbound: FlowOutboundPolicy(terminalResult: {'count': journeyCount}),
);

@FlowGraph(id: 'general_journey', surface: Surface.general,
  delivery: FlowDeliveryMode.general)
const generalJourney = FlowDefinition(
  start: Notice,
  transitions: [Transition.complete(Notice.dismiss)],
);
''';
    final sources = <String, String>{sourceId: source};
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    for (final builder in <Builder>[
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      RestageGeneratedDartBuilder(BuilderOptions.empty),
      const RestageSurfaceListBuilder(),
    ]) {
      final result = await testBuilder(
        builder,
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    }
    final generated = readerWriter.testing.readString(
      AssetId('apps_examples', partPath),
    );
    final list = readerWriter.testing.readString(
      AssetId('apps_examples', kRestageSurfaceListPath),
    );
    for (final name in [
      'premiumOffer',
      'notice',
      'typedJourney',
      'generalJourney',
    ]) {
      expect(
        RegExp('s0\\.${name}PlacementDefinition\\(\\)').allMatches(list),
        hasLength(1),
      );
    }
    expect(list, isNot(contains('PaywallRef')));
    expect(list, isNot(contains('JourneyRef,')));
    expect(
      RegExp(r'=\s*Restage(?:Paywall|Screen|FlowGraph)'
              r'.generatedPlacementDefinition\(')
          .allMatches(generated),
      hasLength(4),
    );
    expect(RegExp('hostContractJson:').allMatches(generated), hasLength(4));
    expect(generated, contains("'surfaceType': 'paywall'"));
    expect(generated, contains("'surfaceType': 'general'"));
    expect(RegExp("'slug': 'shared'").allMatches(generated), hasLength(2));
    expect(generated, contains("'contractVersion': 1"));
    expect(
      generated,
      contains('required CompiledFlowScreenBuilder profileScreenBuilder,'),
    );
    expect(generated, contains('final class TypedJourneyResult'));
    expect(generated, contains('final int count;'));
    expect(generated, contains('const GeneralJourneySurface.atPlacement('));
    expect(generated, contains('String restagePlacementId2,'));
    final contracts = _emittedHostContracts(generated);
    expect(
      contracts.keys,
      unorderedEquals(
        ['premiumOffer', 'notice', 'typedJourney', 'generalJourney'],
      ),
    );
    for (final contract in contracts.values) {
      expect(contract.hosting.presentation, SurfacePresentationV1.inline);
      expect(
        SurfaceHostContractV1.fromJson(contract.toJson()).contentHash,
        contract.contentHash,
      );
    }
    expect(
      contracts['notice']!.hosting.contentKind,
      SurfaceContentKindV1.single,
    );
    expect(
      contracts['notice']!.providedContext.toJson(),
      SurfaceScreenHostDataSchema(const {
        'title': SurfaceScreenHostDataNullableShapeV1(
          SurfaceScreenHostDataScalarShapeV1(
            SurfaceScreenHostDataScalarKind.string,
          ),
        ),
      }).toJson(),
    );
    expect(
      contracts['notice']!.handledEvents.events.map((event) => event.id),
      ['dismiss'],
    );
    expect(
      contracts['premiumOffer']!.providedContext.inputs.keys,
      ['placement', 'restagePlacementId'],
    );
    expect(contracts['premiumOffer']!.handledEvents.events, isEmpty);
    expect(
      contracts['typedJourney']!.hosting.contentKind,
      SurfaceContentKindV1.flow,
    );
    expect(
      contracts['typedJourney']!.flowBoundary!.deliveryMode,
      FlowDeliveryMode.typed,
    );
    expect(
      contracts['typedJourney']!.flowBoundary!.outbound.terminalResult,
      {'count': FlowDataType.int},
    );
    expect(
      contracts['generalJourney']!.flowBoundary!.deliveryMode,
      FlowDeliveryMode.general,
    );
    final bundle = RestageSurfacePublicationBundle.fromJson(
      jsonDecode(
        readerWriter.testing.readString(
          AssetId(
            'apps_examples',
            kRestageSurfacePublicationCompilerBundlePath,
          ),
        ),
      ),
    );
    expect(bundle.valid, isTrue);
    expect(bundle.manifest!.publications, hasLength(4));
    expect(
      bundle.manifest!.publications
          .singleWhere(
            (entry) => entry.publication.surface.wireName == 'paywall',
          )
          .publication
          .mountName,
      'PremiumOfferSurface',
    );
    await resolveWorkspaceSources(
      {
        sourceId: '''
$source
Widget buildProfile() => const ProfileStep('Casey');
void completeTyped(TypedJourneyResult result) {}
const paywallOriginal = PremiumOfferSurface('authored');
const paywallNamed = PremiumOfferSurface.atPlacement('upgrade_card', 'authored', 'authored-id');
const screenOriginal = NoticeSurface();
const screenNamed = NoticeSurface(placement: 'settings_card', title: 'Settings');
const screenUniversal = NoticeSurface.atPlacement('profile_card', title: 'Profile');
final typedOriginal = TypedJourneySurface(profileScreenBuilder: buildProfile, onComplete: completeTyped);
final typedNamed = TypedJourneySurface.atPlacement('profile_flow', profileScreenBuilder: buildProfile, onComplete: completeTyped);
const generalOriginal = GeneralJourneySurface();
const generalNamed = GeneralJourneySurface.atPlacement('home_flow');
''',
        'apps_examples|$partPath': generated,
        'apps_examples|$kRestageSurfaceListPath': list,
      },
      (resolver) async {
        for (final path in ['lib/mounts.dart', kRestageSurfaceListPath]) {
          final library =
              await resolver.libraryFor(AssetId('apps_examples', path));
          final resolved =
              await library.session.getResolvedLibraryByElement(library);
          expect(resolved, isA<ResolvedLibraryResult>());
          expect(
            [
              for (final unit in (resolved as ResolvedLibraryResult).units)
                for (final diagnostic in unit.diagnostics)
                  if (diagnostic.severity == Severity.error ||
                      (unit.path.endsWith(partPath) &&
                          diagnostic.severity == Severity.warning))
                    diagnostic.problemMessage.messageText(includeUrl: false),
            ],
            isEmpty,
            reason: path,
          );
          if (path == 'lib/mounts.dart') {
            for (final entry in const <String, String?>{
              'paywallOriginal': null,
              'paywallNamed': 'upgrade_card',
              'screenOriginal': null,
              'screenNamed': 'settings_card',
              'screenUniversal': 'profile_card',
              'generalOriginal': null,
              'generalNamed': 'home_flow',
            }.entries) {
              final value = library.topLevelVariables
                  .singleWhere((variable) => variable.name == entry.key)
                  .computeConstantValue();
              expect(value, isNotNull, reason: entry.key);
              expect(
                value!.getField('_restagePlacementName')!.toStringValue(),
                entry.value,
                reason: entry.key,
              );
            }
            final paywall = library.topLevelVariables
                .singleWhere((variable) => variable.name == 'paywallOriginal')
                .computeConstantValue()!;
            expect(
              paywall.getField('_restageArgument0')!.toStringValue(),
              'authored',
            );
            expect(
              paywall.getField('_restageArgument1')!.toStringValue(),
              'authored-id',
            );
          }
        }
      },
      resolverFor: sourceId,
      rootPackage: 'apps_examples',
    );
  });

  test('paywall host kind follows its actual compiled navigation flow',
      () async {
    const sourceId = 'apps_examples|lib/paywall_hosts.dart';
    const partPath = 'lib/restage.generated/paywall_hosts.restage.g.dart';
    const source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/paywall_hosts.restage.g.dart';

@Paywall(id: 'single')
final class SingleOffer extends StatelessWidget {
  const SingleOffer({super.key});
  @override
  Widget build(BuildContext context) => const Text('Single');
}

@Paywall(id: 'entry')
final class EntryPaywall extends StatelessWidget {
  const EntryPaywall({super.key});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      ElevatedButton(
        onPressed: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(builder: (_) => const PublishedOffer()),
        ),
        child: const Text('Choose'),
      ),
      ElevatedButton(
        onPressed: paywallEvent('skip'),
        child: const Text('Skip'),
      ),
    ],
  );
}

@Paywall(id: 'offer')
final class PublishedOffer extends StatelessWidget {
  const PublishedOffer({super.key});
  @override
  Widget build(BuildContext context) => ElevatedButton(
    onPressed: () => Navigator.pop(context),
    child: const Text('Back'),
  );
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    for (final builder in <Builder>[
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      RestageGeneratedDartBuilder(BuilderOptions.empty),
    ]) {
      final result = await testBuilder(
        builder,
        const {sourceId: source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    }
    final generated = readerWriter.testing.readString(
      AssetId('apps_examples', partPath),
    );
    final contracts = _emittedHostContracts(generated);
    expect(
      contracts['singleOffer']!.hosting.contentKind,
      SurfaceContentKindV1.single,
    );
    expect(contracts['singleOffer']!.flowBoundary, isNull);
    final flowHost = contracts['entryPaywall']!;
    expect(flowHost.hosting.contentKind, SurfaceContentKindV1.flow);
    expect(flowHost.hosting.presentation, SurfacePresentationV1.inline);
    final bundle = RestageSurfacePublicationBundle.fromJson(
      jsonDecode(
        readerWriter.testing.readString(
          AssetId(
            'apps_examples',
            kRestageSurfacePublicationCompilerBundlePath,
          ),
        ),
      ),
    );
    final publication = bundle.manifest!.publications.singleWhere(
      (entry) => entry.publication.slug == 'entry',
    );
    expect(publication.publication.payloadKind, SurfacePayloadKind.flow);
    final documentPath = publication.artifacts
        .singleWhere(
          (artifact) =>
              artifact.role == SurfacePublicationArtifactRole.flowDocument,
        )
        .path;
    final document = FlowDocumentCodec.decodeJson(
      utf8.decode(bundle.artifacts[documentPath]!),
    );
    expect(
      flowHost.flowBoundary!.toJson(),
      FlowHostBoundaryV1.fromDocument(
        document,
        signals: document.outbound.customEvents.keys.toSet(),
      ).toJson(),
    );
  });

  test('emits paywalls by id and references in a stable order', () {
    final source = emitRestageSurfaceList(
      package: 'app',
      paywallIds: const ['pro'],
      refs: const [
        SurfaceListReference(libraryPath: 'lib/b.dart', name: 'zRef'),
        SurfaceListReference(libraryPath: 'lib/a.dart', name: 'yRef'),
        SurfaceListReference(libraryPath: 'lib/b.dart', name: 'aRef'),
      ],
    );
    expect(
      source,
      endsWith('''
import 'package:restage/restage.dart' as restage;
import 'package:app/a.dart' as s0;
import 'package:app/b.dart' as s1;

/// Every surface this package compiles, for
/// `Restage.configure(surfaces: restageSurfaces)`.
final List<restage.RestageSurfaceRef> restageSurfaces =
    List<restage.RestageSurfaceRef>.unmodifiable(
  <restage.RestageSurfaceRef>[
    const restage.PaywallRef('pro'),
    s0.yRef,
    s1.aRef,
    s1.zRef,
  ],
);
'''),
    );
  });
}

Map<String, SurfaceHostContractV1> _emittedHostContracts(String generated) {
  final result = <String, SurfaceHostContractV1>{};
  final parsed = parseString(content: generated);
  expect(parsed.errors, isEmpty);
  for (final declaration
      in parsed.unit.declarations.whereType<TopLevelVariableDeclaration>()) {
    for (final variable in declaration.variables.variables) {
      final initializer = variable.initializer;
      if (initializer is! MethodInvocation ||
          initializer.methodName.name != 'generatedPlacementDefinition') {
        continue;
      }
      final argument = initializer.argumentList.arguments
          .whereType<NamedArgument>()
          .singleWhere(
            (argument) => argument.name.lexeme == 'hostContractJson',
          );
      final name = variable.name.lexeme;
      final key = name.substring(
        1,
        name.length - 'PlacementDefinitionValue'.length,
      );
      result[key] = SurfaceHostContractV1.fromJson(
        _literalValue(argument.argumentExpression),
      );
    }
  }
  return result;
}

Object? _literalValue(Expression expression) => switch (expression) {
      NullLiteral() => null,
      StringLiteral(:final stringValue) => stringValue,
      IntegerLiteral(:final value) => value,
      BooleanLiteral(:final value) => value,
      ListLiteral(:final elements) => [
          for (final element in elements) _literalValue(element as Expression),
        ],
      SetOrMapLiteral(:final elements) => {
          for (final entry in elements.cast<MapLiteralEntry>())
            _literalValue(entry.key)! as String: _literalValue(entry.value),
        },
      _ =>
        throw StateError('Expected an emitted metadata literal: $expression'),
    };
