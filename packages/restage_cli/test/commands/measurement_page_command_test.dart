import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/api.dart';
import 'package:restage_cli/src/commands/experiment_command.dart';
import 'package:restage_cli/src/commands/measurement_page_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    hide RuntimePlane;
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement
    show RuntimePlane;
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

final _target = TargetCoordinate(
  organizationId: OrganizationId(7),
  appId: ApplicationId(5),
  environmentTargetId: EnvironmentTargetId(13),
  namedEnvironmentId: NamedEnvironmentId(23),
  runtimePlane: measurement.RuntimePlane.live,
);

final _now = DateTime.utc(2026, 9, 16, 12);

/// The arguments each read needs beyond the target.
const _needs = <String, List<String>>{
  'analytics overview': [],
  'analytics explore': ['--dimension=platform'],
  'analytics surface': ['--surface=surface.v1.welcome'],
  'analytics taps': ['--surface=surface.v1.welcome', '--version=3'],
  'analytics health': [],
  'experiment list': [],
  'experiment results': ['--experiment=experiment.checkout'],
  'delivery map': [],
  'where': ['daily-check-in@2'],
};

String _served(Map<String, Object?> document) => jsonEncode({
  'kind': 'served',
  'projections': [
    {'document': document},
  ],
  'schemaVersion': 1,
  'surfaceTypes': <Object?>[],
  'target': _target.toJson(),
});

Map<String, Object?> _sentence(List<String> texts) => {
  'parts': [
    for (final text in texts) {'text': text},
  ],
};

void main() {
  late Directory tempDir;
  late FileCredentialStore store;
  late List<Map<String, dynamic>> sent;

  setUp(() async {
    sent = [];
    tempDir = await Directory.systemTemp.createTemp('measurement_page_');
    store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    await seedCredential(store);
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  http.Client route(String reply) => mockHttpClient((request) {
    sent.add(jsonDecode(request.body) as Map<String, dynamic>);
    return http.Response(jsonEncode(reply), 200);
  });

  Future<({int code, String out, String err})> run(
    PageRead read,
    List<String> arguments, {
    String? reply,
  }) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final runner = CommandRunner<int>('restage', '')
      ..addCommand(
        MeasurementPageCommand(
          read,
          stdout: out,
          stderr: err,
          interactive: const NonInteractive(),
          credentialStore: store,
          httpClient: route(reply ?? _served({'kind': 'page'})),
          now: () => _now,
        ),
      );
    final code = await runner.run([
      read.cliPath.split(' ').last,
      ...arguments,
      '--project',
      'p',
      '--app',
      'mobile',
      '--env',
      'production',
    ]);
    return (code: code ?? 1, out: out.toString(), err: err.toString());
  }

  PageRead readOf(String path) =>
      pageReads.singleWhere((read) => read.cliPath == path);

  test('the nine reads are defined once, each with its own tool', () {
    expect(pageReads.map((read) => read.cliPath), _needs.keys);
    expect(pageReads.map((read) => read.mcpName).toSet(), hasLength(9));
  });

  group('the delivery map', () {
    test(
      'where names one surface and version across every environment',
      () async {
        final result = await run(readOf('where'), ['daily-check-in@2']);

        expect(result.code, 0, reason: result.err);
        expect(sent.single['method'], 'readDeliveryMapPage');
        expect(sent.single['surfaceSlug'], 'daily-check-in');
        expect(sent.single['version'], 2);
        expect(sent.single['allEnvironments'], isTrue);
      },
    );

    test('where needs a surface and a whole version', () async {
      expect((await run(readOf('where'), const [])).code, 1);
      expect((await run(readOf('where'), ['daily@two'])).code, 1);
      expect(sent, isEmpty);
    });

    test('the map sends its filters and keeps the grouping local', () async {
      await run(readOf('delivery map'), [
        '--all-environments',
        '--placement=named:home',
        '--by=surface',
      ]);

      expect(sent.single['allEnvironments'], isTrue);
      expect(sent.single['placement'], 'named:home');
      expect(sent.single.containsKey('by'), isFalse);
    });

    final page = {
      'kind': 'deliveryMapPage',
      'request': {
        'fromMicros': DateTime.utc(2026, 9, 27).microsecondsSinceEpoch,
        'untilMicros': DateTime.utc(2026, 10, 4).microsecondsSinceEpoch,
      },
      'targets': [
        {
          'environment': 'staging',
          'target': {'environmentTargetId': 13, 'runtimePlane': 'sandbox'},
        },
      ],
      'builds': [
        {'platform': 'ios', 'buildOrdinal': 118, 'appVersion': '2.3'},
      ],
      'placements': {
        'values': [
          {
            'key': 'named:home',
            'label': 'home',
            'target': {'environmentTargetId': 13, 'runtimePlane': 'sandbox'},
            'screen': {'screenLabel': 'Home'},
            'resolutions': {'value': 1067},
            'edges': [
              {
                'surfaceType': 'message',
                'surfaceSlug': 'daily-check-in',
                'isDefault': true,
                'routeIds': <Object?>[],
                'routedResolutions': {'value': 1000},
                'paints': {'value': 1000},
                'flags': <Object?>[],
                'kpi': {'state': 'notAvailable'},
                'versions': [
                  {
                    'version': 2,
                    'live': true,
                    'routedResolutions': {'value': 1000},
                    'paints': {'value': 1000},
                    'paintsByBuild': [
                      {
                        'platform': 'ios',
                        'buildOrdinal': 118,
                        'count': {'value': 1000},
                      },
                    ],
                    'flags': <Object?>[],
                  },
                ],
              },
              {
                'surfaceType': 'message',
                'surfaceSlug': 'evening-check-in',
                'isDefault': false,
                'routeIds': ['evening-ritual'],
                'routedResolutions': {'state': 'unknown'},
                'paints': {'state': 'held'},
                'flags': [
                  {
                    'kind': 'cantRender',
                    'count': 7,
                    'platform': 'ios',
                    'buildOrdinal': 118,
                  },
                ],
                'kpi': {
                  'state': 'available',
                  'metric': 'Check-in started',
                  'numerator': 349,
                  'denominator': 1000,
                },
                'versions': <Object?>[],
              },
            ],
            'schedule': [
              {
                'rules': [
                  {
                    'routeId': 'evening-ritual',
                    'name': 'Evening ritual',
                    'audienceName': 'Evening users',
                  },
                ],
              },
            ],
          },
        ],
      },
      'surfaces': {
        'values': [
          {
            'surfaceType': 'message',
            'surfaceSlug': 'weekly-progress',
            'placed': false,
            'fitsPlacements': <Object?>[],
          },
        ],
      },
    };

    List<String> rows(String out) => [
      for (final line in out.split('\n'))
        if (line.trim().isNotEmpty)
          line.trim().split(RegExp(' {2,}')).join('|'),
    ];

    test('by placement prints a row per version with its shares', () async {
      final result = await run(
        readOf('delivery map'),
        const [],
        reply: _served(page),
      );

      expect(result.code, 0, reason: result.err);
      final table = rows(result.out);
      expect(
        table,
        contains(['Delivery map', 'Sep 27–Oct 3', 'staging'].join('|')),
      );
      expect(
        table,
        contains(
          [
            'PLACEMENT',
            'SCREEN',
            'SURFACE',
            'VERSION',
            'RULE',
            'AUDIENCE',
            'BUILDS',
            'CONFIGURED',
            'SEEN',
            'PAINTS',
            'KPI',
          ].join('|'),
        ),
      );
      expect(
        table,
        contains(
          [
            'home',
            'Home',
            'daily-check-in',
            'v2',
            '—',
            'Everyone',
            'iOS 2.3 (118)',
            '93.7%',
            'Unknown',
            '1,000',
            'Not available',
          ].join('|'),
        ),
      );
      expect(
        table,
        contains(
          [
            'home',
            'Home',
            'evening-check-in',
            '—',
            'Evening ritual',
            'Evening users',
            '—',
            'Unknown',
            'Unknown',
            '<5',
            'Check-in started 34.9%',
          ].join('|'),
        ),
      );
      expect(
        table,
        contains(
          [
            'home',
            'evening-check-in',
            'cant-render',
            '7 fallbacks on iOS 2.3 (118)',
          ].join('|'),
        ),
      );
      expect(table, contains(['Not placed yet', '1'].join('|')));
      expect(
        table,
        contains(['weekly-progress', 'Fits no reported placement'].join('|')),
      );
    });

    test('by surface leads with the surface and the environment', () async {
      final result = await run(readOf('delivery map'), [
        '--by=surface',
      ], reply: _served(page));

      final table = rows(result.out);
      expect(
        table,
        contains(
          [
            'SURFACE',
            'VERSION',
            'ENVIRONMENT',
            'PLANE',
            'PLACEMENT',
            'SCREEN',
            'RULE',
            'AUDIENCE',
            'BUILDS',
            'CONFIGURED',
            'SEEN',
            'PAINTS',
          ].join('|'),
        ),
      );
      expect(
        table,
        contains(
          [
            'daily-check-in',
            'v2',
            'staging',
            'sandbox',
            'home',
            'Home',
            '—',
            'Everyone',
            'iOS 2.3 (118)',
            '93.7%',
            'Unknown',
            '1,000',
          ].join('|'),
        ),
      );
    });

    test('where takes the v prefix the dashboard shows', () async {
      await run(readOf('where'), ['annual-upgrade@v4']);

      expect(sent.single['surfaceSlug'], 'annual-upgrade');
      expect(sent.single['version'], 4);
    });
  });

  group('every read', () {
    for (final entry in _needs.entries) {
      test('${entry.key} calls its method at the resolved target', () async {
        final read = readOf(entry.key);
        final result = await run(read, entry.value);

        expect(result.code, 0, reason: result.err);
        expect(sent.single['method'], read.method);
        expect(sent.single['organizationId'], 7);
        expect(sent.single['appId'], 5);
        expect(sent.single['environmentTargetId'], 13);
        expect(sent.single['namedEnvironmentId'], 23);
        expect(sent.single['runtimePlane'], 'live');
      });

      test('${entry.key} --json prints the reply unchanged', () async {
        final reply = _served({'kind': 'page', 'note': 'kept'});
        final result = await run(readOf(entry.key), [
          ...entry.value,
          '--json',
        ], reply: reply);

        expect(result.out.trim(), reply);
      });
    }
  });

  group('the window', () {
    test('ends now and runs back 30 days by default', () async {
      await run(readOf('analytics explore'), _needs['analytics explore']!);

      expect(
        sent.single['windowEndExclusiveMicros'],
        _now.microsecondsSinceEpoch,
      );
      expect(
        sent.single['windowStartMicros'],
        _now.subtract(const Duration(days: 30)).microsecondsSinceEpoch,
      );
    });

    test('is the pair the caller named', () async {
      await run(readOf('analytics overview'), [
        '--from=2026-09-01T00:00:00Z',
        '--until=2026-09-08T00:00:00Z',
      ]);

      expect(
        sent.single['windowStartMicros'],
        DateTime.utc(2026, 9).microsecondsSinceEpoch,
      );
      expect(
        sent.single['windowEndExclusiveMicros'],
        DateTime.utc(2026, 9, 8).microsecondsSinceEpoch,
      );
    });

    test('is left out of an experiment read that names none', () async {
      await run(readOf('experiment results'), _needs['experiment results']!);

      expect(sent.single.containsKey('windowStartMicros'), isFalse);
      expect(sent.single['experimentId'], 'experiment.checkout');
    });

    test('is refused when it ends before it starts', () async {
      final result = await run(readOf('analytics overview'), [
        '--from=2026-09-08T00:00:00Z',
        '--until=2026-09-01T00:00:00Z',
      ]);

      expect(result.code, 1);
      expect(sent, isEmpty);
    });
  });

  group('arguments', () {
    test('a missing required flag is named before any request', () async {
      final result = await run(readOf('analytics explore'), const []);

      expect(result.code, 1);
      expect(result.err, contains('--dimension'));
      expect(sent, isEmpty);
    });

    test('versions repeat into a list', () async {
      await run(readOf('analytics surface'), [
        ..._needs['analytics surface']!,
        '--version=r1',
        '--version=r2',
      ]);

      expect(sent.single['surfaceRevisionIds'], ['r1', 'r2']);
    });

    test('a version ordinal must be a whole number', () async {
      final result = await run(readOf('analytics taps'), [
        '--surface=s',
        '--version=abc',
      ]);

      expect(result.code, 1);
      expect(sent, isEmpty);
    });
  });

  group('human output', () {
    test(
      'prints a held count as <5 and a missing figure as Not available',
      () async {
        final result = await run(
          readOf('analytics overview'),
          const [],
          reply: _served({
            'sessions': {
              'counts': {'distinctSessions': 0},
            },
            'roster': {
              'totalMatches': 4,
              'rows': [
                {'id': 's1', 'label': 'Pro paywall'},
              ],
            },
            'rows': [
              {
                'surfaceId': 's1',
                'sessions': {
                  'value': {
                    'counts': {'rootPresentations': 1200},
                  },
                },
              },
              {'surfaceId': 's2', 'sessions': <String, Object?>{}},
            ],
          }),
        );

        expect(result.out, contains('Views: <5'));
        expect(result.out, contains('App sessions: 0'));
        expect(result.out, contains('Surfaces: 4'));
        expect(result.out, contains('Needs a look: Not available'));
        expect(result.out, contains('Pro paywall  1,200 views'));
        expect(result.out, contains('s2  Not available'));
        expect(result.out, isNot(contains('rootPresentations')));
      },
    );

    test('says only Not available for a refused read', () async {
      final reply = jsonEncode({
        'kind': 'refused',
        'reason': 'notServed',
        'detail': 'Nothing yet.',
        'schemaVersion': 1,
        'target': _target.toJson(),
      });
      final result = await run(
        readOf('analytics health'),
        const [],
        reply: reply,
      );

      expect(result.code, 0);
      expect(result.out.trim(), 'Not available');
    });

    test('labels the experiment list with lifecycle words', () async {
      final result = await run(
        readOf('experiment list'),
        const [],
        reply: _served({
          'roster': {
            'totalMatches': 2,
            'attentionCount': 1,
            'rows': [
              {'id': 'e1', 'label': 'Checkout test', 'lifecycle': 'active'},
              {'id': 'e2', 'label': 'Old test', 'lifecycle': 'concluded'},
              {'id': 'e3', 'lifecycle': 'odd'},
            ],
          },
          'summaries': [
            {
              'experimentId': 'e1',
              'summary': {
                'headline': _sentence([
                  'Pro',
                  ' beats ',
                  'Basic',
                  ' by 2.0 points.',
                ]),
                'detail': <Object?>[],
                'state': 'winner',
              },
            },
          ],
        }),
      );

      expect(result.out, contains('Checkout test  Running'));
      expect(result.out, contains('Old test  Finished'));
      expect(result.out, contains('e3  Unknown'));
      expect(
        result.out,
        contains('Checkout test  Running\n  Pro beats Basic by 2.0 points.'),
      );
    });

    test('leads an experiment result with its summary sentences', () async {
      final result = await run(
        readOf('experiment results'),
        _needs['experiment results']!,
        reply: _served({
          'detail': {'lifecycle': 'active'},
          'summary': {
            'headline': {
              'parts': [
                {'variant': 'a', 'label': 'Control'},
                {'variant': 'b', 'label': 'Pro'},
                {'text': ' Not enough data yet.'},
              ],
            },
            'detail': [
              _sentence(['60 of 100 users so far.']),
              _sentence(['Day 3 of up to 14.']),
            ],
            'state': 'enrolling',
          },
          'changes': [
            {
              'armId': 'b',
              'label': 'Pro',
              'referenceArmId': 'a',
              'referenceLabel': 'Control',
              'status': 'available',
              'moreCount': 2,
              'changes': [
                {
                  'kind': 'textChanged',
                  'line': _sentence(['Headline reads Go Pro.']),
                  'measurement': {
                    'line': _sentence(['Taps went from 3% to 5%.']),
                  },
                },
              ],
            },
            {
              'armId': 'c',
              'label': 'Annual',
              'referenceArmId': 'a',
              'referenceLabel': 'Control',
              'status': 'sameVersion',
              'moreCount': 0,
              'changes': <Object?>[],
            },
            {
              'armId': 'd',
              'label': 'Lifetime',
              'referenceArmId': 'a',
              'referenceLabel': 'Control',
              'status': 'notComparable',
              'moreCount': 0,
              'changes': <Object?>[],
            },
            {
              'armId': 'e',
              'label': 'Trial',
              'referenceArmId': 'a',
              'referenceLabel': 'Control',
              'status': 'available',
              'moreCount': 0,
              'changes': <Object?>[],
            },
          ],
        }),
      );

      expect(
        result.out,
        contains(
          'Status: Running\n'
          'Views: Not available\n'
          'App sessions: Not available\n'
          'ControlPro Not enough data yet.\n'
          '60 of 100 users so far.\n'
          'Day 3 of up to 14.\n'
          'Pro\n'
          '  Headline reads Go Pro.\n'
          '    Taps went from 3% to 5%.\n'
          '  2 more changes.\n'
          'Annual\n'
          '  Same version as Control.\n'
          'Lifetime\n'
          '  Changes not available for this version.\n'
          'Trial\n'
          '  No differences found.',
        ),
      );
    });

    test('prints Not available for a missing variant label', () async {
      final result = await run(
        readOf('experiment results'),
        _needs['experiment results']!,
        reply: _served({
          'changes': [
            {
              'armId': 'b',
              'referenceArmId': 'a',
              'status': 'sameVersion',
              'moreCount': 0,
              'changes': <Object?>[],
            },
          ],
        }),
      );

      expect(
        result.out,
        contains('Not available\n  Same version as Not available.'),
      );
    });

    test('names a variant from its own change lines', () async {
      final result = await run(
        readOf('experiment results'),
        _needs['experiment results']!,
        reply: _served({
          'changes': [
            {
              'armId': 'b',
              'label': 'Annual',
              'referenceArmId': 'a',
              'referenceLabel': 'Control',
              'status': 'available',
              'moreCount': 0,
              'changes': [
                {
                  'kind': 'added',
                  'line': {
                    'parts': [
                      {'variant': 'b', 'label': 'Annual'},
                      {'text': ' adds a badge.'},
                    ],
                  },
                },
              ],
            },
          ],
        }),
      );

      expect(result.out, contains('Annual\n  Annual adds a badge.'));
    });

    test('reads a rate as a percent with one decimal', () async {
      final result = await run(
        readOf('analytics surface'),
        _needs['analytics surface']!,
        reply: _served({
          'summary': {
            'value': {
              'counts': {'rootPresentations': 10, 'distinctSessions': 8},
            },
          },
          'metrics': [
            {
              'displayLabel': 'Purchase',
              'history': {
                'current': {
                  'summary': {
                    'counts': {'observedValue': '21', 'observedZero': '179'},
                  },
                },
              },
            },
            {'displayLabel': 'Other'},
          ],
        }),
      );

      expect(result.out, contains('Purchase: 10.5%'));
      expect(result.out, contains('Other: Not available'));
      expect(result.out, contains('Version comparisons: 0'));
    });

    test(
      'prints a funnel\'s steps and each version\'s purchase rate',
      () async {
        final result = await run(
          readOf('analytics surface'),
          _needs['analytics surface']!,
          reply: _served({
            'metrics': [
              {
                'displayLabel': 'Steps finished',
                'stepLabels': ['welcome_screen', 'flowCompleted'],
                'summary': {
                  'current': {
                    'result': {
                      'entrantCount': '200',
                      'steps': [
                        {'slotId': 'a', 'reachCount': '150'},
                        {'slotId': 'b', 'reachCount': '60'},
                      ],
                    },
                  },
                },
              },
            ],
            'metadata': {'surfaceTypeWireName': 'paywall'},
            'purchaseRate': {
              'status': 'available',
              'versions': [
                {'publishedVersion': 2, 'purchases': 12, 'views': 400},
                {'publishedVersion': 1, 'views': 90},
              ],
            },
          }),
        );

        expect(
          result.out,
          contains(
            'Steps finished\n'
            '  Welcome screen  150 reached  75.0%\n'
            '  Finished  60 reached  30.0%\n',
          ),
        );
        expect(
          result.out,
          contains(
            'Purchase rate\n'
            '  v2  12 first purchases  400 views  3.0%\n'
            '  v1  <5 first purchases  90 views  Not available',
          ),
        );
      },
    );

    test('states why a purchase rate is missing', () async {
      final notConnected = await run(
        readOf('analytics surface'),
        _needs['analytics surface']!,
        reply: _served({
          'metadata': {'surfaceTypeWireName': 'paywall'},
          'purchaseRate': {
            'status': 'commerceNotConnected',
            'versions': <Object?>[],
          },
        }),
      );
      final absent = await run(
        readOf('analytics surface'),
        _needs['analytics surface']!,
        reply: _served({
          'metadata': {'surfaceTypeWireName': 'paywall'},
        }),
      );
      final onboarding = await run(
        readOf('analytics surface'),
        _needs['analytics surface']!,
        reply: _served({
          'metadata': {'surfaceTypeWireName': 'onboarding'},
        }),
      );

      expect(onboarding.out, isNot(contains('Purchase rate')));
      expect(
        notConnected.out,
        contains('Purchase rate: Connect a store to see purchases.'),
      );
      expect(absent.out, contains('Purchase rate: Not available'));
    });

    test('lists a version\'s busiest elements with held taps as <5', () async {
      final result = await run(
        readOf('analytics taps'),
        _needs['analytics taps']!,
        reply: _served({
          'surfaceId': 's1',
          'disclosureFloor': 5,
          'versions': [
            {
              'revisionOrdinal': 3,
              'rootCounts': {'presented': 1500},
              'taps': [
                {'eventName': 'close'},
                {'eventName': 'buy', 'reach': 900},
              ],
            },
          ],
        }),
      );

      expect(result.out, contains('Reporting floor: 5 users'));
      expect(result.out, contains('v3  1,500 views'));
      final lines = result.out.split('\n');
      expect(
        lines.indexOf('  buy  900 taps'),
        lessThan(lines.indexOf('  close  <5 taps')),
      );
    });
  });

  group('--all-apps', () {
    final apps = {
      'totals': {
        'sessions': {
          'value': 1000,
          'approximate': false,
          'atLeast': false,
          'unavailable': false,
        },
        'flowsFinished': {
          'approximate': false,
          'atLeast': false,
          'unavailable': true,
        },
        'flowsEligible': {
          'approximate': false,
          'atLeast': false,
          'unavailable': true,
        },
        'revenue': {
          'earning': true,
          'grossUsdMicros': 4000000000,
          'approximate': false,
          'unconverted': false,
        },
      },
      'apps': [
        {
          'appId': '1',
          'appName': 'Stride',
          'figures': {
            'sessions': {
              'value': 250,
              'approximate': true,
              'atLeast': false,
              'unavailable': false,
            },
            'flowsFinished': {
              'value': 30,
              'atLeast': false,
              'approximate': false,
              'unavailable': false,
            },
            'flowsEligible': {
              'value': 120,
              'atLeast': false,
              'approximate': false,
              'unavailable': false,
            },
            'revenue': {
              'earning': true,
              'grossUsdMicros': 1000000000,
              'approximate': false,
              'unconverted': true,
            },
          },
        },
        {
          'appId': '2',
          'appName': 'Lumen',
          'figures': {
            'sessions': {
              'value': 40,
              'atLeast': true,
              'approximate': false,
              'unavailable': false,
            },
            'flowsFinished': {
              'atLeast': false,
              'approximate': false,
              'unavailable': true,
            },
            'flowsEligible': {
              'approximate': false,
              'atLeast': false,
              'unavailable': true,
            },
            'revenue': {
              'earning': false,
              'approximate': false,
              'unconverted': false,
            },
          },
        },
      ],
    };

    test('calls the organization-wide read without an app', () async {
      final result = await run(readOf('analytics overview'), const [
        '--all-apps',
      ], reply: _served(apps));

      expect(result.code, 0, reason: result.err);
      expect(sent.single['method'], 'readOverviewAppsPage');
      expect(sent.single['organizationId'], 7);
      expect(sent.single['namedEnvironmentId'], 23);
      expect(sent.single['runtimePlane'], 'live');
      expect(sent.single.containsKey('appId'), isFalse);
      expect(sent.single.containsKey('queryBytes'), isFalse);
      expect(sent.single['granularity'], 'day');
    });

    test('prints each figure as a total and a line per app', () async {
      final result = await run(readOf('analytics overview'), const [
        '--all-apps',
      ], reply: _served(apps));

      expect(
        result.out,
        contains(
          'App sessions that saw a surface\n'
          '1,000\n'
          '  Stride  ≈250  25% of total\n'
          '  Lumen  At least 40  4% of total\n'
          'Onboarding and surveys finished\n'
          'Not available\n'
          '  Stride  25.0%\n'
          '  Lumen  Not available\n'
          'Revenue from surfaces\n'
          '\$4,000\n'
          '  Stride  \$1,000 so far  25% of total\n'
          '  Lumen  Not available',
        ),
      );
    });

    test(
      'revenue totals distinguish unavailable amounts from measured zero',
      () async {
        for (final (gross, unconverted, expected) in [
          (0, true, 'Not available'),
          (0, false, r'$0'),
          (1000000000, true, r'$1,000 so far'),
        ]) {
          final result = await run(
            readOf('analytics overview'),
            const ['--all-apps'],
            reply: _served({
              'totals': {
                'revenue': {
                  'earning': true,
                  'grossUsdMicros': gross,
                  'unconverted': unconverted,
                },
              },
            }),
          );
          expect(result.code, 0, reason: result.err);
          expect(result.out, contains('Revenue from surfaces\n$expected\n'));
        }
      },
    );

    test(
      'an unconverted app amount never claims a zero revenue share',
      () async {
        final result = await run(
          readOf('analytics overview'),
          const ['--all-apps'],
          reply: _served({
            'totals': {
              'revenue': {'earning': true, 'grossUsdMicros': 1000000000},
            },
            'apps': [
              {
                'appName': 'Stride',
                'figures': {
                  'revenue': {
                    'earning': true,
                    'grossUsdMicros': 0,
                    'unconverted': true,
                  },
                },
              },
            ],
          }),
        );
        expect(result.code, 0, reason: result.err);
        expect(
          result.out,
          contains('Revenue from surfaces\n\$1,000\n  Stride  Not available\n'),
        );
      },
    );

    test('--json prints the reply unchanged', () async {
      final reply = _served(apps);
      final result = await run(readOf('analytics overview'), const [
        '--all-apps',
        '--json',
      ], reply: reply);

      expect(result.out.trim(), reply);
    });

    test('a held app revenue prints Hidden for privacy', () async {
      final held = jsonDecode(jsonEncode(apps)) as Map<String, Object?>;
      final first = (held['apps']! as List).first as Map<String, Object?>;
      (first['figures']! as Map<String, Object?>)['revenue'] = {
        'earning': true,
        'approximate': false,
        'unconverted': false,
      };
      final result = await run(readOf('analytics overview'), const [
        '--all-apps',
      ], reply: _served(held));

      expect(result.code, 0, reason: result.err);
      expect(result.out, contains('  Stride  Hidden for privacy'));
    });

    test('a reply naming another app\'s own environment is refused', () async {
      final reply = jsonEncode({
        'kind': 'served',
        'projections': [
          {'document': apps},
        ],
        'target': TargetCoordinate(
          organizationId: OrganizationId(7),
          appId: ApplicationId(99),
          environmentTargetId: EnvironmentTargetId(77),
          namedEnvironmentId: NamedEnvironmentId(24),
          runtimePlane: measurement.RuntimePlane.live,
        ).toJson(),
      });
      final result = await run(readOf('analytics overview'), const [
        '--all-apps',
      ], reply: reply);

      expect(result.code, 2);
    });
  });

  test('a reply for another target is refused', () async {
    final other = jsonEncode({
      'kind': 'served',
      'projections': [
        {'document': <String, Object?>{}},
      ],
      'target': TargetCoordinate(
        organizationId: OrganizationId(8),
        appId: ApplicationId(5),
        environmentTargetId: EnvironmentTargetId(13),
        namedEnvironmentId: NamedEnvironmentId(23),
        runtimePlane: measurement.RuntimePlane.live,
      ).toJson(),
    });
    final result = await run(
      readOf('analytics health'),
      const [],
      reply: other,
    );

    expect(result.code, 2);
    expect(result.out, isEmpty);
  });

  test('experiment reads and authoring are visible by default', () {
    final command = ExperimentCommand(
      stdout: StringBuffer(),
      stderr: StringBuffer(),
      interactive: const NonInteractive(),
    );

    expect(command.hidden, isFalse);
    expect(command.subcommands['list']!.hidden, isFalse);
    expect(command.subcommands['results']!.hidden, isFalse);
    expect(command.subcommands['create']!.hidden, isFalse);
  });
}
