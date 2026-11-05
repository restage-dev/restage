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

  // Each row: an island failure and the exact reason a developer reads.
  for (final (code, reason) in [
    (
      'missingIsland',
      "An installed build doesn't include the app code of `ListView in "
          'PaywallScreen`. Try removing it from the version, or releasing an '
          'app build that includes it.',
    ),
    (
      'changedIsland',
      'An installed build changed the app code of `ListView in '
          'PaywallScreen`. Try republishing the version to show it on an '
          'installed build.',
    ),
  ]) {
    test('$code names the widget by its label', () {
      final reasons = describeFitVerdict(
        _verdict([
          {
            'code': code,
            'path': r'$.requiredIslands.app.islands:paywall__screen_ListView_0',
            'required': 'ListView in PaywallScreen',
            'available': null,
          },
        ]),
      );
      expect(reasons, ['does not fit', reason]);
      expect(reasons.join(), isNot(matches(RegExp('island'))));
    });
  }

  for (final (code, path, label, reason) in [
    (
      'unproducedHostField',
      r'$.layoutReads.values._hT',
      'plan.name',
      "`plan.name` is shown where `PlanPicker.build` doesn't compute it. "
          'The build computes it only when `offer != null` '
          '(lib/plans.dart:12:9). Try showing it only in that case, or '
          'computing it before that `if`.',
    ),
    (
      'unproducedIsland',
      r'$.layoutReads.islands.app.islands:paywall__screen_Badge_0',
      'Badge in PaywallScreen',
      "`Badge` is placed where `PlanPicker.build` doesn't create it. The "
          'build creates it only when `offer != null` (lib/plans.dart:12:9). '
          'Try placing it only in that case, or creating it before that '
          '`if`.',
    ),
  ]) {
    test('$code names what the build computes elsewhere', () {
      expect(
        describeFitVerdict(
          _verdict([
            {
              'code': code,
              'path': path,
              'required': label,
              'available': {
                'needs': {
                  '_hB': [1],
                },
                'build': 'PlanPicker.build',
                'when': [
                  {
                    'source': 'offer != null',
                    'plain': "when there's an offer",
                    'location': 'lib/plans.dart:12:9',
                  },
                ],
              },
            },
          ]),
        ),
        ['does not fit', reason],
      );
    });
  }

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
        'not checked yet',
        'No app build has shown this placement in the last 30 days. Try '
            'opening it in an app build, then pushing again.',
      ],
    );
  });

  test('each distinct failure reads as the publish confirmation words it', () {
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
        "This version is one screen, and this placement doesn't show single "
            'screens. Try publishing it to a placement that does.',
        "An installed build doesn't pass `activePlan` to this placement. Try "
            "removing `activePlan` from the version, or passing it in the "
            "placement's `context` in a new app build.",
        "An installed build doesn't pass `busy` to this placement. Try "
            "removing `busy` from the version, or passing it in the "
            "placement's `context` in a new app build.",
        'This version sends the event `restore`, which an installed build '
            "doesn't handle here. Try removing it from the version, or "
            'handling it where a new app build shows this placement.',
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
        'This version reads `VColors.of(context).ink`, which an installed '
            "build doesn't compute. Try removing `VColors.of(context).ink` "
            'from the version, or releasing an app build that computes it.',
        'This version reads `plants[]._hfedcba9876`, which an installed '
            "build doesn't compute. Try removing `plants[]._hfedcba9876` from "
            'the version, or releasing an app build that computes it.',
      ],
    );
  });
}
