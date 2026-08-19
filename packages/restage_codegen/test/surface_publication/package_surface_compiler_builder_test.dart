import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/surface_publication/dynamic_output_owner.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('compiles tracked arbitrary-directory sources into the fixed bundle',
      () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'announcement.rsscreen.g.dart';

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

part 'launch.rsflow.g.dart';

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
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final encoded = readerWriter.testing.readString(
      AssetId(
        'apps_examples',
        kRestageSurfacePublicationCompilerBundlePath,
      ),
    );
    final bundle = RestageSurfacePublicationBundle.fromJson(
      jsonDecode(encoded),
    );
    expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
    expect(
      bundle.manifest!.publications
          .map((entry) => entry.publication.slug)
          .toList(),
      orderedEquals(['announcement', 'launch']),
    );
    expect(
      bundle.artifacts.keys,
      containsAll(<String>[
        'assets/general/screens/announcement.rfw',
        'assets/general/screens/announcement.capability.json',
        'assets/general/flows/launch.flow.json',
      ]),
    );
    expect(
      bundle.ownedOutputs.keys,
      containsAll(<String>[
        'assets/general/screens/announcement.rfwtxt',
        'lib/features/announcement.rsscreen.g.dart',
        'lib/journeys/launch.rsflow.g.dart',
      ]),
    );
    expect(
      utf8.decode(
        bundle.ownedOutputs['assets/general/screens/announcement.rfwtxt']!,
      ),
      contains('"Announcement"'),
    );
    expect(
      utf8.decode(
        bundle.ownedOutputs['lib/features/announcement.rsscreen.g.dart']!,
      ),
      contains('SurfaceScreenRef<FeatureAnnouncementEvent>'),
    );
    expect(
      utf8.decode(
        bundle.ownedOutputs['lib/journeys/launch.rsflow.g.dart']!,
      ),
      contains('SurfaceFlowRef<LaunchResult>'),
    );
  });

  test('materializes one neutral screen for two containing flow surfaces',
      () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

@Screen()
final class Welcome extends StatelessWidget {
  const Welcome({super.key});
  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Welcome');
}
''';
    const onboardingFlow = '''
import 'package:restage/restage.dart';
import '../shared/welcome.dart';
part 'onboarding.rsflow.g.dart';

@FlowGraph(surface: Surface.onboarding)
const onboarding = FlowDefinition(
  start: Welcome,
  transitions: [Transition.complete(Welcome.finish)],
);
''';
    const messageFlow = '''
import 'package:restage/restage.dart';
import '../shared/welcome.dart';
part 'message.rsflow.g.dart';

@FlowGraph(surface: Surface.message)
const message = FlowDefinition(
  start: Welcome,
  transitions: [Transition.complete(Welcome.finish)],
);
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      <String, String>{
        'apps_examples|lib/shared/welcome.dart': screen,
        'apps_examples|lib/journeys/onboarding.dart': onboardingFlow,
        'apps_examples|lib/journeys/message.dart': messageFlow,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
    const onboardingBlob = 'assets/onboarding/screens/welcome.rfw';
    const messageBlob = 'assets/message/screens/welcome.rfw';
    expect(bundle.artifacts, containsPair(onboardingBlob, isNotEmpty));
    expect(bundle.artifacts, containsPair(messageBlob, isNotEmpty));
    expect(bundle.artifacts[onboardingBlob], bundle.artifacts[messageBlob]);
    expect(
      bundle.manifest!.publications
          .map((entry) => entry.publication.slug)
          .toList(),
      orderedEquals(['message', 'onboarding']),
      reason: 'a neutral screen is flow-owned, never standalone',
    );
  });

  test('compiles colocated explicit paywalls without a generated part',
      () async {
    const paywalls = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall(id: 'upgrade_offer')
final class FirstOffer extends StatelessWidget {
  const FirstOffer({super.key});

  @override
  Widget build(BuildContext context) => const Text('Upgrade');
}

@Paywall(id: 'retention_offer')
final class SecondOffer extends StatelessWidget {
  const SecondOffer({super.key});

  @override
  Widget build(BuildContext context) => const Text('Stay');
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const <String, String>{
        'apps_examples|lib/features/commerce/offers.dart': paywalls,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
    expect(
      bundle.manifest!.publications
          .map((entry) => entry.publication.slug)
          .toList(),
      orderedEquals(['retention_offer', 'upgrade_offer']),
    );
    expect(
      bundle.ownedOutputs.keys.where((path) => path.endsWith('.g.dart')),
      isEmpty,
    );
    expect(
      bundle.artifacts.keys,
      containsAll(<String>[
        'assets/paywalls/retention_offer.rfw',
        'assets/paywalls/upgrade_offer.rfw',
      ]),
    );
  });

  test('publishes a canonical class-shaped advanced flow', () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
part 'welcome.rsscreen.g.dart';

@Screen()
final class Welcome extends StatelessWidget {
  const Welcome({super.key});
  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Welcome');
}
''';
    const flow = '''
import 'package:restage/restage.dart';
import '../shared/welcome.dart';
part 'complex.rsflow.g.dart';

@FlowGraph(surface: Surface.general)
final class Complex extends RestageFlow {
  const Complex();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: WelcomeDescriptor.ref,
      states: [
        screen(WelcomeDescriptor.ref).on(Welcome.finish).goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const <String, String>{
        'apps_examples|lib/shared/welcome.dart': screen,
        'apps_examples|lib/journeys/complex.dart': flow,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
    expect(
      bundle.manifest!.publications.single.publication.slug,
      'complex',
    );
    expect(
      utf8.decode(bundle.artifacts['assets/general/flows/complex.flow.json']!),
      contains('"flow":"complex"'),
    );
    expect(
      utf8.decode(bundle.ownedOutputs['lib/journeys/complex.rsflow.g.dart']!),
      contains('SurfaceFlowRef<ComplexResult>'),
    );
  });

  test('adapts a legacy-only package as borrowed exact artifacts', () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
part 'welcome.rsscreen.g.dart';

@ScreenSource(id: 'welcome', version: 1, minClient: 1)
final class Welcome extends StatelessWidget {
  const Welcome({super.key});
  static const finish = OnboardingEvent<String>('finish');

  @override
  Widget build(BuildContext context) => const Text('Welcome');
}
''';
    const flow = '''
import 'package:restage/restage.dart';
import '../screens/welcome.dart';
part 'welcome_flow.rsflow.g.dart';

@FlowSource(id: 'welcome_flow', version: 1, minClient: 1)
final class WelcomeFlow extends RestageFlow {
  const WelcomeFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: WelcomeDescriptor.ref,
      states: [
        screen(WelcomeDescriptor.ref).on(Welcome.finish).goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilders(
      [
        onboardingScreenBuilder(BuilderOptions.empty),
        onboardingFlowBuilder(BuilderOptions.empty),
        const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      ],
      const <String, String>{
        'apps_examples|lib/onboarding/screens/welcome.dart': screen,
        'apps_examples|lib/onboarding/flows/welcome_flow.dart': flow,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
    expect(bundle.artifacts, isEmpty);
    expect(
      bundle.borrowedArtifacts.keys,
      containsAll(<String>[
        'assets/onboarding/screens/welcome.rfw',
        'assets/onboarding/screens/welcome.capability.json',
        'assets/onboarding/flows/welcome_flow.flow.json',
      ]),
      reason: 'the aggregate validates legacy closure bytes without '
          'claiming a second writer',
    );
    expect(
      bundle.manifest!.publications
          .map((entry) => entry.publication.slug)
          .toList(),
      orderedEquals(['welcome', 'welcome_flow']),
    );
    final legacyScreen = bundle.manifest!.publications.singleWhere(
      (entry) => entry.publication.slug == 'welcome',
    );
    expect(
      legacyScreen.publication.eventContract!.events.single.arguments,
      isA<SurfaceScreenEventValueArgumentsV1>().having(
        (arguments) => arguments.shape,
        'shape',
        isA<SurfaceScreenEventScalarShapeV1>().having(
          (shape) => shape.kind,
          'kind',
          SurfaceScreenEventScalarKindV1.string,
        ),
      ),
      reason: 'typedef-resolved legacy events retain the strict schema',
    );
  });

  test(
      'keeps same-named advanced-flow screens distinct by resolved library '
      'and surface', () async {
    const onboardingScreen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'onboarding_welcome.rsscreen.g.dart';

@Screen(id: 'welcome', surface: Surface.onboarding)
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Onboarding welcome');
}
''';
    const messageScreen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'message_welcome.rsscreen.g.dart';

@Screen(id: 'welcome', surface: Surface.message)
final class Welcome extends StatelessWidget {
  const Welcome({super.key});

  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Message welcome');
}
''';
    const onboardingFlow = '''
import 'package:restage/restage.dart';

import '../screens/onboarding_welcome.dart' as onboarding;

part 'onboarding_advanced.rsflow.g.dart';

@FlowGraph(id: 'onboarding_advanced', surface: Surface.onboarding)
final class OnboardingAdvanced extends RestageFlow {
  const OnboardingAdvanced();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: onboarding.WelcomeDescriptor.ref,
      states: [
        screen(onboarding.WelcomeDescriptor.ref)
            .on(onboarding.Welcome.finish)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
''';
    const messageFlow = '''
import 'package:restage/restage.dart';

import '../screens/message_welcome.dart' as message;

part 'message_advanced.rsflow.g.dart';

@FlowGraph(id: 'message_advanced', surface: Surface.message)
final class MessageAdvanced extends RestageFlow {
  const MessageAdvanced();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: message.WelcomeDescriptor.ref,
      states: [
        screen(message.WelcomeDescriptor.ref)
            .on(message.Welcome.finish)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const <String, String>{
        'apps_examples|lib/screens/onboarding_welcome.dart': onboardingScreen,
        'apps_examples|lib/screens/message_welcome.dart': messageScreen,
        'apps_examples|lib/flows/onboarding_advanced.dart': onboardingFlow,
        'apps_examples|lib/flows/message_advanced.dart': messageFlow,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    const onboardingBlob = 'assets/onboarding/screens/welcome.rfw';
    const messageBlob = 'assets/message/screens/welcome.rfw';
    expect(
      bundle.artifacts[onboardingBlob],
      isNot(equals(bundle.artifacts[messageBlob])),
    );
    final onboardingDocument = FlowDocumentCodec.decodeJson(
      utf8.decode(
        bundle.artifacts[
            'assets/onboarding/flows/onboarding_advanced.flow.json']!,
      ),
    );
    final messageDocument = FlowDocumentCodec.decodeJson(
      utf8.decode(
        bundle.artifacts['assets/message/flows/message_advanced.flow.json']!,
      ),
    );
    expect(onboardingDocument.screenArtifacts.keys, orderedEquals(['welcome']));
    expect(messageDocument.screenArtifacts.keys, orderedEquals(['welcome']));
    expect(
      onboardingDocument.screenArtifacts['welcome']!.contentHash,
      isNot(equals(messageDocument.screenArtifacts['welcome']!.contentHash)),
    );
  });

  test(
      'admits canonical libraries under generated while excluding generated '
      'and story Dart', () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'notice.rsscreen.g.dart';

@Screen(id: 'generated_notice', surface: Surface.general)
final class GeneratedNotice extends StatelessWidget {
  const GeneratedNotice({super.key});

  @override
  Widget build(BuildContext context) => const Text('Retained authored source');
}
''';
    const ignored = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Screen(id: 'ignored', surface: Surface.general)
final class Ignored extends StatelessWidget {
  const Ignored({super.key});

  @override
  Widget build(BuildContext context) => const Text('This must not be scanned');
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const <String, String>{
        'apps_examples|lib/generated/notice.dart': screen,
        'apps_examples|lib/generated/ignored.g.dart': ignored,
        'apps_examples|lib/generated/ignored.stories.dart': ignored,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    expect(
      bundle.manifest!.publications
          .map((entry) => entry.publication.slug)
          .toList(),
      orderedEquals(['generated_notice']),
    );
    expect(
      bundle.artifacts,
      contains('assets/general/screens/generated_notice.rfw'),
    );
    expect(
      bundle.artifacts,
      isNot(contains('assets/general/screens/ignored.rfw')),
    );
  });

  test('propagates authored standalone minClient above a derived floor',
      () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'minimum_notice.rsscreen.g.dart';

@Screen(id: 'minimum_notice', surface: Surface.general, minClient: 3)
final class MinimumNotice extends StatelessWidget {
  const MinimumNotice({super.key});

  @override
  Widget build(BuildContext context) => const Text('Minimum client');
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const <String, String>{
        'apps_examples|lib/features/minimum_notice.dart': screen,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    final publication = bundle.manifest!.publications.single.publication;
    expect(publication.capabilities!.builtInFloor, 3);
    final sidecar = jsonDecode(
      utf8.decode(
        bundle.artifacts[
            'assets/general/screens/minimum_notice.capability.json']!,
      ),
    ) as Map<String, Object?>;
    expect((sidecar['manifest']! as Map<Object?, Object?>)['builtInFloor'], 3);
    final generatedPart = utf8.decode(
      bundle.ownedOutputs['lib/features/minimum_notice.rsscreen.g.dart']!,
    );
    expect(generatedPart, contains('builtInFloor: 3'));
    expect(generatedPart, contains('minClient: 3'));
  });

  test('propagates authored embedded-screen minClient into the flow document',
      () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'minimum_notice.rsscreen.g.dart';

@Screen(id: 'minimum_notice', minClient: 3)
final class MinimumNotice extends StatelessWidget {
  const MinimumNotice({super.key});

  static const finish = SurfaceEvent<void>('finish');

  @override
  Widget build(BuildContext context) => const Text('Minimum client');
}
''';
    const flow = '''
import 'package:restage/restage.dart';

import '../screens/minimum_notice.dart' as notice;

part 'minimum_flow.rsflow.g.dart';

@FlowGraph(id: 'minimum_flow', surface: Surface.general, minClient: 3)
final class MinimumFlow extends RestageFlow {
  const MinimumFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: notice.MinimumNoticeDescriptor.ref,
      states: [
        screen(notice.MinimumNoticeDescriptor.ref)
            .on(notice.MinimumNotice.finish)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const <String, String>{
        'apps_examples|lib/screens/minimum_notice.dart': screen,
        'apps_examples|lib/flows/minimum_flow.dart': flow,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    final document = FlowDocumentCodec.decodeJson(
      utf8.decode(
        bundle.artifacts['assets/general/flows/minimum_flow.flow.json']!,
      ),
    );
    expect(document.minClient, 3);
    expect(document.screenArtifacts['minimum_notice']!.minClient, 3);
    final sidecar = jsonDecode(
      utf8.decode(
        bundle.artifacts[
            'assets/general/screens/minimum_notice.capability.json']!,
      ),
    ) as Map<String, Object?>;
    expect((sidecar['manifest']! as Map<Object?, Object?>)['builtInFloor'], 3);
  });

  test(
      'scheduler accepts a flat flow whose aggregate floor exceeds its '
      'authored screen reference floor', () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'derived_floor.rsscreen.g.dart';

@Screen(id: 'derived_floor', minClient: 1)
final class DerivedFloor extends StatelessWidget {
  const DerivedFloor({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) =>
      const Offstage(child: Text('Derived floor'));
}
''';
    const flatFlow = '''
import 'package:restage/restage.dart';

import '../screens/derived_floor.dart';

part 'flat_floor.rsflow.g.dart';

@FlowGraph(id: 'flat_floor', surface: Surface.general, minClient: 1)
const flatFloor = FlowDefinition(
  start: DerivedFloor,
  transitions: [Transition.complete(DerivedFloor.next)],
);
''';
    const advancedFlow = '''
import 'package:restage/restage.dart';

import '../screens/derived_floor.dart';

part 'advanced_trigger.rsflow.g.dart';

@FlowGraph(id: 'advanced_trigger', surface: Surface.general, minClient: 5)
final class AdvancedTrigger extends RestageFlow {
  const AdvancedTrigger();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: DerivedFloorDescriptor.ref,
      states: [
        screen(DerivedFloorDescriptor.ref)
            .on(DerivedFloor.next)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const <String, String>{
        'apps_examples|lib/screens/derived_floor.dart': screen,
        'apps_examples|lib/flows/flat_floor.dart': flatFlow,
        'apps_examples|lib/flows/advanced_trigger.dart': advancedFlow,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    final sidecar = jsonDecode(
      utf8.decode(
        bundle
            .artifacts['assets/general/screens/derived_floor.capability.json']!,
      ),
    ) as Map<String, Object?>;
    final effectiveFloor =
        (sidecar['manifest']! as Map<Object?, Object?>)['builtInFloor']! as int;
    expect(effectiveFloor, greaterThan(1));
    final flatDocument = FlowDocumentCodec.decodeJson(
      utf8.decode(
        bundle.artifacts['assets/general/flows/flat_floor.flow.json']!,
      ),
    );
    expect(flatDocument.minClient, effectiveFloor);
    expect(
      flatDocument.screenArtifacts['derived_floor']!.minClient,
      effectiveFloor,
    );
    expect(
      bundle.manifest!.publications
          .map((entry) => entry.publication.slug)
          .toList(),
      orderedEquals(['advanced_trigger', 'flat_floor']),
    );
    expect(
      bundle.artifacts,
      contains('assets/general/flows/flat_floor.flow.json'),
    );
  });

  test(
      'advanced parent consumes an arbitrary-path canonical flat child '
      'document by normalized identity', () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'shared_entry.rsscreen.g.dart';

@Screen(id: 'shared_entry')
final class SharedEntry extends StatelessWidget {
  const SharedEntry({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => const Text('Shared entry');
}
''';
    const child = '''
import 'package:restage/restage.dart';

import '../ui/shared_entry.dart';

part 'flat_leaf.rsflow.g.dart';

@FlowGraph(id: 'flat_leaf', surface: Surface.general)
const flatLeaf = FlowDefinition(
  start: SharedEntry,
  transitions: [Transition.complete(SharedEntry.next)],
);
''';
    const parent = '''
import 'package:restage/restage.dart';

import '../ui/shared_entry.dart';

part 'flat_parent.rsflow.g.dart';

Map<String, Object?> _decodeFlatLeaf(Map<String, Object?> result) => result;

const flatLeafRef = SurfaceFlowRef<Map<String, Object?>>(
  id: 'flat_leaf',
  version: 1,
  minClient: 1,
  surface: Surface.general,
  decodeResult: _decodeFlatLeaf,
);

@FlowGraph(id: 'flat_parent', surface: Surface.general)
final class FlatParent extends RestageFlow {
  const FlatParent();

  @override
  FlowDef buildFlow() {
    final child = flowNode('child');
    final done = endState('done');
    return flow(
      initial: SharedEntryDescriptor.ref,
      states: [
        screen(SharedEntryDescriptor.ref).on(SharedEntry.next).goTo(child),
        subFlow(
          child,
          flow: flatLeafRef,
          input: const {},
          onComplete: [
            flowBranch(
              when: const FlowBranchPredicate(fields: {}),
              target: done,
            ),
          ],
          defaultBranch: flowBranchTarget(done),
        ),
        end(done, result: {}),
      ],
    );
  }
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const <String, String>{
        'apps_examples|lib/ui/shared_entry.dart': screen,
        'apps_examples|lib/z_children/flat_leaf.dart': child,
        'apps_examples|lib/a_parents/flat_parent.dart': parent,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    final childBytes =
        bundle.artifacts['assets/general/flows/flat_leaf.flow.json']!;
    final parentDocument = FlowDocumentCodec.decodeJson(
      utf8.decode(
        bundle.artifacts['assets/general/flows/flat_parent.flow.json']!,
      ),
    );
    final childState = parentDocument.states['child']! as SubFlowState;
    expect(childState.flow, 'flat_leaf');
    expect(childState.contentHash, FlowContentHash.compute(childBytes));
  });

  test(
      'advanced parent consumes an arbitrary-path canonical advanced child '
      'document by normalized identity', () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'advanced_entry.rsscreen.g.dart';

@Screen(id: 'advanced_entry')
final class AdvancedEntry extends StatelessWidget {
  const AdvancedEntry({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => const Text('Advanced entry');
}
''';
    const child = '''
import 'package:restage/restage.dart';

import '../ui/advanced_entry.dart';

part 'advanced_leaf.rsflow.g.dart';

@FlowGraph(id: 'advanced_leaf', surface: Surface.general)
final class AdvancedLeaf extends RestageFlow {
  const AdvancedLeaf();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: AdvancedEntryDescriptor.ref,
      states: [
        screen(AdvancedEntryDescriptor.ref)
            .on(AdvancedEntry.next)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
''';
    const parent = '''
import 'package:restage/restage.dart';

import '../ui/advanced_entry.dart';

part 'advanced_parent.rsflow.g.dart';

Map<String, Object?> _decodeAdvancedLeaf(Map<String, Object?> result) => result;

const advancedLeafRef = SurfaceFlowRef<Map<String, Object?>>(
  id: 'advanced_leaf',
  version: 1,
  minClient: 1,
  surface: Surface.general,
  decodeResult: _decodeAdvancedLeaf,
);

@FlowGraph(id: 'advanced_parent', surface: Surface.general)
final class AdvancedParent extends RestageFlow {
  const AdvancedParent();

  @override
  FlowDef buildFlow() {
    final child = flowNode('child');
    final done = endState('done');
    return flow(
      initial: AdvancedEntryDescriptor.ref,
      states: [
        screen(AdvancedEntryDescriptor.ref).on(AdvancedEntry.next).goTo(child),
        subFlow(
          child,
          flow: advancedLeafRef,
          input: const {},
          onComplete: [
            flowBranch(
              when: const FlowBranchPredicate(fields: {}),
              target: done,
            ),
          ],
          defaultBranch: flowBranchTarget(done),
        ),
        end(done, result: {}),
      ],
    );
  }
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const <String, String>{
        'apps_examples|lib/ui/advanced_entry.dart': screen,
        'apps_examples|lib/z_arbitrary/advanced_leaf.dart': child,
        'apps_examples|lib/a_arbitrary/advanced_parent.dart': parent,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    final childBytes =
        bundle.artifacts['assets/general/flows/advanced_leaf.flow.json']!;
    final parentDocument = FlowDocumentCodec.decodeJson(
      utf8.decode(
        bundle.artifacts['assets/general/flows/advanced_parent.flow.json']!,
      ),
    );
    final childState = parentDocument.states['child']! as SubFlowState;
    expect(childState.flow, 'advanced_leaf');
    expect(childState.contentHash, FlowContentHash.compute(childBytes));
  });

  test('rejects a same-id cross-surface child from an advanced parent',
      () async {
    const screen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'cross_surface_entry.rsscreen.g.dart';

@Screen(id: 'cross_surface_entry')
final class CrossSurfaceEntry extends StatelessWidget {
  const CrossSurfaceEntry({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => const Text('Cross surface entry');
}
''';
    const onboardingChild = '''
import 'package:restage/restage.dart';
import 'shared/cross_surface_entry.dart';
part 'onboarding_child.rsflow.g.dart';

@FlowGraph(id: 'shared_child', surface: Surface.onboarding)
const onboardingChild = FlowDefinition(
  start: CrossSurfaceEntry,
  transitions: [Transition.complete(CrossSurfaceEntry.next)],
);
''';
    const messageChild = '''
import 'package:restage/restage.dart';
import 'shared/cross_surface_entry.dart';
part 'message_child.rsflow.g.dart';

@FlowGraph(id: 'shared_child', surface: Surface.message)
const messageChild = FlowDefinition(
  start: CrossSurfaceEntry,
  transitions: [Transition.complete(CrossSurfaceEntry.next)],
);
''';
    const parent = '''
import 'package:restage/restage.dart';
import 'shared/cross_surface_entry.dart';
part 'cross_surface_parent.rsflow.g.dart';

Map<String, Object?> _decodeChild(Map<String, Object?> result) => result;

const messageChildRef = SurfaceFlowRef<Map<String, Object?>>(
  id: 'shared_child',
  version: 1,
  minClient: 1,
  surface: Surface.message,
  decodeResult: _decodeChild,
);

@FlowGraph(id: 'cross_surface_parent', surface: Surface.onboarding)
final class CrossSurfaceParent extends RestageFlow {
  const CrossSurfaceParent();

  @override
  FlowDef buildFlow() {
    final child = flowNode('child');
    final done = endState('done');
    return flow(
      initial: CrossSurfaceEntryDescriptor.ref,
      states: [
        screen(CrossSurfaceEntryDescriptor.ref)
            .on(CrossSurfaceEntry.next)
            .goTo(child),
        subFlow(
          child,
          flow: messageChildRef,
          input: const {},
          onComplete: [
            flowBranch(
              when: const FlowBranchPredicate(fields: {}),
              target: done,
            ),
          ],
          defaultBranch: flowBranchTarget(done),
        ),
        end(done, result: {}),
      ],
    );
  }
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const <String, String>{
        'apps_examples|lib/shared/cross_surface_entry.dart': screen,
        'apps_examples|lib/onboarding_child.dart': onboardingChild,
        'apps_examples|lib/message_child.dart': messageChild,
        'apps_examples|lib/cross_surface_parent.dart': parent,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains(
        'Subflow child message/shared_child cannot be included in a '
        'onboarding flow.',
      ),
    );
  });

  test(
      'canonical class flow embeds an arbitrary-path roster paywall exact '
      'aggregate artifact', () async {
    const paywall = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall(id: 'premium_offer')
final class PremiumOffer extends StatelessWidget {
  const PremiumOffer({super.key});

  @override
  Widget build(BuildContext context) => const Text('Premium offer');
}
''';
    const flow = '''
import 'package:restage/restage.dart';

part 'offer_gate.rsflow.g.dart';

@FlowGraph(id: 'offer_gate', surface: Surface.general)
final class OfferGate extends RestageFlow {
  const OfferGate();

  @override
  FlowDef buildFlow() {
    final done = endState('done');
    return flow(
      initial: paywallScreen('premium_offer'),
      states: [
        screen(paywallScreen('premium_offer'))
            .on(PaywallFlowEvents.purchase)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final result = await testBuilder(
      const PackageSurfaceCompilerBuilder(BuilderOptions.empty),
      const <String, String>{
        'apps_examples|lib/arbitrary/commerce/premium_offer.dart': paywall,
        'apps_examples|lib/journeys/offer_gate.dart': flow,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    final bundle = _readBundle(readerWriter);
    const adapterBlobPath = 'assets/paywalls/screens/paywall_premium_offer.rfw';
    const adapterSidecarPath =
        'assets/paywalls/screens/paywall_premium_offer.capability.json';
    final adapterBlob = bundle.artifacts[adapterBlobPath]!;
    final sidecar = jsonDecode(
      utf8.decode(bundle.artifacts[adapterSidecarPath]!),
    ) as Map<String, Object?>;
    final builtInFloor =
        (sidecar['manifest']! as Map<Object?, Object?>)['builtInFloor']! as int;
    final document = FlowDocumentCodec.decodeJson(
      utf8.decode(
        bundle.artifacts['assets/general/flows/offer_gate.flow.json']!,
      ),
    );
    final embedded = document.screenArtifacts['paywall_premium_offer']!;
    expect(embedded.path, 'paywall_premium_offer.rfw');
    expect(embedded.version, 1);
    expect(embedded.minClient, builtInFloor);
    expect(embedded.contentHash, FlowContentHash.compute(adapterBlob));
    expect(document.minClient, greaterThanOrEqualTo(embedded.minClient));
  });
}

RestageSurfacePublicationBundle _readBundle(TestReaderWriter readerWriter) =>
    RestageSurfacePublicationBundle.fromJson(
      jsonDecode(
        readerWriter.testing.readString(
          AssetId(
            'apps_examples',
            kRestageSurfacePublicationCompilerBundlePath,
          ),
        ),
      ),
    );
