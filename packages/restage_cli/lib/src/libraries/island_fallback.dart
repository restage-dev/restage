import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/library_requirements_api.dart';
import 'package:restage_cli/src/libraries/library_contract_check.dart'
    show inEnvironmentOrder;
import 'package:restage_shared/restage_shared.dart';

/// The fit token of every island in [renderCatalogJson], by qualified name.
@experimental
Map<String, String> islandTokens(String renderCatalogJson) {
  final catalog = decodeCatalog(renderCatalogJson);
  return {
    for (final widget in catalog.widgets)
      if (catalog.libraries[widget.library]?.islands ?? false)
        WidgetVocabulary.qualifiedName(widget.library.namespace, widget.name):
            widget.wireId.value,
  };
}

/// What the last local build's compiler handoff says about its islands.
@experimental
@immutable
final class LocalIslands {
  /// Creates a record.
  const LocalIslands({this.locations = const {}, this.byMount = const {}});

  /// Reads [handoff]; empty when it is absent or unreadable.
  factory LocalIslands.read(File handoff) {
    try {
      if (jsonDecode(handoff.readAsStringSync()) case {
        'splitSites': final List<Object?> sites,
        'surfaceIslands': final Map<String, Object?> hosts,
      }) {
        return LocalIslands(
          locations: {
            for (final site in sites)
              if (site case {
                'name': final String name,
                'location': final String location,
                'kind': 'island',
              })
                name: location,
          },
          byMount: {
            for (final MapEntry(:key, :value) in hosts.entries)
              if (value case final List<Object?> islands)
                key: islands.whereType<String>().toSet(),
          },
        );
      }
    } on Object {
      // Without the local record, findings name no location.
    }
    return const LocalIslands();
  }

  /// Where each island is in the app's source, `path:line:column`.
  final Map<String, String> locations;

  /// The islands each publication's host provides, by `<surface>/<slug>`.
  final Map<String, Set<String>> byMount;
}

/// The line above the [IslandFallback.sentence]s a push reports.
const islandFallbacksHeading =
    'These live versions show the compiled screen on this build:';

/// A live version that shows the app's compiled screen on this build,
/// because widget app code it renders is gone or changed.
@experimental
@immutable
final class IslandFallback {
  /// Construct one finding.
  const IslandFallback({
    required this.version,
    required this.island,
    required this.removed,
    this.location,
  });

  /// The live version.
  final LiveVersionRequirements version;

  /// The widget's qualified compiler name.
  final String island;

  /// Whether this build lacks the widget's app code, rather than changed it.
  final bool removed;

  /// Where this build has it, `path:line:column`, when it has it.
  final String? location;

  /// The line naming this finding.
  String get sentence {
    final v = version;
    final where = switch (v.kind) {
      LiveVersionKind.serving => 'serving',
      LiveVersionKind.deliveryRule => '${v.routeId}',
      LiveVersionKind.experimentArm =>
        '${v.experimentLabel ?? v.experimentId} ${v.armLabel ?? v.armId}',
    };
    final label = version.islandLabels[island] ?? 'a widget';
    final lead =
        '${v.surfaceSlug} v${v.publishedRevision} ($where) shows the '
        'compiled screen on this build:';
    if (removed) return "$lead this build doesn't include $label.";
    final line = switch (RegExp(r'^(.*:\d+):\d+$').firstMatch(location ?? '')) {
      final match? => ' (${match[1]})',
      null => '',
    };
    return '$lead $label$line changed. Republish to update it.';
  }
}

/// Every widget app code of every live version that this build's [tokens]
/// do not render as published at the mount serving it, in environment order.
@experimental
List<IslandFallback> findIslandFallbacks({
  required List<LiveVersionRequirements> live,
  required Map<String, String> tokens,
  LocalIslands local = const LocalIslands(),
}) {
  final found = <IslandFallback>[];
  for (final version in live) {
    final mount =
        local.byMount['${version.surfaceType}/${version.surfaceSlug}'];
    for (final MapEntry(key: island, value: token)
        in (version.requiredIslands ?? const <String, String>{}).entries) {
      final available = mount == null || mount.contains(island)
          ? tokens[island]
          : null;
      if (available == token) continue;
      found.add(
        IslandFallback(
          version: version,
          island: island,
          removed: available == null,
          location: local.locations[island],
        ),
      );
    }
  }
  return inEnvironmentOrder(found, (item) => item.version);
}
