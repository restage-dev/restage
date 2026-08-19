import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Surface-parameterization proof: the same flow/screen machinery, scoped by
/// the `message` / `survey` surface parameter, codegens a valid flow document
/// from `lib/<surface>/flows/` to `assets/<surface>/flows/` — in BOTH delivery
/// modes (typed default + `delivery: general` stamped).
///
/// Artifact-level proof only: neutral host behavior is covered by SDK widget
/// tests, so no separate message/survey example app is needed here.
void main() {
  for (final surface in const [Surface.message, Surface.survey]) {
    final name = surface.wireName;
    group('surface parameterization — $name', () {
      test('typed flow codegens a valid document to assets/$name/flows',
          () async {
        final doc = await _buildAndValidate(surface, delivery: null);
        expect(doc.deliveryMode, FlowDeliveryMode.typed);
      });

      test('general flow codegens a valid, deliveryMode:general document',
          () async {
        final doc = await _buildAndValidate(
          surface,
          delivery: FlowDeliveryMode.general,
        );
        expect(doc.deliveryMode, FlowDeliveryMode.general);
      });

      test('the emitted flow.json carries the general stamp verbatim',
          () async {
        final json = await _buildFlowJson(surface, FlowDeliveryMode.general);
        expect(json, contains('"deliveryMode":"general"'));
      });

      test('the typed flow.json omits the deliveryMode key entirely', () async {
        final json = await _buildFlowJson(surface, null);
        expect(json, isNot(contains('deliveryMode')));
      });

      for (final delivery in [
        null,
        FlowDeliveryMode.general,
      ]) {
        final mode = delivery?.wireName ?? 'typed';
        test('$mode descriptor carries $name surface provenance', () async {
          final generated = await _buildFlowDescriptor(surface, delivery);
          expect(
            generated,
            contains('surface: Surface.$name'),
          );
          expect(
            generated,
            contains('deliveryMode: FlowDeliveryMode.$mode'),
          );
        });
      }
    });
  }

  test('a sub-flow child artifact resolves from the SAME surface directory',
      () async {
    // Pins the one surface-derived read the single-flow fixtures never
    // execute: a parent flow's subFlow(...) child artifact is read from
    // assets/<surface>/flows/, derived from the parent's own path. The seeded
    // child lives ONLY under message/, so a regression to a fixed surface
    // path fails the build (missing child artifact) and this test goes RED.
    // One non-onboarding surface suffices — the derivation is the same
    // expression for every surface.
    final childJson = _childFlowJson();
    final sources = _subFlowSources(Surface.message, childJson);
    final readerWriter = await _readerWriterWith(sources);
    final result = await testBuilders(
      _buildersFor(Surface.message),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    final bytes = result.readerWriter.testing.readBytes(
      AssetId('apps_examples', 'assets/message/flows/parent.flow.json'),
    );
    final decoded = FlowDocumentCodec.decodeJson(utf8.decode(bytes));
    FlowDocumentValidation.checkValid(decoded);
    final child = decoded.states['profile']! as SubFlowState;
    expect(child.flow, 'profile_child');
    expect(child.contentHash, FlowContentHash.computeString(childJson));
  });
}

const _flowSlug = 'first';
const _screenStem = 'welcome';
const _screenClass = 'WelcomeScreen';
const _screenEvent = 'next';

/// Builds the flow for [surface] in the given [delivery] mode, decodes the
/// emitted `assets/<surface>/flows/first.flow.json`, and runs the shared
/// validator on it (the real proof the artifact is a well-formed document).
Future<FlowDocument> _buildAndValidate(
  Surface surface, {
  required FlowDeliveryMode? delivery,
}) async {
  final json = await _buildFlowJson(surface, delivery);
  final document = FlowDocumentCodec.decodeJson(json);
  FlowDocumentValidation.checkValid(document);
  return document;
}

Future<String> _buildFlowJson(
  Surface surface,
  FlowDeliveryMode? delivery,
) async {
  final name = surface.wireName;
  final result = await _run(surface, delivery);
  final bytes = result.readerWriter.testing.readBytes(
    AssetId('apps_examples', 'assets/$name/flows/$_flowSlug.flow.json'),
  );
  return utf8.decode(bytes);
}

Future<String> _buildFlowDescriptor(
  Surface surface,
  FlowDeliveryMode? delivery,
) async {
  final name = surface.wireName;
  final result = await _run(surface, delivery);
  return result.readerWriter.testing.readString(
    AssetId(
      'apps_examples',
      'lib/$name/flows/restage.generated/$_flowSlug.restage.g.dart',
    ),
  );
}

Future<TestBuilderResult> _run(
  Surface surface,
  FlowDeliveryMode? delivery,
) async {
  final sources = _sources(surface, delivery);
  final readerWriter = await _readerWriterWith(sources);
  return testBuilders(
    _buildersFor(surface),
    sources,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
}

List<Builder> _buildersFor(Surface surface) => switch (surface) {
      Surface.message => [
          messageScreenBuilder(BuilderOptions.empty),
          messageFlowBuilder(BuilderOptions.empty),
          restagePackageSurfaceCompilerBuilder(BuilderOptions.empty),
          restageGeneratedDartBuilder(BuilderOptions.empty),
        ],
      Surface.survey => [
          surveyScreenBuilder(BuilderOptions.empty),
          surveyFlowBuilder(BuilderOptions.empty),
          restagePackageSurfaceCompilerBuilder(BuilderOptions.empty),
          restageGeneratedDartBuilder(BuilderOptions.empty),
        ],
      _ => throw ArgumentError('unexpected surface $surface'),
    };

Map<String, String> _sources(Surface surface, FlowDeliveryMode? delivery) {
  final name = surface.wireName;
  return {
    'apps_examples|lib/$name/screens/$_screenStem.dart': _screenSource(),
    'apps_examples|lib/$name/flows/$_flowSlug.dart': _flowSource(delivery),
  };
}

String _flowSource(FlowDeliveryMode? delivery) {
  final annotation = delivery == null
      ? "@FlowSource(id: '$_flowSlug', version: 1, minClient: 3)"
      : "@FlowSource(id: '$_flowSlug', version: 1, minClient: 3, "
          'delivery: FlowDeliveryMode.general)';
  // Each variant builds in its own isolated readerWriter, so the class name
  // never needs to vary to avoid a collision — only the annotation and the
  // general outbound body legitimately differ with the delivery mode.
  const className = 'FirstFlow';
  // General mode exercises the outbound authoring surface (a terminalResult
  // ref into in-flow-captured state + a custom event) so the stamped document
  // is a realistic general flow, not a degenerate one.
  final generalBody = delivery == null
      ? ''
      : '''
      flowState: const {
        'completed': FlowStateDeclaration(
          type: FlowDataType.bool,
          classification: FlowStateClassification.exportable,
        ),
      },
      outbound: const FlowOutboundDeclarations(
        terminalResult: FlowOutboundPayloadDeclaration(
          fields: {
            'completed': FlowOutboundField(
              type: FlowDataType.bool,
              ref: StateFlowOutboundRef(key: 'completed'),
            ),
          },
        ),
        customEvents: {
          'skip': FlowOutboundPayloadDeclaration(),
        },
      ),''';
  return '''
import 'package:restage/restage.dart';

import '../screens/$_screenStem.dart';

part 'restage.generated/$_flowSlug.restage.g.dart';

$annotation
final class $className extends RestageFlow {
  const $className();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: ${_screenClass}Descriptor.ref,$generalBody
      states: [
        screen(${_screenClass}Descriptor.ref)
            .on($_screenClass.$_screenEvent)
            .goTo(done),
        end(done, result: {'completed': true}),
      ],
    );
  }
}
''';
}

String _screenSource() => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/$_screenStem.restage.g.dart';

@ScreenSource(id: '$_screenStem')
final class $_screenClass extends StatelessWidget {
  static const $_screenEvent = OnboardingEvent<void>('$_screenEvent');

  const $_screenClass({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: ElevatedButton(
          onPressed: onboardingEvent($_screenEvent),
          child: const Text('$_screenClass'),
        ),
      );
}
''';

Future<TestReaderWriter> _readerWriterWith(Map<String, String> sources) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  for (final entry in sources.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  return readerWriter;
}

/// A parent flow with a `subFlow(...)` node whose child artifact is seeded
/// under the SAME surface's asset root — the child read is the one
/// surface-derived site the single-flow fixtures never reach.
Map<String, String> _subFlowSources(Surface surface, String childJson) {
  final name = surface.wireName;
  return {
    'apps_examples|lib/$name/screens/$_screenStem.dart': _screenSource(),
    'apps_examples|assets/$name/flows/profile_child.flow.json': childJson,
    'apps_examples|lib/$name/flows/parent.dart': '''
import 'package:restage/restage.dart';

import '../screens/$_screenStem.dart';

part 'restage.generated/parent.restage.g.dart';

@FlowSource(id: 'parent', version: 1, minClient: 3)
final class ParentFlow extends RestageFlow {
  const ParentFlow();

  @override
  FlowDef buildFlow() {
    final profile = flowNode('profile');
    final done = endState('done');

    return flow(
      initial: ${_screenClass}Descriptor.ref,
      flowState: const {
        'completed': FlowStateDeclaration(
          type: FlowDataType.bool,
          classification: FlowStateClassification.internal,
          defaultValue: false,
        ),
      },
      outbound: const FlowOutboundDeclarations(
        subFlowResult: FlowOutboundPayloadDeclaration(
          fields: {
            'accepted': FlowOutboundField(
              type: FlowDataType.bool,
              ref: EventFlowOutboundRef(key: 'accepted'),
            ),
          },
        ),
      ),
      states: [
        screen(${_screenClass}Descriptor.ref)
            .on($_screenClass.$_screenEvent)
            .goTo(profile),
        subFlow(
          profile,
          flow: profileChildFlow,
          onComplete: [
            flowBranch(
              when: const FlowBranchPredicate(
                fields: {
                  'accepted': EqualsFlowPredicateCondition(
                    value: LiteralFlowValueSource(
                      type: FlowDataType.bool,
                      value: true,
                    ),
                  ),
                },
              ),
              target: done,
              stateWrites: const {
                'completed': FlowStateWrite(
                  type: FlowDataType.bool,
                  value: SubFlowResultFlowValueSource(key: 'accepted'),
                ),
              },
            ),
          ],
          defaultBranch: flowBranchTarget(done),
        ),
        end(done, result: {}),
      ],
    );
  }
}

const profileChildFlow = OnboardingFlowRef<Map<String, Object?>>(
  id: 'profile_child',
  version: 1,
  minClient: 3,
  decodeResult: _decodeProfileChild,
);

Map<String, Object?> _decodeProfileChild(Map<String, Object?> result) {
  return result;
}
''',
  };
}

/// A minimal, valid child flow document (decision → two end states), encoded
/// exactly as the flow builder would publish it.
String _childFlowJson() {
  const document = FlowDocument(
    flow: 'profile_child',
    version: 1,
    schemaVersion: 1,
    minClient: 3,
    initial: 'branch',
    flowState: {
      'parentIsPro': FlowStateDeclaration(
        type: FlowDataType.bool,
        classification: FlowStateClassification.internal,
        defaultValue: false,
      ),
    },
    outbound: FlowOutboundDeclarations(
      terminalResult: FlowOutboundPayloadDeclaration(
        fields: {
          'accepted': FlowOutboundField(
            type: FlowDataType.bool,
            ref: EventFlowOutboundRef(key: 'accepted'),
          ),
        },
      ),
    ),
    screenArtifacts: {},
    states: {
      'branch': DecisionFlowState(
        branches: [
          FlowBranch(
            when: FlowBranchPredicate(
              fields: {
                'parentIsPro': EqualsFlowPredicateCondition(
                  value: LiteralFlowValueSource(
                    type: FlowDataType.bool,
                    value: true,
                  ),
                ),
              },
            ),
            target: 'accepted',
          ),
        ],
        defaultBranch: FlowBranchTarget(target: 'declined'),
      ),
      'accepted': EndFlowState(result: {'accepted': true}),
      'declined': EndFlowState(result: {'accepted': false}),
    },
  );
  FlowDocumentValidation.checkValid(document);
  return utf8.decode(FlowDocumentCodec.encodeCanonicalJson(document));
}
