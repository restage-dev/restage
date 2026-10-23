import 'dart:convert';

import 'package:restage_cli/src/delivery/fit_report.dart';
import 'package:test/test.dart';

List<int> _verdict(List<Map<String, Object?>> failures) => utf8.encode(
  jsonEncode({
    'kind': 'surfaceFitVerdict',
    'accepted': failures.isEmpty,
    'failures': failures,
  }),
);

void main() {
  test('an accepted verdict fits', () {
    expect(describeFitVerdict(_verdict(const [])), ['fits']);
  });

  test('a placement no build has shown is not checked yet', () {
    expect(
      describeFitVerdict(
        _verdict(const [
          {
            'code': 'missingRequirement',
            'path': r'$.reportingCensus',
            'required':
                'An app build that showed this placement in the last 30 days',
            'available': null,
          },
        ]),
      ),
      [
        'not checked yet; needs an app build that showed this placement in '
            'the last 30 days',
      ],
    );
  });

  test('missing host fields collapse into one line, other reasons follow', () {
    expect(
      describeFitVerdict(
        _verdict(const [
          {
            'code': 'hostingMismatch',
            'path': r'$.hosting',
            'required': {
              'allowedPresentations': ['inline', 'presented'],
              'contentKind': 'single',
            },
            'available': {'contentKind': 'flow', 'presentation': 'inline'},
          },
          {
            'code': 'missingHostField',
            'path': r'$.requiredContext.activePlan',
            'required': {'kind': 'string'},
            'available': null,
          },
          {
            'code': 'missingHostField',
            'path': r'$.requiredContext.busy',
            'required': {'kind': 'bool'},
            'available': null,
          },
          {
            'code': 'missingHostField',
            'path': r'$.requiredContext.busy',
            'required': {'kind': 'bool'},
            'available': null,
          },
          {
            'code': 'unhandledEvent',
            'path': r'$.emittedEvents.restore',
            'required': null,
            'available': null,
          },
        ]),
      ),
      [
        'does not fit',
        'the app does not pass `activePlan`, `busy` to this placement',
        'the surface is one screen; this placement shows a flow',
        'the app does not handle the event `restore` here',
      ],
    );
  });

  test('a push reports placements the surface fits or that show it', () {
    List<int> verdict({required bool accepted, bool? shows}) => utf8.encode(
      jsonEncode({
        'accepted': accepted,
        'failures': <Object?>[],
        'showsPublication': ?shows,
      }),
    );
    expect(fitConcernsPushedSurface(verdict(accepted: true)), isTrue);
    expect(
      fitConcernsPushedSurface(verdict(accepted: false, shows: true)),
      isTrue,
    );
    expect(
      fitConcernsPushedSurface(verdict(accepted: false, shows: false)),
      isFalse,
    );
    expect(fitConcernsPushedSurface(verdict(accepted: false)), isFalse);
  });

  test('a value the installed app does not compute needs an app release', () {
    expect(
      describeFitVerdict(
        _verdict(const [
          {
            'code': 'missingHostField',
            'path': r'$.requiredContext._h0123456789',
            'required': {'kind': 'int', 'label': 'VColors.of(context).ink'},
            'available': null,
          },
          {
            'code': 'missingHostField',
            'path': r'$.requiredContext.plants[]._hfedcba9876',
            'required': {'kind': 'int'},
            'available': null,
          },
        ]),
      ),
      [
        'does not fit',
        "This version reads 'VColors.of(context).ink', which installed builds "
            "don't compute. It needs an app release",
        "This version reads '_hfedcba9876', which installed builds don't "
            'compute. It needs an app release',
      ],
    );
  });
}
