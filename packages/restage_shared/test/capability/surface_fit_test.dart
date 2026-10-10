import 'dart:convert';

import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show CanonicalFormatException, CanonicalJsonCodec;
import 'package:restage_shared/src/capability/capability_manifest.dart';
import 'package:restage_shared/src/capability/installed_capability.dart';
import 'package:restage_shared/src/capability/surface_fit.dart';
import 'package:restage_shared/src/capability/widget_vocabulary.dart';
import 'package:restage_shared/src/flow_document/flow_action_schema.dart';
import 'package:restage_shared/src/flow_document/flow_active_render_gate.dart';
import 'package:restage_shared/src/flow_document/flow_document.dart';
import 'package:restage_shared/src/surface_contract/surface_screen_event_schema.dart';
import 'package:restage_shared/src/surface_contract/surface_screen_host_data_schema.dart';
import 'package:test/test.dart';

import 'flow_experiment_test_support.dart';

const _inlineSingle = SurfaceHostingV1(
  contentKind: SurfaceContentKindV1.single,
  presentation: SurfacePresentationV1.inline,
);
const _presentedFlow = SurfaceHostingV1(
  contentKind: SurfaceContentKindV1.flow,
  presentation: SurfacePresentationV1.presented,
);
const _string = SurfaceScreenHostDataScalarShapeV1(
  SurfaceScreenHostDataScalarKind.string,
);
const _int = SurfaceScreenHostDataScalarShapeV1(
  SurfaceScreenHostDataScalarKind.integer,
);
const _num = SurfaceScreenHostDataScalarShapeV1(
  SurfaceScreenHostDataScalarKind.number,
);
const _double = SurfaceScreenHostDataScalarShapeV1(
  SurfaceScreenHostDataScalarKind.doubleValue,
);
const _json = SurfaceScreenHostDataScalarShapeV1(
  SurfaceScreenHostDataScalarKind.jsonValue,
);
const _eventString = SurfaceScreenEventScalarShapeV1(
  SurfaceScreenEventScalarKind.string,
);
const _eventInt = SurfaceScreenEventScalarShapeV1(
  SurfaceScreenEventScalarKind.integer,
);
const _eventJson = SurfaceScreenEventScalarShapeV1(
  SurfaceScreenEventScalarKind.jsonValue,
);

void main() {
  test('projects global child bindings while retaining root-only state/results',
      () {
    final root = experimentDocument().copyWith(
      legacyTerminalResultPassthrough: false,
    );
    const notify = FlowActionContract(
      actionName: 'notify',
      contractVersion: 1,
      minClient: 3,
      argsSchema: FlowActionSchema.object({}),
      resultSchema: FlowActionSchema.bool(),
      idempotent: false,
    );
    final child = root.copyWith(
      flow: 'details',
      actions: const {'notify': notify},
      flowState: const {
        'child_seed': FlowStateDeclaration(
            type: FlowDataType.string,
            classification: FlowStateClassification.internal,
            hostSeedable: true),
      },
      outbound: const FlowOutboundDeclarations(
        terminalResult: FlowOutboundPayloadDeclaration(fields: {
          'child_result': FlowOutboundField(
              type: FlowDataType.string,
              ref: StateFlowOutboundRef(key: 'child_seed')),
        }),
        customEvents: {'skip': FlowOutboundPayloadDeclaration()},
      ),
    );
    final boundary = FlowHostBoundaryV1.fromDocuments(
      root: root,
      descendants: [child],
    );
    expect(boundary.actions.keys, ['notify']);
    expect(boundary.signals, {'skip'});
    expect(boundary.outbound.customEvents.keys, ['skip']);
    expect(boundary.hostSeedableState, isEmpty);
    expect(boundary.outbound.terminalResult, isEmpty);
    expect(_flowFit(boundary, boundary).accepted, isTrue);
    final conflict = child.copyWith(actions: const {
      'notify': FlowActionContract(
          actionName: 'notify',
          contractVersion: 2,
          minClient: 3,
          argsSchema: FlowActionSchema.object({}),
          resultSchema: FlowActionSchema.bool(),
          idempotent: false),
    });
    expect(
        () => FlowHostBoundaryV1.fromDocuments(
              root: root,
              descendants: [child, conflict],
            ),
        throwsFormatException);
    final conflictingSignal = child.copyWith(
      outbound: const FlowOutboundDeclarations(customEvents: {
        'skip': FlowOutboundPayloadDeclaration(fields: {
          'answer': FlowOutboundField(
              type: FlowDataType.string,
              ref: StateFlowOutboundRef(key: 'child_seed')),
        }),
      }),
    );
    final otherSignal = conflictingSignal.copyWith(
      outbound: const FlowOutboundDeclarations(customEvents: {
        'skip': FlowOutboundPayloadDeclaration(fields: {
          'answer': FlowOutboundField(
              type: FlowDataType.int,
              ref: StateFlowOutboundRef(key: 'child_seed')),
        }),
      }),
    );
    expect(
        () => FlowHostBoundaryV1.fromDocuments(
              root: root,
              descendants: [conflictingSignal, otherSignal],
            ),
        throwsFormatException);
  });

  group('hosting', () {
    test('pure screen may fit either actual host but not a flow host', () {
      final requirement = SurfaceHostingRequirementV1(
        contentKind: SurfaceContentKindV1.single,
        allowedPresentations: const {
          SurfacePresentationV1.inline,
          SurfacePresentationV1.presented,
        },
      );
      for (final presentation in SurfacePresentationV1.values) {
        expect(
          surfaceHostingFits(
            SurfaceHostingV1(
              contentKind: SurfaceContentKindV1.single,
              presentation: presentation,
            ),
            requirement,
          ),
          isTrue,
        );
      }
      expect(surfaceHostingFits(_presentedFlow, requirement), isFalse);
    });

    test('evaluator rejects an unproven presentation mode', () {
      final verdict = _evaluate(
        requirement: _requirement(
          presentations: {SurfacePresentationV1.presented},
        ),
      );
      _expectFailure(verdict, SurfaceFitFailureCodeV1.hostingMismatch);
      expect(verdict.failures.single.path, r'$.hosting');
    });

    test('evaluator rejects a different content kind', () {
      _expectFailure(
        _evaluate(
          requirement: _requirement(
            hostingKind: SurfaceContentKindV1.flow,
            boundary: _boundary(),
          ),
        ),
        SurfaceFitFailureCodeV1.hostingMismatch,
      );
    });

    test('empty presentation metadata is refused and sets are immutable', () {
      expect(
        () => SurfaceHostingRequirementV1(
          contentKind: SurfaceContentKindV1.single,
          allowedPresentations: const {},
        ),
        throwsFormatException,
      );
      final modes = {SurfacePresentationV1.inline};
      final requirement = SurfaceHostingRequirementV1(
        contentKind: SurfaceContentKindV1.single,
        allowedPresentations: modes,
      );
      modes.add(SurfacePresentationV1.presented);
      expect(requirement.allowedPresentations, {SurfacePresentationV1.inline});
      expect(
        () => requirement.allowedPresentations.add(
          SurfacePresentationV1.presented,
        ),
        throwsUnsupportedError,
      );
    });

    test('hosting codec requires exact current metadata', () {
      final json = _requirement().hosting.toJson();
      for (final malformed in [
        <String, Object?>{'contentKind': 'single'},
        <String, Object?>{...json, 'allowedPresentations': <Object?>[]},
        <String, Object?>{...json, 'contentKind': 'screen'},
        <String, Object?>{
          ...json,
          'allowedPresentations': ['inline', 'inline'],
        },
        <String, Object?>{...json, 'presentationIndependent': true},
      ]) {
        expect(
          () => SurfaceHostingRequirementV1.fromJson(malformed),
          throwsFormatException,
        );
      }
    });
  });

  group('context containment', () {
    test('evaluator rejects missing required context', () {
      final verdict = _evaluate(
        requirement: _requirement(
          context: SurfaceScreenHostDataSchema(const {'name': _string}),
        ),
      );
      _expectFailure(verdict, SurfaceFitFailureCodeV1.missingHostField);
      expect(verdict.failures.single.path, r'$.requiredContext.name');
      expect(verdict.failures.single.available, isNull);
    });

    test('host extra fields are allowed', () {
      expect(
        _evaluate(
          host: _host(
            context: SurfaceScreenHostDataSchema(const {
              'name': _string,
              'age': _int,
            }),
          ),
          requirement: _requirement(
            context: SurfaceScreenHostDataSchema(const {'name': _string}),
          ),
        ).accepted,
        isTrue,
      );
    });

    final cases = <(
      String,
      SurfaceScreenHostDataShape,
      SurfaceScreenHostDataShape,
      bool
    )>[
      ('int into num', _num, _int, true),
      ('double into num', _num, _double, true),
      ('num into int', _int, _num, false),
      ('int into double', _double, _int, false),
      (
        'nullable host into required input',
        _string,
        const SurfaceScreenHostDataNullableShapeV1(_string),
        false
      ),
      (
        'nonnullable host into nullable input',
        const SurfaceScreenHostDataNullableShapeV1(_string),
        _string,
        true
      ),
      (
        'nullable numeric containment',
        const SurfaceScreenHostDataNullableShapeV1(_num),
        const SurfaceScreenHostDataNullableShapeV1(_int),
        true
      ),
      (
        'jsonValue accepts nullable input',
        _json,
        const SurfaceScreenHostDataNullableShapeV1(_string),
        true
      ),
      ('jsonValue cannot provide just string', _string, _json, false),
      (
        'nullable string cannot accept all jsonValue',
        const SurfaceScreenHostDataNullableShapeV1(_string),
        _json,
        false
      ),
      (
        'redundant nullable wrappers have the same accepted values',
        const SurfaceScreenHostDataNullableShapeV1(_string),
        const SurfaceScreenHostDataNullableShapeV1(
          SurfaceScreenHostDataNullableShapeV1(_string),
        ),
        true
      ),
    ];
    for (final (label, required, provided, accepted) in cases) {
      test(label, () {
        expect(hostDataShapeAcceptsProvided(required, provided), accepted);
        expect(
          _evaluate(
            host: _host(
              context: SurfaceScreenHostDataSchema({'input': provided}),
            ),
            requirement: _requirement(
              context: SurfaceScreenHostDataSchema({'input': required}),
            ),
          ).accepted,
          accepted,
        );
      });
    }

    test('nested list objects allow extra fields and numeric containment', () {
      final required = SurfaceScreenHostDataListShapeV1(
        SurfaceScreenHostDataObjectShapeV1(const {'score': _num}),
      );
      final provided = SurfaceScreenHostDataListShapeV1(
        SurfaceScreenHostDataObjectShapeV1(const {
          'score': _int,
          'label': _string,
        }),
      );
      expect(
        _evaluate(
          host: _host(context: SurfaceScreenHostDataSchema({'rows': provided})),
          requirement: _requirement(
            context: SurfaceScreenHostDataSchema({'rows': required}),
          ),
        ).accepted,
        isTrue,
      );
    });

    test('nested object missing fields and nullable lists fail directionally',
        () {
      final required = SurfaceScreenHostDataListShapeV1(
        SurfaceScreenHostDataObjectShapeV1(const {'score': _num}),
      );
      final provided = SurfaceScreenHostDataListShapeV1(
        SurfaceScreenHostDataObjectShapeV1(const {'label': _string}),
      );
      final verdict = _evaluate(
        host: _host(context: SurfaceScreenHostDataSchema({'rows': provided})),
        requirement: _requirement(
          context: SurfaceScreenHostDataSchema({'rows': required}),
        ),
      );
      _expectFailure(verdict, SurfaceFitFailureCodeV1.missingHostField);
      expect(verdict.failures.single.path, r'$.requiredContext.rows[].score');
      expect(
        hostDataShapeAcceptsProvided(
          const SurfaceScreenHostDataListShapeV1(_string),
          const SurfaceScreenHostDataListShapeV1(
            SurfaceScreenHostDataNullableShapeV1(_string),
          ),
        ),
        isFalse,
      );
    });

    test('map values and fixed objects use their actual containment', () {
      expect(
        hostDataShapeAcceptsProvided(
          const SurfaceScreenHostDataMapShapeV1(_num),
          const SurfaceScreenHostDataMapShapeV1(_int),
        ),
        isTrue,
      );
      expect(
        hostDataShapeAcceptsProvided(
          const SurfaceScreenHostDataMapShapeV1(_num),
          SurfaceScreenHostDataObjectShapeV1(const {'count': _int}),
        ),
        isTrue,
      );
      expect(
        hostDataShapeAcceptsProvided(
          SurfaceScreenHostDataObjectShapeV1(const {'count': _int}),
          const SurfaceScreenHostDataMapShapeV1(_int),
        ),
        isFalse,
      );
    });
  });

  group('event containment', () {
    test('every emitted ID must be handled', () {
      _expectFailure(
        _evaluate(
          requirement: _requirement(events: _events(_eventString)),
        ),
        SurfaceFitFailureCodeV1.unhandledEvent,
      );
    });

    test('handler accepts every emitted value in the reverse direction', () {
      expect(
        _evaluate(
          host: _host(events: _events(_eventJson)),
          requirement: _requirement(events: _events(_eventString)),
        ).accepted,
        isTrue,
      );
      _expectFailure(
        _evaluate(
          host: _host(events: _events(_eventString)),
          requirement: _requirement(events: _events(_eventJson)),
        ),
        SurfaceFitFailureCodeV1.incompatibleEventShape,
      );
    });

    test('nullable handlers accept nonnullable emission but not conversely',
        () {
      final nullable = _events(
        const SurfaceScreenEventNullableShapeV1(_eventString),
      );
      final nonnullable = _events(_eventString);
      expect(
        _evaluate(
          host: _host(events: nullable),
          requirement: _requirement(events: nonnullable),
        ).accepted,
        isTrue,
      );
      _expectFailure(
        _evaluate(
          host: _host(events: nonnullable),
          requirement: _requirement(events: nullable),
        ),
        SurfaceFitFailureCodeV1.incompatibleEventShape,
      );
    });

    test('object and value wrappers remain distinct for the same map', () {
      const map = SurfaceScreenEventMapShapeV1(_eventString);
      _expectFailure(
        _evaluate(
          host: _host(
            events: _eventArguments(SurfaceScreenEventObjectArguments(map)),
          ),
          requirement: _requirement(
            events:
                _eventArguments(const SurfaceScreenEventValueArguments(map)),
          ),
        ),
        SurfaceFitFailureCodeV1.incompatibleEventShape,
      );
    });

    test('none agrees only with none and extra handlers are allowed', () {
      final none = _eventArguments(const SurfaceScreenEventNoArguments());
      expect(
        _evaluate(
          host: _host(events: none),
          requirement: _requirement(events: none),
        ).accepted,
        isTrue,
      );
      expect(_evaluate(host: _host(events: none)).accepted, isTrue);
      _expectFailure(
        _evaluate(
          host: _host(events: none),
          requirement: _requirement(events: _events(_eventInt)),
        ),
        SurfaceFitFailureCodeV1.incompatibleEventShape,
      );
    });

    test('nested event maps and lists recurse without numeric widening', () {
      const accepted = SurfaceScreenEventMapShapeV1(
        SurfaceScreenEventListShapeV1(_eventJson),
      );
      const emitted = SurfaceScreenEventMapShapeV1(
        SurfaceScreenEventListShapeV1(_eventInt),
      );
      expect(
        _evaluate(
          host: _host(events: _events(accepted)),
          requirement: _requirement(events: _events(emitted)),
        ).accepted,
        isTrue,
      );
      _expectFailure(
        _evaluate(
          host: _host(events: _events(_eventInt)),
          requirement: _requirement(
            events: _events(
              const SurfaceScreenEventScalarShapeV1(
                SurfaceScreenEventScalarKind.doubleValue,
              ),
            ),
          ),
        ),
        SurfaceFitFailureCodeV1.incompatibleEventShape,
      );
    });
  });

  group('installed render capabilities', () {
    test('built-in floor uses the existing blob gate', () {
      _expectFailure(
        _evaluate(
          requirement: _requirement(
            capabilities: CapabilityManifest(
              builtInFloor: 6,
              requiredLibraries: const [],
            ),
          ),
        ),
        SurfaceFitFailureCodeV1.builtInFloor,
      );
    });

    final libraries = <(String, InstalledLibrary?, SurfaceFitFailureCodeV1?)>[
      ('missing', null, SurfaceFitFailureCodeV1.missingLibrary),
      (
        'unversioned',
        const InstalledLibrary(namespace: 'acme.widgets'),
        SurfaceFitFailureCodeV1.missingLibrary
      ),
      (
        'old',
        const InstalledLibrary(namespace: 'acme.widgets', version: 2),
        SurfaceFitFailureCodeV1.oldLibrary
      ),
      (
        'broken',
        const InstalledLibrary(
          namespace: 'acme.widgets',
          version: 5,
          compatibleSince: 4,
        ),
        SurfaceFitFailureCodeV1.brokenLibrary
      ),
      (
        'satisfied',
        const InstalledLibrary(namespace: 'acme.widgets', version: 3),
        null
      ),
    ];
    for (final (label, library, failure) in libraries) {
      test('library $label retains compatibility authority', () {
        final verdict = _evaluate(
          requirement: _requirement(
            capabilities: CapabilityManifest(
              builtInFloor: 1,
              requiredLibraries: const [
                LibraryRequirement(namespace: 'acme.widgets', minVersion: 3),
              ],
            ),
          ),
          installed: _installed(libraries: [if (library != null) library]),
        );
        if (failure == null) {
          expect(verdict.accepted, isTrue);
        } else {
          _expectFailure(verdict, failure);
        }
      });
    }

    test('selectively installed widget and icon members are exact', () {
      final required = WidgetVocabulary(
        widgetNames: const {'restage.material:Text'},
        iconCodePoints: const {
          'MaterialIcons': {42},
        },
      );
      final verdict = _evaluate(
        requirement: _requirement(vocabulary: required),
        installed: _installed(
          vocabulary: WidgetVocabulary(
            widgetNames: const {'acme.material:Text'},
            iconCodePoints: const {
              'OtherIcons': {42},
            },
          ),
        ),
      );
      _expectFailure(verdict, SurfaceFitFailureCodeV1.missingWidget);
      _expectFailure(verdict, SurfaceFitFailureCodeV1.missingIcon);
      expect(
        _evaluate(
          requirement: _requirement(vocabulary: required),
          installed: _installed(vocabulary: required),
        ).accepted,
        isTrue,
      );
    });

    test('absent installed vocabulary cannot prove a replacement contract', () {
      _expectFailure(
        _evaluate(
          installed: InstalledCapability(
            builtInCatalogVersion: 5,
            installedLibraries: const [],
          ),
        ),
        SurfaceFitFailureCodeV1.missingInstalledVocabulary,
      );
    });
  });

  group('flow host boundary', () {
    test('different typed topology fits equal ABI without relaxing lineage',
        () {
      const outbound = FlowOutboundDeclarations(
        terminalResult: FlowOutboundPayloadDeclaration(
          fields: {
            'completed': FlowOutboundField(
              type: FlowDataType.bool,
              ref: StateFlowOutboundRef(key: 'completed'),
            ),
          },
        ),
      );
      final hostDocument = experimentDocument(
        flowState: const {
          'completed': FlowStateDeclaration(
            type: FlowDataType.bool,
            classification: FlowStateClassification.exportable,
            defaultValue: true,
          ),
        },
        outbound: outbound,
      );
      final candidateDocument = hostDocument.copyWith(
        flow: 'other_surface',
        initial: 'another_end',
        states: const {'another_end': EndFlowState(result: {})},
      );
      final hostBoundary = FlowHostBoundaryV1.fromDocument(
        hostDocument,
        signals: const {},
      );
      final candidateBoundary = FlowHostBoundaryV1.fromDocument(
        candidateDocument,
        signals: const {},
      );
      expect(hostBoundary.contentHash, candidateBoundary.contentHash);
      expect(
        _flowFit(hostBoundary, candidateBoundary).accepted,
        isTrue,
      );
      expect(
        FlowActiveRenderGate.evaluate(
          client: hostDocument,
          active: candidateDocument,
        ).accepted,
        isFalse,
      );
    });

    test('legacy terminal values cannot become an empty projected typed ABI',
        () {
      final document = experimentDocument();
      expect(document.legacyTerminalResultPassthrough, isTrue);
      expect(document.outbound.terminalResult.isEmpty, isTrue);
      expect((document.states['done']! as EndFlowState).result, isNotEmpty);
      expect(
        () => FlowHostBoundaryV1.fromDocument(document, signals: const {}),
        throwsFormatException,
      );
    });

    test('flow construction requires its boundary and single excludes one', () {
      expect(
        () => _host(hosting: _presentedFlow),
        throwsFormatException,
      );
      expect(
        () => _requirement(hostingKind: SurfaceContentKindV1.flow),
        throwsFormatException,
      );
      expect(() => _host(boundary: _boundary()), throwsFormatException);
      expect(() => _requirement(boundary: _boundary()), throwsFormatException);
    });

    test('typed content cannot use a general host boundary', () {
      _expectFailure(
        _flowFit(
          _boundary(mode: FlowDeliveryMode.general),
          _boundary(),
        ),
        SurfaceFitFailureCodeV1.deliveryModeMismatch,
      );
    });

    test('typed terminal result keys and types are exact', () {
      final host = _boundary(
        outbound: FlowHostOutboundShapeV1(
          terminalResult: const {'completed': FlowDataType.bool},
        ),
      );
      for (final result in [
        const <String, FlowDataType>{},
        const {'completed': FlowDataType.string},
        const {'completed': FlowDataType.bool, 'extra': FlowDataType.int},
      ]) {
        _expectFailure(
          _flowFit(
            host,
            _boundary(
              outbound: FlowHostOutboundShapeV1(terminalResult: result),
            ),
          ),
          SurfaceFitFailureCodeV1.resultMismatch,
        );
      }
      expect(_flowFit(host, host).accepted, isTrue);
    });

    test('actions keep exact names versions schemas idempotency and support',
        () {
      final required = experimentAction(minClient: 2);
      final host = _boundary(
        actions: {'request_notifications': experimentAction(minClient: 3)},
      );
      final candidate = _boundary(actions: {'request_notifications': required});
      expect(_flowFit(host, candidate).accepted, isTrue);
      _expectFailure(
        _flowFit(_boundary(), candidate),
        SurfaceFitFailureCodeV1.actionMismatch,
      );
      final mismatches = [
        _action(required, name: 'other_action'),
        _action(required, version: 2),
        _action(required, args: const FlowActionSchema.string()),
        _action(required, result: const FlowActionSchema.string()),
        _action(required, minClient: 1),
        _action(required, idempotent: true),
      ];
      for (final action in mismatches) {
        _expectFailure(
          _flowFit(
            _boundary(actions: {'request_notifications': action}),
            candidate,
          ),
          SurfaceFitFailureCodeV1.actionMismatch,
        );
      }
    });

    test('action minimum also needs the actual installed catalog floor', () {
      final boundary = _boundary(
        actions: {'request_notifications': experimentAction(minClient: 6)},
      );
      _expectFailure(
        _flowFit(boundary, boundary),
        SurfaceFitFailureCodeV1.builtInFloor,
      );
    });

    test('candidate preserves every host seed key and type', () {
      final host = _boundary(seeds: {'answer': _seed(FlowDataType.string)});
      for (final candidate in [
        _boundary(),
        _boundary(seeds: {'answer': _seed(FlowDataType.int)}),
      ]) {
        _expectFailure(
          _flowFit(host, candidate),
          SurfaceFitFailureCodeV1.seedMismatch,
        );
      }
      expect(
        _flowFit(
          host,
          _boundary(
            seeds: {
              'answer': _seed(FlowDataType.string),
              'extra': _seed(FlowDataType.bool),
            },
          ),
        ).accepted,
        isTrue,
      );
    });

    test('signals require installed names in both delivery modes', () {
      for (final mode in FlowDeliveryMode.values) {
        _expectFailure(
          _flowFit(
            _boundary(mode: mode),
            _boundary(mode: mode, signals: {'skip'}),
          ),
          SurfaceFitFailureCodeV1.signalMismatch,
        );
        expect(
          _flowFit(
            _boundary(mode: mode, signals: {'skip', 'extra'}),
            _boundary(mode: mode, signals: {'skip'}),
          ).accepted,
          isTrue,
        );
      }
    });

    test('all externally observable outbound categories are checked', () {
      final candidate = _boundary(
        outbound: FlowHostOutboundShapeV1(
          actionArgs: const {
            'request_notifications': {'answer': FlowDataType.string},
          },
          lifecycle: const {'step': FlowDataType.string},
          surveyAnswers: const {'answer': FlowDataType.string},
          subFlowResult: const {'completed': FlowDataType.bool},
          customEvents: const {
            'skip': {'reason': FlowDataType.string},
          },
        ),
        signals: {'skip'},
      );
      final verdict = _flowFit(_boundary(signals: {'skip'}), candidate);
      _expectFailure(verdict, SurfaceFitFailureCodeV1.outboundMismatch);
      expect(
        verdict.failures.map((failure) => failure.path),
        containsAll([
          r'$.flowBoundary.outbound.actionArgs.request_notifications',
          r'$.flowBoundary.outbound.lifecycle.step',
          r'$.flowBoundary.outbound.surveyAnswers.answer',
          r'$.flowBoundary.outbound.subFlowResult.completed',
          r'$.flowBoundary.outbound.customEvents.skip',
        ]),
      );
      expect(_flowFit(candidate, candidate).accepted, isTrue);
    });

    test('outbound event declarations cannot omit the installed signal check',
        () {
      final outbound = FlowHostOutboundShapeV1(
        customEvents: const {'skip': <String, FlowDataType>{}},
      );
      _expectFailure(
        _flowFit(_boundary(outbound: outbound), _boundary(outbound: outbound)),
        SurfaceFitFailureCodeV1.signalMismatch,
      );
    });
  });

  group('immutable canonical contracts', () {
    test('canonical host and requirement shapes have distinct hash domains',
        () {
      const hostJson =
          '{"flowBoundary":null,"handledEvents":{"events":[],"schemaVersion":1},'
          '"hosting":{"contentKind":"single","presentation":"inline"},'
          '"providedContext":{"inputs":{},"schemaVersion":1},"schemaVersion":1}';
      const requirementJson =
          '{"capabilities":{"builtInFloor":1,"requiredLibraries":[]},'
          '"emittedEvents":{"events":[],"schemaVersion":1},"flowBoundary":null,'
          '"hosting":{"allowedPresentations":["inline","presented"],'
          '"contentKind":"single"},"requiredContext":{"inputs":{},'
          '"schemaVersion":1},"requiredVocabulary":{"iconCodePoints":{},'
          '"widgetNames":[]},"schemaVersion":1}';
      expect(utf8.decode(_host().canonicalBytes), hostJson);
      expect(
        _host().contentHash,
        'sha256:32adf3a1a1c3a15c480848068c833cad3a4c91f2b0f3eb41ea4c4e95eb2899a4',
      );
      expect(utf8.decode(_requirement().canonicalBytes), requirementJson);
      expect(
        _requirement().contentHash,
        'sha256:53d24779e43407351544428569e2b26fa5365b37ec223c8ef42ca1ef304ad177',
      );
      expect(_host().contentHash, isNot(_requirement().contentHash));
    });

    test('every constructed shape supports the portable canonical profile', () {
      const tooLarge = 9007199254740992;
      expect(
        () => _requirement(
          capabilities: CapabilityManifest(
            builtInFloor: tooLarge,
            requiredLibraries: const [],
          ),
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
      expect(
        () => _boundary(
          actions: {'notify': experimentAction(minClient: tooLarge)},
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('boundary decoding refuses source references and seed values', () {
      final boundary = _boundary(seeds: {'answer': _seed(FlowDataType.string)});
      final json = boundary.toJson();
      expect(
        () => FlowHostBoundaryV1.fromJson({
          ...json,
          'hostSeedableState': const {
            'answer': {
              'type': 'string',
              'classification': 'internal',
              'hostSeedable': true,
              'default': 'actual data',
            },
          },
        }),
        throwsFormatException,
      );
      expect(
        () => FlowHostBoundaryV1.fromJson({...json, 'integrityVerified': true}),
        throwsFormatException,
      );
      expect(
        () => FlowHostOutboundShapeV1.fromJson({
          ...boundary.outbound.toJson(),
          'terminalResult': const {
            'completed': {
              'type': 'bool',
              'ref': {'state': 'internal'},
            },
          },
        }),
        throwsFormatException,
      );
    });

    test('host schema snapshots detach nested maps and exclude host values',
        () {
      final object = SurfaceScreenHostDataObjectShapeV1(const {'count': _int});
      final schema = SurfaceScreenHostDataSchema({'profile': object});
      final host = _host(context: schema);
      final hash = host.contentHash;
      schema.inputs.clear();
      object.fields.clear();
      host.providedContext.inputs.clear();
      expect(host.contentHash, hash);
      final profile = host.providedContext.inputs['profile']!
          as SurfaceScreenHostDataObjectShapeV1;
      expect(profile.fields.keys, ['count']);
      expect(
        SurfaceHostContractV1.fromJson(
          CanonicalJsonCodec.decode(host.canonicalBytes),
        ).contentHash,
        hash,
      );
      final json = host.toJson();
      expect(json.keys, isNot(contains('values')));
      expect(
        () => SurfaceHostContractV1.fromJson({
          ...json,
          'values': const {'count': 4},
        }),
        throwsFormatException,
      );
    });

    test('canonical order and roundtrip preserve host requirement and boundary',
        () {
      final first = _boundary(
        actions: {'notify': experimentAction()},
        seeds: {'answer': _seed(FlowDataType.string)},
        signals: {'skip', 'continue'},
        outbound: FlowHostOutboundShapeV1(
          terminalResult: const {'completed': FlowDataType.bool},
        ),
      );
      final second = _boundary(
        actions: {'notify': experimentAction()},
        seeds: {'answer': _seed(FlowDataType.string, defaultValue: 'unused')},
        signals: {'continue', 'skip'},
        outbound: FlowHostOutboundShapeV1(
          terminalResult: const {'completed': FlowDataType.bool},
        ),
      );
      expect(first.canonicalBytes, second.canonicalBytes);
      expect(first.contentHash, second.contentHash);
      expect(first.hostSeedableState['answer']!.defaultValue, isNull);
      expect(
        FlowHostBoundaryV1.fromJson(
          CanonicalJsonCodec.decode(first.canonicalBytes),
        ).canonicalBytes,
        first.canonicalBytes,
      );
      final host = _host(hosting: _presentedFlow, boundary: first);
      final requirement = _requirement(
        hostingKind: SurfaceContentKindV1.flow,
        boundary: second,
      );
      expect(
        SurfaceHostContractV1.fromJson(host.toJson()).canonicalBytes,
        host.canonicalBytes,
      );
      expect(
        SurfaceFitRequirementV1.fromJson(requirement.toJson()).canonicalBytes,
        requirement.canonicalBytes,
      );
      expect(host.contentHash, isNot(requirement.contentHash));
      expect(
        utf8.decode(host.canonicalBytes),
        utf8.decode(CanonicalJsonCodec.encode(host.toJson())),
      );
    });

    test('outbound projection discards source references and keeps only types',
        () {
      final first = FlowHostOutboundShapeV1.fromDeclarations(
        const FlowOutboundDeclarations(
          terminalResult: FlowOutboundPayloadDeclaration(
            fields: {
              'completed': FlowOutboundField(
                type: FlowDataType.bool,
                ref: StateFlowOutboundRef(key: 'internal_one'),
              ),
            },
          ),
        ),
      );
      final second = FlowHostOutboundShapeV1.fromDeclarations(
        const FlowOutboundDeclarations(
          terminalResult: FlowOutboundPayloadDeclaration(
            fields: {
              'completed': FlowOutboundField(
                type: FlowDataType.bool,
                ref: EventFlowOutboundRef(key: 'internal_two', path: ['value']),
              ),
            },
          ),
        ),
      );
      expect(first.toJson(), second.toJson());
      expect(first.terminalResult, {'completed': FlowDataType.bool});
      expect(first.toJson().toString(), isNot(contains('ref')));
      expect(
        FlowHostOutboundShapeV1.fromJson(first.toJson()).toJson(),
        first.toJson(),
      );
    });

    test('nested action schemas and outbound collections are frozen', () {
      final fields = <String, FlowActionSchemaField>{
        'answer': const FlowActionSchemaField(
          required: true,
          schema: FlowActionSchema.string(),
        ),
      };
      final action = FlowActionContract(
        actionName: 'save',
        contractVersion: 1,
        argsSchema: FlowActionSchema.object(fields),
        resultSchema: const FlowActionSchema.bool(),
        minClient: 1,
        idempotent: true,
      );
      final terminal = {'completed': FlowDataType.bool};
      final boundary = _boundary(
        actions: {'save': action},
        outbound: FlowHostOutboundShapeV1(terminalResult: terminal),
      );
      final hash = boundary.contentHash;
      fields.clear();
      terminal.clear();
      expect(boundary.contentHash, hash);
      expect(boundary.actions.clear, throwsUnsupportedError);
      final args =
          boundary.actions['save']!.argsSchema as FlowObjectActionSchema;
      expect(args.fields.clear, throwsUnsupportedError);
      expect(
        boundary.outbound.terminalResult.clear,
        throwsUnsupportedError,
      );
      expect(() => boundary.signals.add('unknown'), throwsUnsupportedError);
    });

    test('missing and malformed requirement metadata fails strict decoding',
        () {
      final json = _requirement().toJson();
      for (final key in json.keys) {
        final malformed = {...json}..remove(key);
        expect(
          () => SurfaceFitRequirementV1.fromJson(malformed),
          throwsFormatException,
          reason: key,
        );
      }
      expect(
        () => SurfaceFitRequirementV1.fromJson(
          {...json, 'integrityVerified': true},
        ),
        throwsFormatException,
      );
      expect(
        () => SurfaceFitRequirementV1.fromJson(
          {...json, 'requiredVocabulary': const <String, Object?>{}},
        ),
        throwsFormatException,
      );
      expect(
        () => SurfaceFitRequirementV1.fromJson({...json, 'schemaVersion': 2}),
        throwsFormatException,
      );
    });

    test('rejection failures are nonempty and immutable shape snapshots', () {
      expect(
        () => SurfaceFitVerdictV1.doesNotFit(const []),
        throwsArgumentError,
      );
      final required = <String, Object?>{'kind': 'string'};
      final failure = SurfaceFitFailureV1(
        code: SurfaceFitFailureCodeV1.incompatibleHostField,
        path: r'$.requiredContext.name',
        required: required,
        available: const {'kind': 'int'},
      );
      final failures = [failure];
      final verdict = SurfaceFitVerdictV1.doesNotFit(failures);
      failures.clear();
      required.clear();
      expect(verdict.accepted, isFalse);
      expect(verdict.failures.single.required, {'kind': 'string'});
      expect(verdict.failures.clear, throwsUnsupportedError);
      expect(() => (failure.required! as Map).clear(), throwsUnsupportedError);
      expect(const SurfaceFitVerdictV1.fits().accepted, isTrue);
    });
  });
}

SurfaceHostContractV1 _host({
  SurfaceHostingV1 hosting = _inlineSingle,
  SurfaceScreenHostDataSchema context =
      const SurfaceScreenHostDataSchema.empty(),
  SurfaceScreenEventSchema? events,
  FlowHostBoundaryV1? boundary,
}) =>
    SurfaceHostContractV1(
      hosting: hosting,
      providedContext: context,
      handledEvents: events ?? SurfaceScreenEventSchema(events: const []),
      flowBoundary: boundary,
    );

SurfaceFitRequirementV1 _requirement({
  SurfaceContentKindV1 hostingKind = SurfaceContentKindV1.single,
  Set<SurfacePresentationV1> presentations = const {
    SurfacePresentationV1.inline,
    SurfacePresentationV1.presented,
  },
  SurfaceScreenHostDataSchema context =
      const SurfaceScreenHostDataSchema.empty(),
  SurfaceScreenEventSchema? events,
  CapabilityManifest? capabilities,
  WidgetVocabulary? vocabulary,
  FlowHostBoundaryV1? boundary,
}) =>
    SurfaceFitRequirementV1(
      hosting: SurfaceHostingRequirementV1(
        contentKind: hostingKind,
        allowedPresentations: presentations,
      ),
      requiredContext: context,
      emittedEvents: events ?? SurfaceScreenEventSchema(events: const []),
      capabilities: capabilities ??
          CapabilityManifest(builtInFloor: 1, requiredLibraries: const []),
      requiredVocabulary: vocabulary ?? WidgetVocabulary.empty,
      flowBoundary: boundary,
    );

InstalledCapability _installed({
  List<InstalledLibrary> libraries = const [],
  WidgetVocabulary? vocabulary,
}) =>
    InstalledCapability(
      builtInCatalogVersion: 5,
      installedLibraries: libraries,
      vocabulary: vocabulary ?? WidgetVocabulary.empty,
    );

SurfaceFitVerdictV1 _evaluate({
  SurfaceHostContractV1? host,
  SurfaceFitRequirementV1? requirement,
  InstalledCapability? installed,
}) =>
    SurfaceFitEvaluator.evaluate(
      host: host ?? _host(),
      requirement: requirement ?? _requirement(),
      installed: installed ?? _installed(),
    );

void _expectFailure(SurfaceFitVerdictV1 verdict, SurfaceFitFailureCodeV1 code) {
  expect(verdict.accepted, isFalse);
  expect(verdict.failures.map((failure) => failure.code), contains(code));
}

SurfaceScreenEventSchema _events(SurfaceScreenEventShape shape) =>
    _eventArguments(SurfaceScreenEventValueArguments(shape));

SurfaceScreenEventSchema _eventArguments(
  SurfaceScreenEventArguments arguments,
) =>
    SurfaceScreenEventSchema(
      events: [SurfaceScreenEvent(id: 'answer', arguments: arguments)],
    );

FlowStateDeclaration _seed(FlowDataType type, {Object? defaultValue}) =>
    FlowStateDeclaration(
      type: type,
      classification: FlowStateClassification.internal,
      hostSeedable: true,
      defaultValue: defaultValue,
    );

FlowHostBoundaryV1 _boundary({
  FlowDeliveryMode mode = FlowDeliveryMode.typed,
  Map<String, FlowActionContract> actions = const {},
  Map<String, FlowStateDeclaration> seeds = const {},
  Set<String> signals = const {},
  FlowHostOutboundShapeV1? outbound,
}) =>
    FlowHostBoundaryV1(
      deliveryMode: mode,
      hostSeedableState: seeds,
      actions: actions,
      signals: signals,
      outbound: outbound ?? FlowHostOutboundShapeV1(),
    );

SurfaceFitVerdictV1 _flowFit(
  FlowHostBoundaryV1 host,
  FlowHostBoundaryV1 candidate,
) =>
    _evaluate(
      host: _host(hosting: _presentedFlow, boundary: host),
      requirement: _requirement(
        hostingKind: SurfaceContentKindV1.flow,
        boundary: candidate,
      ),
    );

FlowActionContract _action(
  FlowActionContract action, {
  String? name,
  int? version,
  FlowActionSchema? args,
  FlowActionSchema? result,
  int? minClient,
  bool? idempotent,
}) =>
    FlowActionContract(
      actionName: name ?? action.actionName,
      contractVersion: version ?? action.contractVersion,
      argsSchema: args ?? action.argsSchema,
      resultSchema: result ?? action.resultSchema,
      minClient: minClient ?? action.minClient,
      idempotent: idempotent ?? action.idempotent,
    );
