import 'dart:convert';
import 'dart:io';

import 'package:restage_cli/src/render_bundles/surface_capture_source.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/publication_fixtures.dart';

const _paywall = 'package:demo/paywalls/pro_upgrade.dart';
const _screen = 'package:demo/screens/checklist_screen.dart';

Map<String, Object?> _object(
  String name,
  List<Map<String, Object?>> parameters, {
  String library = _paywall,
}) => {
  'kind': 'object',
  'importUri': library,
  'name': name,
  'parameters': parameters,
};

Map<String, Object?> _parameter(
  String name,
  Map<String, Object?> type, {
  bool named = true,
  bool required = true,
  bool hasDefault = false,
  String? sampleKey,
  bool unbound = false,
}) => {
  'name': name,
  'named': named,
  'required': required,
  'hasDefault': hasDefault,
  'sampleKey': unbound ? null : sampleKey ?? name,
  'type': type,
};

Map<String, Object?> _nullable(Map<String, Object?> type) => {
  ...type,
  'nullable': true,
};

Map<String, Object?> _list(Map<String, Object?> item) => {
  'kind': 'list',
  'item': item,
};

const _string = {'kind': 'string'};
const _bool = {'kind': 'bool'};
const _int = {'kind': 'int'};

/// The `super.key` every widget constructor carries.
final _key = _parameter(
  'key',
  _nullable({'kind': 'unbuildable', 'display': 'Key?'}),
  required: false,
);

void main() {
  late Directory app;

  setUp(() async {
    app = await Directory.systemTemp.createTemp('surface_capture_source_');
  });

  tearDown(() => app.deleteSync(recursive: true));

  String source(
    Map<String, Object?>? plan, {
    Map<String, Object?> sample = const <String, Object?>{},
    List<String>? placeholders,
  }) => surfaceCaptureTestSource(
    appName: 'demo',
    plan: plan,
    name: 'paywall.pro_upgrade',
    sample: sample,
    placeholders: placeholders,
  );

  Matcher refusal(Object reason) => throwsA(
    isA<SurfaceCaptureSourceException>().having(
      (error) => error.reason,
      'reason',
      reason,
    ),
  );

  test('builds the authored widget its plan names', () {
    final text = source(_object('ProUpgradePaywall', [_key]));

    expect(
      text,
      contains("import 'package:demo/paywalls/pro_upgrade.dart' as "),
    );
    expect(text, contains('return restage_capture_type0.ProUpgradePaywall();'));
  });

  test('says why a surface its build did not plan has no image', () {
    expect(() => source(null), refusal('its widget was not found'));
  });

  test('draws a non-nullable bool that has no sample', () {
    expect(
      source(
        _object('ProUpgradePaywall', [_key, _parameter('entitled', _bool)]),
      ),
      contains('ProUpgradePaywall(entitled: false)'),
    );
  });

  test('reports the fields drawn with placeholder values', () {
    final placeholders = <String>[];
    source(
      _object('ProUpgradePaywall', [
        _key,
        _parameter('entitled', _bool),
        _parameter('title', _string),
      ]),
      placeholders: placeholders,
    );

    expect(placeholders, [
      'ProUpgradePaywall.entitled',
      'ProUpgradePaywall.title',
    ]);
  });

  test('uses an enum\'s first value', () {
    expect(
      source(
        _object('ProUpgradePaywall', [
          _key,
          _parameter('tier', {
            'kind': 'enum',
            'importUri': 'package:demo/paywalls/tier.dart',
            'name': 'Tier',
            'values': ['free', 'pro'],
          }),
        ]),
      ),
      contains('tier: restage_capture_type1.Tier.free'),
    );
  });

  for (final (type, expected) in [
    ('DateTime', 'DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)'),
    ('Duration', 'Duration.zero'),
    ('Color', 'const restage_capture_widgets.Color(0xFF000000)'),
  ]) {
    test('draws a $type it has no sample for from a neutral value', () {
      final placeholders = <String>[];
      expect(
        source(
          _object('ProUpgradePaywall', [
            _key,
            _parameter('value', {'kind': 'value', 'name': type}),
          ]),
          placeholders: placeholders,
        ),
        contains('ProUpgradePaywall(value: $expected)'),
      );
      expect(placeholders, ['ProUpgradePaywall.value']);
    });
  }

  test('a non-nullable Object has no sample to build', () {
    expect(
      () => source(
        _object('ProUpgradePaywall', [
          _key,
          _parameter('payload', {'kind': 'json'}),
        ]),
      ),
      refusal(contains('(`Object`)')),
    );
  });

  test('names the type when it cannot build a sample', () {
    expect(
      () => source(
        _object('ProUpgradePaywall', [
          _key,
          _parameter('clock', {
            'kind': 'unbuildable',
            'display': 'DateTime Function()',
          }),
        ]),
      ),
      refusal(
        "its host data `ProUpgradePaywall.clock` has a type the preview "
        "can't build a sample of (`DateTime Function()`). Give the parameter "
        'a default value to draw the image',
      ),
    );
  });

  test('fills a screen\'s host data with sample values', () {
    final text = source(
      _object('Checklist', [
        _parameter('owner', _string),
        _parameter(
          'items',
          _list(
            _object('ChecklistItem', [
              _parameter('title', _string),
              _parameter('done', _bool),
            ], library: _screen),
          ),
        ),
        _key,
      ], library: _screen),
      sample: const <String, Object?>{
        'owner': 'Ada',
        'items': [
          {'title': 'First', 'done': true},
        ],
      },
    );

    expect(
      text,
      contains(
        "return restage_capture_type0.Checklist(owner: 'Ada', items: "
        "[restage_capture_type0.ChecklistItem(title: 'First', done: true)]);",
      ),
    );
  });

  test('builds host data typed by a package the app imports', () {
    final text = source(
      _object('Checklist', [
        _parameter(
          'steps',
          _list(
            _object('VTimelineStep', [
              _parameter('label', _string),
              _parameter(
                'marker',
                _object('VTimelineMarker', [
                  _parameter('done', _bool),
                ], library: 'package:timeline_ui/src/marker.dart'),
              ),
            ], library: 'package:timeline_ui/src/timeline.dart'),
          ),
        ),
        _key,
      ], library: _screen),
      sample: const <String, Object?>{
        'steps': [
          {
            'label': 'First',
            'marker': {'done': true},
          },
        ],
      },
    );

    expect(
      text,
      contains(
        "import 'package:timeline_ui/src/timeline.dart' as "
        'restage_capture_type1;',
      ),
    );
    expect(
      text,
      contains(
        "import 'package:timeline_ui/src/marker.dart' as "
        'restage_capture_type2;',
      ),
    );
    expect(
      text,
      contains(
        'return restage_capture_type0.Checklist(steps: '
        "[restage_capture_type1.VTimelineStep(label: 'First', marker: "
        'restage_capture_type2.VTimelineMarker(done: true))]);',
      ),
    );
  });

  test('says why a widget it cannot construct has no image', () {
    expect(
      () => source({'kind': 'unconstructible', 'name': 'Checklist'}),
      refusal('its widget Checklist has no constructor this can call'),
    );
  });

  test('says why a type private to its library has no image', () {
    expect(
      () => source(
        _object('ProUpgrade', [
          _parameter('hidden', {'kind': 'private', 'name': '_Hidden'}),
        ]),
        sample: const <String, Object?>{
          'hidden': {'note': 'kept'},
        },
      ),
      refusal('its host data type `_Hidden` is private to its library'),
    );
    // An optional one it can leave out does not stop the image.
    expect(
      source(
        _object('ProUpgrade', [
          _parameter(
            'hidden',
            _nullable({'kind': 'private', 'name': '_Hidden'}),
            required: false,
          ),
        ]),
      ),
      contains('return restage_capture_type0.ProUpgrade();'),
    );
  });

  test('reports a parameter no field holds as drawn without its sample', () {
    final placeholders = <String>[];
    final text = source(
      _object('ProUpgrade', [
        _parameter(
          'fallback',
          _object('Fallback', [
            _parameter(
              'amount',
              _nullable(_string),
              required: false,
              unbound: true,
            ),
          ]),
        ),
        _parameter(
          'price',
          _object('Price', [_parameter('amount', _string, unbound: true)]),
        ),
      ]),
      sample: const <String, Object?>{
        'fallback': {'label': r'$5', 'amount': 'unrelated'},
        'price': {'label': r'$5'},
      },
      placeholders: placeholders,
    );

    expect(text, contains('restage_capture_type0.Fallback()'));
    expect(text, contains("restage_capture_type0.Price(amount: '')"));
    expect(placeholders, [
      'ProUpgrade.fallback.amount',
      'ProUpgrade.price.amount',
    ]);
  });

  test('refuses a flow whose ref is private to its library', () {
    expect(
      () => source({
        'kind': 'flow',
        'importUri': 'package:demo/flows/tour.dart',
        'ref': '_tourFlowRef',
      }),
      refusal('its flow is private to its library'),
    );
  });

  test('draws a flow from its first screen', () {
    final text = source({
      'kind': 'flow',
      'importUri': 'package:demo/flows/tour.dart',
      'ref': 'tourFlowRef',
    });

    expect(text, contains('return restage_capture.flowEntry(tourFlowRef);'));
    expect(text, contains("import 'package:demo/flows/tour.dart';"));
  });

  test('leaves out an optional parameter with a default', () {
    expect(
      source(
        _object('ProUpgrade', [
          _parameter('title', _string),
          _parameter(
            'tags',
            {'kind': 'map', 'value': _string},
            required: false,
            hasDefault: true,
          ),
          _key,
        ]),
        sample: const <String, Object?>{'title': 'Go Pro'},
      ),
      contains("return restage_capture_type0.ProUpgrade(title: 'Go Pro');"),
    );
  });

  test('passes positionals in order and leaves out trailing defaults', () {
    expect(
      source(
        _object('ProUpgrade', [
          _parameter('title', _string, named: false),
          _parameter(
            'count',
            _int,
            named: false,
            required: false,
            hasDefault: true,
          ),
        ]),
        sample: const <String, Object?>{'title': 'Go Pro'},
      ),
      contains("return restage_capture_type0.ProUpgrade('Go Pro');"),
    );
  });

  test('fills a set from a list sample', () {
    expect(
      source(
        _object('ProUpgrade', [
          _parameter('ids', {'kind': 'set', 'item': _string}),
        ]),
        sample: const <String, Object?>{
          'ids': ['a', 'b'],
        },
      ),
      contains("ProUpgrade(ids: {'a', 'b'})"),
    );
  });

  group('the shapes the build resolves for the app', () {
    // Plans as the compiler writes them for the same source, which a text
    // scan of the source refused.
    test('a field typed through a typedef', () {
      expect(
        source(
          _object('ProUpgradePaywall', [
            _key,
            _parameter(
              'steps',
              _list(_object('Step', [_parameter('label', _string)])),
            ),
          ]),
          sample: const <String, Object?>{
            'steps': [
              {'label': 'First'},
            ],
          },
        ),
        contains(
          "ProUpgradePaywall(steps: [restage_capture_type0.Step(label: "
          "'First')])",
        ),
      );
    });

    test('a widget taking a plain Key? key', () {
      expect(
        source(
          _object('ProUpgradePaywall', [_key, _parameter('title', _string)]),
          sample: const <String, Object?>{'title': 'Hi'},
        ),
        contains("ProUpgradePaywall(title: 'Hi')"),
      );
    });

    test('a constructor that assigns a field in its initializer list', () {
      expect(
        source(
          _object('ProUpgradePaywall', [
            _key,
            _parameter(
              'steps',
              _list(
                _object('Step', [
                  _parameter('name', _string, sampleKey: 'label'),
                ]),
              ),
            ),
          ]),
          sample: const <String, Object?>{
            'steps': [
              {'label': 'First'},
            ],
          },
        ),
        contains("restage_capture_type0.Step(name: 'First')"),
      );
    });

    test('fields declared together', () {
      expect(
        source(
          _object('ProUpgradePaywall', [
            _key,
            _parameter(
              'steps',
              _list(
                _object('Step', [
                  _parameter('note', _string),
                  _parameter('hint', _string),
                ]),
              ),
            ),
          ]),
          sample: const <String, Object?>{
            'steps': [
              {'note': 'n', 'hint': 'h'},
            ],
          },
        ),
        contains("restage_capture_type0.Step(note: 'n', hint: 'h')"),
      );
    });

    test('a comment inside a field type', () {
      expect(
        source(
          _object('ProUpgradePaywall', [_key, _parameter('title', _string)]),
          sample: const <String, Object?>{'title': 'Hi'},
        ),
        contains("ProUpgradePaywall(title: 'Hi')"),
      );
    });
  });

  group('the render context of values the app computes', () {
    final withAppValue = SurfaceScreenHostDataSchema({
      'owner': const SurfaceScreenHostDataScalarShapeV1(
        SurfaceScreenHostDataScalarKind.string,
      ),
      '_h0123456789': const SurfaceScreenHostDataScalarShapeV1(
        SurfaceScreenHostDataScalarKind.integer,
      ),
    });

    /// [entry] with the generated widget named [mountName].
    SurfacePublicationManifestEntry mounted(
      SurfacePublicationManifestEntry entry,
      String mountName,
    ) {
      final json =
          jsonDecode(jsonEncode(entry.toJson())) as Map<String, Object?>;
      (json['publication']! as Map<String, Object?>)['mountName'] = mountName;
      return SurfacePublicationManifestEntry.fromJson(json, path: 'entry');
    }

    Future<String?> contextSource(
      SurfaceScreenHostDataSchema schema,
      Map<String, Object?> plan, {
      Surface surface = Surface.paywall,
      String? mountName,
    }) async {
      var entry = await seedGeneratedPaywall(
        app,
        slug: 'pro_upgrade',
        surface: surface,
        hostDataContract: schema,
      );
      if (mountName != null) entry = mounted(entry, mountName);
      return surfaceContextTestSource(
        appName: 'demo',
        entry: entry,
        plan: plan,
        name: '${surface.wireName}.pro_upgrade',
        sample: sampleHostContext(schema),
      );
    }

    test(
      'native declarations are app values with no fabricated JSON sample',
      () async {
        const native = SurfaceScreenHostDataNativeBindingShapeV1(
          NativeBindingContract(type: 'flutter.TextScaler', nullable: true),
          label: 'scaler',
        );
        final schema = SurfaceScreenHostDataSchema({
          'nested': SurfaceScreenHostDataObjectShapeV1(const {
            'binding': native,
          }),
        });
        expect(hostDataHasAppValues(schema), isTrue);
        expect(hostDataAppValueLabels(schema), ['scaler']);
        expect(
          () => sampleSurfaceCaptureContext(schema),
          throwsA(
            isA<SurfaceCaptureSourceException>().having(
              (error) => error.reason,
              'reason',
              contains('native bindings require an installed host'),
            ),
          ),
        );
        final entry = await seedGeneratedPaywall(
          app,
          surface: Surface.general,
          hostDataContract: schema,
        );
        expect(
          () => surfaceContextTestSource(
            appName: 'demo',
            entry: entry,
            plan: null,
            name: 'paywall.pro_upgrade',
            sample: const {},
          ),
          throwsA(isA<SurfaceCaptureSourceException>()),
        );
      },
    );

    test('records them through the generated widget', () async {
      final text = await contextSource(
        withAppValue,
        _object('ChecklistScreen', [
          _key,
          _parameter('owner', _string),
        ], library: _screen),
        surface: Surface.onboarding,
        mountName: 'ChecklistSurface',
      );
      expect(text, contains('restage_capture.captureContext('));
      expect(
        text,
        contains(
          "return restage_capture_type0.ChecklistSurface(owner: 'Owner');",
        ),
      );
    });

    test('records a paywall, sampling a list its contract omits', () async {
      final schema = SurfaceScreenHostDataSchema({
        'title': const SurfaceScreenHostDataScalarShapeV1(
          SurfaceScreenHostDataScalarKind.string,
        ),
        '_h0123456789': const SurfaceScreenHostDataScalarShapeV1(
          SurfaceScreenHostDataScalarKind.integer,
        ),
      });
      final text = await contextSource(
        schema,
        _object('ProUpgrade', [
          _parameter('title', _string),
          _parameter(
            'plans',
            _list(
              _object('Plan', [
                _parameter('label', _string, required: false, hasDefault: true),
                _parameter('badge', _nullable(_string), required: false),
              ], library: 'package:demo/paywalls/plan.dart'),
            ),
          ),
          _parameter('tags', _list(_string)),
          _key,
        ]),
      );

      expect(text, contains('restage_capture.captureContext('));
      expect(
        text,
        contains(
          "return restage_capture_type0.ProUpgradeSurface(title: 'Title', "
          'plans: [restage_capture_type1.Plan(), '
          'restage_capture_type1.Plan()], tags: const []);',
        ),
      );
    });

    test('fills a type that contains itself with an empty list', () async {
      final schema = SurfaceScreenHostDataSchema({
        'title': const SurfaceScreenHostDataScalarShapeV1(
          SurfaceScreenHostDataScalarKind.string,
        ),
        '_h0123456789': const SurfaceScreenHostDataScalarShapeV1(
          SurfaceScreenHostDataScalarKind.integer,
        ),
      });
      const section = 'package:demo/paywalls/section.dart';
      final text = await contextSource(
        schema,
        _object('ProUpgrade', [
          _parameter('title', _string),
          _parameter(
            'sections',
            _list(
              _object('Section', [
                _parameter('title', _string),
                _parameter(
                  'children',
                  _list({'kind': 'recursive', 'name': 'Section'}),
                ),
              ], library: section),
            ),
          ),
          _key,
        ]),
      );

      const built =
          "restage_capture_type1.Section(title: '', children: const [])";
      expect(
        text,
        contains(
          "return restage_capture_type0.ProUpgradeSurface(title: 'Title', "
          'sections: [$built, $built]);',
        ),
      );
    });

    test('skips a surface with none', () async {
      final text = await contextSource(
        SurfaceScreenHostDataSchema({
          'owner': const SurfaceScreenHostDataScalarShapeV1(
            SurfaceScreenHostDataScalarKind.string,
          ),
        }),
        _object('ProUpgrade', [_parameter('owner', _string)]),
      );
      expect(text, isNull);
    });

    test('names each value by the expression it comes from', () {
      expect(
        hostDataAppValueLabels(
          SurfaceScreenHostDataSchema({
            '_h0123456789': const SurfaceScreenHostDataScalarShapeV1(
              SurfaceScreenHostDataScalarKind.integer,
            ).withLabel('VColors.of(context).ink'),
            'plants': SurfaceScreenHostDataListShapeV1(
              SurfaceScreenHostDataObjectShapeV1({
                '_hfedcba9876': const SurfaceScreenHostDataScalarShapeV1(
                  SurfaceScreenHostDataScalarKind.integer,
                ).withLabel('Tones.of(context).colorFor(plant.tone)'),
              }),
            ),
          }),
        ),
        ['Tones.of(context).colorFor(plant.tone)', 'VColors.of(context).ink'],
      );
    });

    test('finds a value carried by each item of a list', () {
      expect(
        hostDataHasAppValues(
          SurfaceScreenHostDataSchema({
            'plants': SurfaceScreenHostDataListShapeV1(
              SurfaceScreenHostDataObjectShapeV1({
                '_hfedcba9876': const SurfaceScreenHostDataScalarShapeV1(
                  SurfaceScreenHostDataScalarKind.integer,
                ),
              }),
            ),
          }),
        ),
        isTrue,
      );
    });
  });

  group('the support library', () {
    String support({required bool readsPaywallContext}) =>
        surfaceCaptureSupportSource(
          width: 390,
          height: 844,
          fontFiles: const <String, List<String>>{},
          readsPaywallContext: readsPaywallContext,
        );

    test('reads a paywall context through the SDK when it can', () {
      expect(
        support(readsPaywallContext: true),
        allOf(
          contains(
            "import 'package:restage/render_support.dart' "
            'show paywallHostContext;',
          ),
          contains('? paywallHostContext(surface)'),
        ),
      );
    });

    test('compiles against an SDK without the paywall reader', () {
      final text = support(readsPaywallContext: false);
      expect(text, isNot(contains('render_support')));
      expect(text, isNot(contains('paywallHostContext')));
    });
  });
}
