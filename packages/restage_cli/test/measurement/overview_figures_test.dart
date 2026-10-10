import 'dart:convert';

import 'package:restage_cli/src/measurement/overview_figures.dart';
import 'package:restage_cli/src/measurement/page_views/overview_apps_view.dart';
import 'package:test/test.dart';

String _reply(Map<String, Object?> document) => jsonEncode({
  'kind': 'served',
  'projections': [
    {'document': document},
  ],
});

Map<String, Object?> _series({
  int publications = 2,
  int unsupported = 0,
  Object? completed = 21,
  int eligible = 200,
}) => {
  'publicationCount': publications,
  'unsupportedPublicationCount': unsupported,
  'windowCounts': {'eligibleRoots': eligible, 'completed': ?completed},
};

Map<String, Object?> _row(List<Map<String, Object?>> revenues) => {
  'surfaceId': 's',
  'activity': {
    'values': [
      for (final revenue in revenues)
        {
          'revisionOrdinal': 1,
          'series': {'revenue': revenue},
        },
    ],
  },
};

void main() {
  test('states each figure the way the dashboard does', () {
    final figures = overviewFiguresOf(
      _reply({
        'sessions': {
          'counts': {'distinctKnownSessions': 1500, 'distinctSessions': 1500},
        },
        'typedLifecycle': _series(),
        'rows': [
          _row([
            {
              'kind': 'available',
              'grossUsdMicros': [1500000000, 2600000000],
            },
          ]),
        ],
      }),
    );

    expect(figures.sessions, '1,500');
    expect(figures.finished, '10.5%');
    expect(figures.revenue, r'$4,100');
  });

  test(
    'counts onboarding and survey surfaces only, never the all-type series',
    () {
      final figures = overviewFiguresOf(
        _reply({
          'sessions': {'counts': <String, Object?>{}},
          'lifecycle': _series(completed: 100, eligible: 200),
          'typedLifecycle': _series(completed: 50, eligible: 200),
          'rows': <Object?>[],
        }),
      );

      expect(figures.finished, '25%');
    },
  );

  test('a held count reads <5 and an unread figure reads Not available', () {
    final figures = overviewFiguresOf(
      _reply({
        'sessions': {'counts': <String, Object?>{}},
        'typedLifecycle': _series(completed: null),
        'rows': [_row([])],
      }),
    );

    expect(figures.sessions, '<5');
    expect(figures.finished, '<5');
    expect(figures.revenue, 'Not available');
  });

  test('sessions with no exact union read At least the known count', () {
    final figures = overviewFiguresOf(
      _reply({
        'sessions': {
          'counts': {'distinctKnownSessions': 900},
        },
        'typedLifecycle': _series(publications: 0),
        'rows': <Object?>[],
      }),
    );

    expect(figures.sessions, 'At least 900');
    expect(figures.finished, 'Not available');
  });

  test('revenue without an exchange rate is left out and says so', () {
    final figures = overviewFiguresOf(
      _reply({
        'sessions': {'counts': <String, Object?>{}},
        'typedLifecycle': _series(),
        'rows': [
          _row([
            {
              'kind': 'available',
              'grossUsdMicros': [3000000000],
            },
            {'kind': 'unavailable', 'reason': 'currencyRateUnavailable'},
          ]),
        ],
      }),
    );

    expect(figures.revenue, r'$3,000 so far');
  });

  test('a reply with no page states nothing', () {
    expect(overviewFiguresOf('{"kind":"refused"}').sessions, 'Not available');
    expect(overviewFiguresOf('nope').revenue, 'Not available');
  });

  test('states one line per app under each figure', () {
    final lines = overviewAppLinesOf(
      _reply({
        'apps': [
          {
            'appName': 'Stride',
            'figures': {
              'sessions': {'value': 250, 'approximate': true},
              'flowsFinished': {'value': 25},
              'flowsEligible': {'value': 100},
              'revenue': {'earning': true, 'grossUsdMicros': 1000000000},
            },
          },
          {
            'appName': 'Lumen',
            'figures': {
              'sessions': {'unavailable': true},
              'flowsFinished': {'unavailable': true},
              'flowsEligible': {'unavailable': true},
              'revenue': {'earning': false},
            },
          },
        ],
      }),
    );

    expect(lines['sessions'], ['Stride ≈250', 'Lumen Not available']);
    expect(lines['finished'], ['Stride 25.0%', 'Lumen Not available']);
    expect(lines['revenue'], [r'Stride $1,000', 'Lumen Not available']);
  });
}
