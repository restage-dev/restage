/// Standalone source groups supported by the blob fixture owner.
const blobStandaloneFixtureIds = <String>[
  'ascend_premium',
  'modal_sheet_lowering',
  'modal_sheet_lowering_cupertino',
  'narrate_membership',
  'pulse_premium',
  'sentinel_protection',
];

/// Sources that form one navigation fixture.
const blobNavigationSourceIds = <String>[
  'fluent_pro',
  'fluent_pro_choose_plan',
];

/// Complete golden path to production output path mapping for one fixture.
Map<String, String> blobFixtureArtifacts(String fixture) {
  if (blobStandaloneFixtureIds.contains(fixture)) {
    return {
      '$fixture.rfwtxt': 'assets/paywalls/$fixture.rfwtxt',
      '$fixture.rfw': 'assets/paywalls/$fixture.rfw',
      'paywall_$fixture.rfw': 'assets/paywalls/screens/paywall_$fixture.rfw',
      'paywall_$fixture.capability.json':
          'assets/paywalls/screens/paywall_$fixture.capability.json',
    };
  }
  if (fixture == 'fluent_pro') {
    return {
      'fluent_pro.rfwtxt': 'assets/paywalls/fluent_pro.rfwtxt',
      'fluent_pro.rfw': 'assets/paywalls/fluent_pro.rfw',
      'fluent_pro.flow.json': 'assets/paywalls/fluent_pro.flow.json',
      for (final id in blobNavigationSourceIds) ...{
        'paywall_$id.rfw': 'assets/paywalls/screens/paywall_$id.rfw',
        'paywall_$id.capability.json':
            'assets/paywalls/screens/paywall_$id.capability.json',
      },
    };
  }
  throw ArgumentError.value(fixture, 'fixture', 'Unknown blob fixture');
}

/// Sources compiled together by the canonical owner of [fixture].
List<String> blobFixtureSources(String fixture) {
  blobFixtureArtifacts(fixture);
  // Standalone Measurement allocation depends on the complete corpus roster.
  return fixture == 'fluent_pro'
      ? blobNavigationSourceIds
      : blobStandaloneFixtureIds;
}
