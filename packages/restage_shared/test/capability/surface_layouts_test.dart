import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import 'flow_experiment_test_support.dart';

const _branch = '_hBranch';
const _guard = '_hGuard';
const _inner = '_hInner';
const _list = '_hList';
const _island = 'app.islands:Badge';

// A build that returns early (index 0), then lists [_list] under [_guard],
// with [_inner] recorded only under [_guard] and an island in return 1.
final _boundary = FlowHostBoundaryV1.fromDocument(
  experimentDocument(flowState: const {
    'completed': FlowStateDeclaration(
      type: FlowDataType.bool,
      classification: FlowStateClassification.exportable,
      defaultValue: true,
    ),
  }),
  signals: const {},
);

final _layouts = SurfaceLayoutsV1(
  domains: {
    _branch: {0, 1},
    _guard: {false, true},
    _inner: {false, true},
  },
  values: {
    _guard: {
      _branch: {1},
    },
    _inner: {
      _branch: {1},
      _guard: {true},
    },
    _list: {
      _branch: {1},
      _guard: {true},
      _inner: {true},
    },
  },
  islands: {
    _island: {
      _branch: {1},
    },
  },
);

SurfaceLayoutPath _path(Map<String, Object> arms) => {
      for (final MapEntry(:key, :value) in arms.entries)
        key: switch (value) {
          (final Set<Object> values, true) => SurfaceLayoutArmV1.noneOf(values),
          final Set<Object> values => SurfaceLayoutArmV1.oneOf(values),
          _ => throw ArgumentError(value),
        },
    };

SurfaceFitVerdictV1 _fit({
  Map<String, List<SurfaceLayoutPath>> values = const {},
  Map<String, List<SurfaceLayoutPath>> islands = const {},
  Set<String> topLevel = const {},
  bool island = false,
}) {
  const string = SurfaceScreenHostDataScalarShapeV1(
    SurfaceScreenHostDataScalarKind.string,
  );
  return SurfaceFitEvaluator.evaluate(
    host: SurfaceHostContractV1(
      hosting: const SurfaceHostingV1(
        contentKind: SurfaceContentKindV1.single,
        presentation: SurfacePresentationV1.inline,
      ),
      providedContext: SurfaceScreenHostDataSchema({
        for (final key in [_branch, _guard, _inner, _list]) key: string,
      }),
      handledEvents: SurfaceScreenEventSchema(events: const []),
      islands: const {_island: 'token'},
      layouts: _layouts,
    ),
    requirement: SurfaceFitRequirementV1(
      hosting: SurfaceHostingRequirementV1(
        contentKind: SurfaceContentKindV1.single,
        allowedPresentations: {SurfacePresentationV1.inline},
      ),
      requiredContext: SurfaceScreenHostDataSchema({
        for (final key in topLevel) key: string,
      }),
      emittedEvents: SurfaceScreenEventSchema(events: const []),
      capabilities:
          CapabilityManifest(builtInFloor: 1, requiredLibraries: const []),
      requiredVocabulary: WidgetVocabulary.empty,
      requiredIslands: island ? const {_island: 'token'} : const {},
      islandLabels: island ? const {_island: 'Badge in Plans'} : const {},
      layoutReads: SurfaceLayoutReadsV1(values: values, islands: islands),
    ),
    installed: InstalledCapability(
      builtInCatalogVersion: 5,
      installedLibraries: const [],
      vocabulary: WidgetVocabulary.empty,
    ),
  );
}

List<String> _tokens(SurfaceFitVerdictV1 verdict) =>
    [for (final failure in verdict.failures) failure.token];

void main() {
  group('layout fit', () {
    test('a read in the arm that produces it fits', () {
      expect(
        _tokens(_fit(
          topLevel: {_list},
          values: {
            _list: [
              _path({
                _branch: {1},
                _guard: {true},
                _inner: {true},
              }),
            ],
          },
        )),
        isEmpty,
      );
    });

    test('a default arm admits the rest of the domain', () {
      expect(
        _tokens(_fit(
          topLevel: {_guard},
          values: {
            _guard: [
              _path({
                _branch: ({0}, true),
              }),
            ],
          },
        )),
        isEmpty,
      );
    });

    test('a read in another arm is refused', () {
      expect(
        _tokens(_fit(
          topLevel: {_guard},
          values: {
            _guard: [
              _path({
                _branch: {0},
              }),
            ],
          },
        )),
        ['unproducedHostField:$_guard'],
      );
    });

    test('a refusal names the build and when it computes the value', () {
      final layouts = SurfaceLayoutsV1(
        domains: {
          _branch: {0, 1},
        },
        values: {
          _guard: {
            _branch: {1},
          },
        },
        build: 'PlanPicker.build',
        when: {
          _branch: {
            1: const SurfaceLayoutWhenV1(
              source: 'offer != null',
              plain: "when there's an offer",
              location: 'lib/plans.dart:12:9',
            ),
          },
        },
      );
      expect(SurfaceLayoutsV1.fromJson(layouts.toJson()).toJson(),
          layouts.toJson());
      const string = SurfaceScreenHostDataScalarShapeV1(
        SurfaceScreenHostDataScalarKind.string,
        label: 'plan.name',
      );
      final verdict = SurfaceFitEvaluator.evaluate(
        host: SurfaceHostContractV1(
          hosting: const SurfaceHostingV1(
            contentKind: SurfaceContentKindV1.single,
            presentation: SurfacePresentationV1.inline,
          ),
          providedContext: SurfaceScreenHostDataSchema({_guard: string}),
          handledEvents: SurfaceScreenEventSchema(events: const []),
          layouts: layouts,
        ),
        requirement: SurfaceFitRequirementV1(
          hosting: SurfaceHostingRequirementV1(
            contentKind: SurfaceContentKindV1.single,
            allowedPresentations: {SurfacePresentationV1.inline},
          ),
          requiredContext: SurfaceScreenHostDataSchema({_guard: string}),
          emittedEvents: SurfaceScreenEventSchema(events: const []),
          capabilities:
              CapabilityManifest(builtInFloor: 1, requiredLibraries: const []),
          requiredVocabulary: WidgetVocabulary.empty,
        ),
        installed: InstalledCapability(
          builtInCatalogVersion: 5,
          installedLibraries: const [],
          vocabulary: WidgetVocabulary.empty,
        ),
      );
      final failure = verdict.failures.single;
      expect(failure.required, 'plan.name');
      expect(failure.available, {
        'needs': {
          _branch: [1],
        },
        'build': 'PlanPicker.build',
        'when': [
          {
            'source': 'offer != null',
            'plain': "when there's an offer",
            'location': 'lib/plans.dart:12:9',
          },
        ],
      });
    });

    test('a read outside every switch is refused', () {
      expect(
          _tokens(_fit(topLevel: {_guard})), ['unproducedHostField:$_guard']);
    });

    test('a discriminator a path takes brings what it needs', () {
      // [_inner] holding means [_guard] held and the build took return 1.
      expect(
        _tokens(_fit(
          topLevel: {_list},
          values: {
            _list: [
              _path({
                _inner: {true},
              }),
            ],
          },
        )),
        isEmpty,
      );
    });

    test('an island placed in another arm is refused', () {
      expect(
        _tokens(_fit(
          island: true,
          islands: {
            _island: [
              _path({
                _branch: ({1}, true),
              }),
            ],
          },
        )),
        ['unproducedIsland:$_island'],
      );
      expect(_tokens(_fit(island: true)), ['unproducedIsland:$_island']);
    });

    test('a flow ignores single-surface layouts', () {
      final host = SurfaceHostContractV1(
        hosting: const SurfaceHostingV1(
          contentKind: SurfaceContentKindV1.flow,
          presentation: SurfacePresentationV1.inline,
        ),
        providedContext: const SurfaceScreenHostDataSchema.empty(),
        handledEvents: SurfaceScreenEventSchema(events: const []),
        flowBoundary: _boundary,
        islands: const {_island: 'token'},
        layouts: _layouts,
      );
      final verdict = SurfaceFitEvaluator.evaluate(
        host: host,
        requirement: SurfaceFitRequirementV1(
          hosting: SurfaceHostingRequirementV1(
            contentKind: SurfaceContentKindV1.flow,
            allowedPresentations: {SurfacePresentationV1.inline},
          ),
          requiredContext: const SurfaceScreenHostDataSchema.empty(),
          emittedEvents: SurfaceScreenEventSchema(events: const []),
          capabilities:
              CapabilityManifest(builtInFloor: 1, requiredLibraries: const []),
          requiredVocabulary: WidgetVocabulary.empty,
          flowBoundary: _boundary,
          requiredIslands: const {_island: 'token'},
          islandLabels: const {_island: 'Badge in Plans'},
        ),
        installed: InstalledCapability(
          builtInCatalogVersion: 5,
          installedLibraries: const [],
          vocabulary: WidgetVocabulary.empty,
        ),
      );
      expect(
        verdict.failures.map((failure) => failure.code),
        isNot(contains(SurfaceFitFailureCodeV1.unproducedIsland)),
      );
    });

    test('each flow and subflow step is checked against its own layouts', () {
      List<String> fit(Map<String, SurfaceLayoutReadsV1> reads) => _tokens(
            SurfaceFitEvaluator.evaluate(
              host: SurfaceHostContractV1(
                hosting: const SurfaceHostingV1(
                  contentKind: SurfaceContentKindV1.flow,
                  presentation: SurfacePresentationV1.inline,
                ),
                providedContext: const SurfaceScreenHostDataSchema.empty(),
                handledEvents: SurfaceScreenEventSchema(events: const []),
                flowBoundary: _boundary,
                screenLayouts: {
                  'first_run/welcome': _layouts,
                  'goal_flow/goal': _layouts,
                },
              ),
              requirement: SurfaceFitRequirementV1(
                hosting: SurfaceHostingRequirementV1(
                  contentKind: SurfaceContentKindV1.flow,
                  allowedPresentations: {SurfacePresentationV1.inline},
                ),
                requiredContext: const SurfaceScreenHostDataSchema.empty(),
                emittedEvents: SurfaceScreenEventSchema(events: const []),
                capabilities: CapabilityManifest(
                    builtInFloor: 1, requiredLibraries: const []),
                requiredVocabulary: WidgetVocabulary.empty,
                flowBoundary: _boundary,
                screenLayoutReads: reads,
              ),
              installed: InstalledCapability(
                builtInCatalogVersion: 5,
                installedLibraries: const [],
                vocabulary: WidgetVocabulary.empty,
              ),
            ),
          );
      SurfaceLayoutReadsV1 guardAt(int branch) => SurfaceLayoutReadsV1(
            values: {
              _guard: [
                _path({
                  _branch: {branch},
                }),
              ],
            },
          );
      expect(fit({'first_run/welcome': guardAt(1)}), isEmpty);
      expect(fit({'first_run/welcome': guardAt(0)}),
          ['unproducedHostField:first_run/welcome/$_guard']);
      // A subflow's screen is checked against its own step's build.
      expect(fit({'goal_flow/goal': guardAt(0)}),
          ['unproducedHostField:goal_flow/goal/$_guard']);
      // Another screen's reads don't count against this one's build.
      expect(fit({'first_run/goal': guardAt(0)}), isEmpty);
    });

    test('layouts and layout reads round-trip canonically', () {
      final reads = SurfaceLayoutReadsV1(values: {
        _list: [
          _path({
            _guard: {true},
          }),
          _path({
            _branch: ({0}, true),
          }),
          _path({
            _guard: {true},
          }),
        ],
      });
      expect(reads.values[_list], hasLength(2));
      expect(SurfaceLayoutReadsV1.fromJson(reads.toJson()).toJson(),
          reads.toJson());
      expect(SurfaceLayoutsV1.fromJson(_layouts.toJson()).toJson(),
          _layouts.toJson());
      final host = SurfaceHostContractV1(
        hosting: const SurfaceHostingV1(
          contentKind: SurfaceContentKindV1.single,
          presentation: SurfacePresentationV1.inline,
        ),
        providedContext: const SurfaceScreenHostDataSchema.empty(),
        handledEvents: SurfaceScreenEventSchema(events: const []),
        layouts: _layouts,
      );
      expect(SurfaceHostContractV1.fromJson(host.toJson()).contentHash,
          host.contentHash);
      final flowHost = SurfaceHostContractV1(
        hosting: const SurfaceHostingV1(
          contentKind: SurfaceContentKindV1.flow,
          presentation: SurfacePresentationV1.inline,
        ),
        providedContext: const SurfaceScreenHostDataSchema.empty(),
        handledEvents: SurfaceScreenEventSchema(events: const []),
        flowBoundary: _boundary,
        screenLayouts: {'welcome': _layouts, 'empty': SurfaceLayoutsV1.empty},
      );
      expect(flowHost.screenLayouts.keys, ['welcome']);
      expect(SurfaceHostContractV1.fromJson(flowHost.toJson()).contentHash,
          flowHost.contentHash);
      expect(
        () => SurfaceLayoutsV1(
          values: {
            _list: {
              _branch: {1},
            },
          },
        ),
        throwsFormatException,
      );
    });
  });
}
