import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Shared catalog entries in the existing historical source archive.
const historicalCatalogAssets = <String>[
  'restage_core|lib/src/widget_catalog/catalog.json',
  'restage_material|lib/src/widget_catalog/catalog.json',
  'restage_cupertino|lib/src/widget_catalog/catalog.json',
];

/// Corpus boundaries owned by the production entrypoint oracle.
const productionFixtureCorpora = <String>[
  'examples_onboarding',
  'showcase_onboarding',
  'examples_paywall_navigation',
  'showcase_paywall_navigation',
];

/// Content identity used by fixture manifests.
String fixtureDigest(List<int> bytes) => 'sha256:${sha256.convert(bytes)}';

/// Stable identity of a source or catalog set, independent of map order.
String fixtureSourceDigest(Map<String, String> sources) {
  final keys = sources.keys.toList()..sort();
  return fixtureDigest(
    utf8.encode(
      jsonEncode({
        for (final key in keys) key: sources[key],
      }),
    ),
  );
}

/// Existing gzip source archive and its hash manifest.
final class HistoricalFixtureArchive {
  HistoricalFixtureArchive._(this.sources, this.manifest, this.bytes);

  /// Checks the existing archive before any generation starts.
  factory HistoricalFixtureArchive.decode(
    List<int> bytes,
    Map<String, Object?> manifest,
  ) {
    if (manifest['archiveSha256'] != fixtureDigest(bytes)) {
      throw StateError('Historical source archive digest differs.');
    }
    final sources = Map<String, String>.from(
      jsonDecode(utf8.decode(gzip.decode(bytes))) as Map,
    );
    final entries = manifest['entries']! as Map;
    if (sources.length != entries.length ||
        !sources.keys.every(entries.containsKey)) {
      throw StateError('Historical source archive roster differs.');
    }
    for (final entry in sources.entries) {
      final encoded = utf8.encode(entry.value);
      final provenance = entries[entry.key]! as Map;
      if (provenance['bytes'] != encoded.length ||
          provenance['sha256'] != fixtureDigest(encoded)) {
        throw StateError('Historical source differs: ${entry.key}');
      }
    }
    return HistoricalFixtureArchive._(
      Map.unmodifiable(sources),
      Map.unmodifiable(manifest),
      List.unmodifiable(bytes),
    );
  }

  /// Exact authored source strings, including the shared catalogs.
  final Map<String, String> sources;

  /// Existing archive representation and provenance metadata.
  final Map<String, Object?> manifest;

  /// Hash-verified compressed archive bytes.
  final List<int> bytes;

  /// Identity of every archived author source, excluding the three catalogs.
  String get authorDigest => fixtureSourceDigest({
    for (final entry in sources.entries)
      if (!historicalCatalogAssets.contains(entry.key)) entry.key: entry.value,
  });

  /// Identity of the one shared installed catalog set.
  String get catalogDigest => fixtureSourceDigest({
    for (final key in historicalCatalogAssets) key: sources[key]!,
  });

  /// Replaces only catalog entries, retaining every archived author byte.
  HistoricalFixtureArchive withCatalogs(Map<String, String> catalogs) {
    if (catalogs.length != historicalCatalogAssets.length ||
        !historicalCatalogAssets.every(catalogs.containsKey) ||
        !historicalCatalogAssets.every(sources.containsKey)) {
      throw StateError('Exactly the three installed catalogs are required.');
    }
    return _replacing(catalogs);
  }

  /// Replaces the author sources [migrated] with the output of a shipped
  /// migration, retaining every other archived byte.
  HistoricalFixtureArchive withMigratedSources(Map<String, String> migrated) {
    if (migrated.isEmpty ||
        migrated.keys.any(historicalCatalogAssets.contains) ||
        !migrated.keys.every(sources.containsKey)) {
      throw StateError('Only existing author sources can be migrated.');
    }
    if (migrated.entries.any((entry) => sources[entry.key] == entry.value)) {
      throw StateError('A migrated source must change.');
    }
    return _replacing(migrated);
  }

  HistoricalFixtureArchive _replacing(Map<String, String> replaced) {
    final updated = {...sources, ...replaced};
    final encoded = gzip.encode(utf8.encode(jsonEncode(updated)));
    final entries = <String, Object?>{
      for (final entry in (manifest['entries']! as Map).entries)
        entry.key as String: entry.value,
    };
    for (final entry in replaced.entries) {
      final bytes = utf8.encode(entry.value);
      entries[entry.key] = {
        ...Map<String, Object?>.from(entries[entry.key]! as Map),
        'bytes': bytes.length,
        'sha256': fixtureDigest(bytes),
      };
    }
    return HistoricalFixtureArchive.decode(encoded, {
      ...manifest,
      'archiveSha256': fixtureDigest(encoded),
      'entries': entries,
    });
  }
}

/// Rejects partial catalog transitions and stages from different baselines.
void validateOracleStageSet(List<Map<String, Object?>> stages) {
  if (stages.isEmpty) throw StateError('At least one stage is required.');
  final first = stages.first;
  final corpora = <String>{};
  for (final stage in stages) {
    if (stage['schemaVersion'] != 1 ||
        stage['kind'] != 'oracle' ||
        !productionFixtureCorpora.contains(stage['corpus']) ||
        !corpora.add(stage['corpus']! as String)) {
      throw StateError('Invalid or duplicate oracle stage.');
    }
    for (final key in [
      'baselineArchiveDigest',
      'baselineArchiveManifestDigest',
      'authorDigest',
      'baselineCatalogDigest',
      'catalogDigest',
      'archiveDigest',
      'archiveManifestDigest',
    ]) {
      if (stage[key] is! String || stage[key] != first[key]) {
        throw StateError('Oracle stages disagree on $key.');
      }
    }
    if (stage['reason'] is! String ||
        (stage['reason']! as String).trim().isEmpty) {
      throw StateError('An intentional format-change reason is required.');
    }
  }
  if (first['catalogDigest'] != first['baselineCatalogDigest'] &&
      (corpora.length != productionFixtureCorpora.length ||
          !productionFixtureCorpora.every(corpora.contains))) {
    throw StateError('A catalog change requires all four staged corpora.');
  }
}
