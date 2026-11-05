import 'package:restage_cli/src/api/library_requirements_api.dart';
import 'package:restage_cli/src/libraries/island_fallback.dart';
import 'package:test/test.dart';

const _island = 'app.islands:pro_ListView_0';

LiveVersionRequirements _live(
  Map<String, String>? islands, {
  String environment = 'prod',
}) => LiveVersionRequirements(
  environment: environment,
  kind: LiveVersionKind.serving,
  surfaceType: 'paywall',
  surfaceSlug: 'pro',
  publishedRevision: 3,
  requiredLibraries: const {},
  requiredIslands: islands,
  islandLabels: const {_island: 'ListView in PaywallScreen'},
);

void main() {
  test('the push report heading', () {
    expect(
      islandFallbacksHeading,
      'These live versions show the compiled screen on this build:',
    );
  });

  const here = 'lib/paywall.dart:108:27';
  const mountHas = LocalIslands(
    locations: {_island: here},
    byMount: {
      'paywall/pro': {_island},
    },
  );
  const lead = 'pro v3 (serving) shows the compiled screen on this build:';
  for (final (name, required, tokens, local, sentence) in [
    ('the same token fits', {_island: 'w12'}, {_island: 'w12'}, mountHas, null),
    (
      'a changed token falls back, located',
      {_island: 'w12'},
      {_island: 'w34'},
      mountHas,
      '$lead ListView in PaywallScreen (lib/paywall.dart:108) changed. '
          'Republish to update it.',
    ),
    (
      'a changed token without a location',
      {_island: 'w12'},
      {_island: 'w34'},
      const LocalIslands(),
      '$lead ListView in PaywallScreen changed. Republish to update it.',
    ),
    (
      'a missing widget falls back',
      {_island: 'w12'},
      <String, String>{},
      const LocalIslands(),
      "$lead this build doesn't include ListView in PaywallScreen.",
    ),
    (
      "another mount's widget is missing from this one",
      {_island: 'w12'},
      {_island: 'w12'},
      const LocalIslands(byMount: {'paywall/pro': {}}),
      "$lead this build doesn't include ListView in PaywallScreen.",
    ),
    (
      'an unread requirement says nothing',
      null,
      <String, String>{},
      const LocalIslands(),
      null,
    ),
  ]) {
    test(name, () {
      final found = findIslandFallbacks(
        live: [_live(required)],
        tokens: tokens,
        local: local,
      );
      expect([for (final item in found) item.sentence], [?sentence]);
      // Developers read labels and locations, never compiler names.
      for (final item in found) {
        expect(item.sentence, isNot(matches(RegExp('island|_h[0-9a-f]'))));
      }
    });
  }

  test('findings are in environment order', () {
    final found = findIslandFallbacks(
      live: [
        _live({_island: 'w1'}),
        _live({_island: 'w1'}, environment: 'dev'),
      ],
      tokens: const {},
    );
    expect(
      [for (final item in found) item.version.environment],
      ['dev', 'prod'],
    );
  });
}
