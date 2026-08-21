import 'dart:io';

import 'package:test/test.dart';

/// The legacy behavioral-analytics vocabulary is retained for the legacy
/// analytics runtime the SDK still ships, and reachable only through the
/// `legacy_analytics.dart` entrypoint. Importing it here to name the symbols is
/// exactly what must stay impossible from the default barrel, so the fence is
/// asserted over source text rather than by referencing the declarations.
void main() {
  final barrel = File('lib/restage_shared.dart').readAsStringSync();
  final entrypoint = File('lib/legacy_analytics.dart').readAsStringSync();

  test('the default barrel does not export the legacy analytics modules', () {
    for (final module in _legacyModules) {
      expect(
        barrel,
        isNot(contains(module)),
        reason: '$module is legacy and must not be on the default surface',
      );
    }
  });

  test('the legacy entrypoint exports every legacy analytics module', () {
    for (final module in _legacyModules) {
      expect(
        entrypoint,
        contains("export 'src/legacy_analytics/$module';"),
        reason: 'the retained runtime reaches $module through this entrypoint',
      );
    }
  });

  test('no legacy declaration is reachable from the default surface', () {
    final offenders = <String>[];
    for (final file in _defaultSurfaceSources()) {
      final source = file.readAsStringSync();
      for (final declaration in _legacyDeclarations) {
        if (RegExp('\\b$declaration\\b').hasMatch(source)) {
          offenders.add('${file.path}: $declaration');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}

/// Every library source the default barrel can reach — the whole `lib/` tree
/// except the fenced legacy subtree and its entrypoint.
///
/// Walking the tree rather than listing files means a legacy declaration
/// reintroduced in a NEW file is caught too, which is the failure this guard
/// exists to prevent.
Iterable<File> _defaultSurfaceSources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    .where(
      (file) =>
          !file.path.startsWith('lib/src/legacy_analytics/') &&
          file.path != 'lib/legacy_analytics.dart',
    );

const _legacyModules = <String>[
  'analytics_app_context.dart',
  'analytics_event.dart',
  'analytics_reserved_keys.dart',
  'analytics_skew.dart',
  'analytics_taxonomy_registry.dart',
  'analytics_wire_enums.dart',
];

/// Every public declaration the legacy modules carry, so the fence is stated
/// over the vocabulary itself and not merely over the export lines.
const _legacyDeclarations = <String>[
  'AnalyticsAppContext',
  'AnalyticsEvent',
  'kReservedPropertyKeys',
  'containsReservedKey',
  'scrubReservedKeys',
  'kMaxEventSkew',
  'clampOccurredAt',
  'AnalyticsEventSpec',
  'kSurfaceArtifactFetchFailedEventName',
  'kFlowLifecycleAnalyticsEventNames',
  'kAnalyticsRegistry',
  'lookupAnalyticsEvent',
  'isRegisteredAnalyticsEvent',
  'tierForEvent',
  'isAnalyticsEventEligibleForArtifact',
  'AnalyticsSurface',
  'AnalyticsSource',
  'AnalyticsTier',
  'AnalyticsPlatform',
];
