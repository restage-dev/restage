import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show CanonicalJsonCodec;
import 'package:restage_shared/src/surface_contract/surface_contract_json.dart';

/// The values each discriminator must hold: a return's index or a
/// condition's outcome, by the key it is recorded under.
typedef SurfaceLayoutCondition = Map<String, Set<Object>>;

/// How a build's condition reads where it is written.
@immutable
final class SurfaceLayoutWhenV1 {
  /// Creates a condition's text.
  const SurfaceLayoutWhenV1({
    required this.source,
    required this.plain,
    required this.location,
  });

  factory SurfaceLayoutWhenV1._fromJson(Object? value, String path) {
    final json = SurfaceContractJson.requireObject(value, path);
    SurfaceContractJson.exactKeys(
        json, const {'source', 'plain', 'location'}, path);
    String text(String key) => switch (json[key]) {
          final String text when text.isNotEmpty => text,
          _ => throw FormatException('Expected text at "$path.$key".'),
        };
    return SurfaceLayoutWhenV1(
      source: text('source'),
      plain: text('plain'),
      location: text('location'),
    );
  }

  /// The condition as the build writes it, `offer != null`.
  final String source;

  /// The condition in plain words, `when there's an offer`.
  final String plain;

  /// Where the build writes it, `lib/offer.dart:12:9`.
  final String location;

  /// Canonical JSON.
  Map<String, Object?> toJson() =>
      {'source': source, 'plain': plain, 'location': location};
}

/// Where a mount's build produces each value and island it records.
///
/// A key or island with no entry is produced in every layout.
@immutable
final class SurfaceLayoutsV1 {
  /// Creates layouts; each condition names only discriminators in [domains],
  /// with values in their domain.
  factory SurfaceLayoutsV1({
    Map<String, Set<Object>> domains = const {},
    Map<String, SurfaceLayoutCondition> values = const {},
    Map<String, SurfaceLayoutCondition> islands = const {},
    String? build,
    Map<String, Map<Object, SurfaceLayoutWhenV1>> when = const {},
  }) {
    final frozenDomains = _frozenCondition(domains, r'$.domains');
    for (final MapEntry(:key, :value) in frozenDomains.entries) {
      if (value.isEmpty) {
        throw FormatException('Empty domain at "\$.domains.$key".');
      }
    }
    Map<String, SurfaceLayoutCondition> conditions(
      Map<String, SurfaceLayoutCondition> raw,
      String path,
    ) {
      final result = <String, SurfaceLayoutCondition>{};
      for (final key in _sorted(raw.keys)) {
        final condition = _frozenCondition(raw[key]!, '$path.$key');
        if (condition.isEmpty) continue;
        for (final MapEntry(key: discriminator, :value) in condition.entries) {
          final domain = frozenDomains[discriminator];
          if (domain == null || !domain.containsAll(value)) {
            throw FormatException(
              'Undeclared discriminator value at "$path.$key.$discriminator".',
            );
          }
        }
        result[key] = condition;
      }
      return Map.unmodifiable(result);
    }

    final frozenValues = conditions(values, r'$.values');
    final frozenIslands = conditions(islands, r'$.islands');
    final conditional = frozenValues.isNotEmpty || frozenIslands.isNotEmpty;
    final frozenWhen = <String, Map<Object, SurfaceLayoutWhenV1>>{};
    for (final discriminator in _sorted(when.keys)) {
      if (!conditional) break;
      final domain = frozenDomains[discriminator];
      final texts = when[discriminator]!;
      if (domain == null || !domain.containsAll(texts.keys)) {
        throw FormatException(
          'Undeclared discriminator value at "\$.when.$discriminator".',
        );
      }
      if (texts.isEmpty) continue;
      frozenWhen[discriminator] = Map.unmodifiable({
        for (final value in texts.keys.toList()..sort(_compareValues))
          value: texts[value]!,
      });
    }
    return SurfaceLayoutsV1._(
      frozenDomains,
      frozenValues,
      frozenIslands,
      conditional ? build : null,
      Map.unmodifiable(frozenWhen),
    );
  }

  const SurfaceLayoutsV1._(
    this.domains,
    this.values,
    this.islands,
    this.build,
    this.when,
  );

  /// No conditional value or island.
  static final SurfaceLayoutsV1 empty = SurfaceLayoutsV1();

  /// Decodes canonical layouts strictly.
  factory SurfaceLayoutsV1.fromJson(Object? value, {String path = r'$'}) {
    final json = SurfaceContractJson.requireObject(value, path);
    SurfaceContractJson.allowedKeys(
        json, const {'domains', 'values', 'islands', 'build', 'when'}, path);
    Map<String, SurfaceLayoutCondition> conditions(String key) {
      if (!json.containsKey(key)) return const {};
      final raw = SurfaceContractJson.requireObject(json[key], '$path.$key');
      return {
        for (final MapEntry(key: name, :value) in raw.entries)
          name: _decodeCondition(value, '$path.$key.$name'),
      };
    }

    final layouts = SurfaceLayoutsV1(
      domains: json.containsKey('domains')
          ? _decodeCondition(json['domains'], '$path.domains')
          : const {},
      values: conditions('values'),
      islands: conditions('islands'),
      build: switch (json['build']) {
        null => null,
        final String build when build.isNotEmpty => build,
        _ => throw FormatException('Expected a build name at "$path.build".'),
      },
      when: json.containsKey('when')
          ? {
              for (final MapEntry(key: discriminator, :value)
                  in SurfaceContractJson.requireObject(
                json['when'],
                '$path.when',
              ).entries)
                discriminator: {
                  for (final MapEntry(key: wire, value: text)
                      in SurfaceContractJson.requireObject(
                    value,
                    '$path.when.$discriminator',
                  ).entries)
                    _decodeValueKey(wire, '$path.when.$discriminator'):
                        SurfaceLayoutWhenV1._fromJson(
                      text,
                      '$path.when.$discriminator.$wire',
                    ),
                },
            }
          : const {},
    );
    if (!SurfaceContractJson.bytesEqual(
      CanonicalJsonCodec.encode(layouts.toJson()),
      CanonicalJsonCodec.encode(json),
    )) {
      throw FormatException('Non-canonical layouts at "$path".');
    }
    return layouts;
  }

  /// Every value each discriminator can record.
  final Map<String, Set<Object>> domains;

  /// What each recorded value needs, by context key.
  final Map<String, SurfaceLayoutCondition> values;

  /// What each island needs, by qualified island name.
  final Map<String, SurfaceLayoutCondition> islands;

  /// The build that records them, `PlanPicker.build`.
  final String? build;

  /// The condition each discriminator value stands for, where it is known.
  final Map<String, Map<Object, SurfaceLayoutWhenV1>> when;

  /// Whether every value and island is produced in every layout.
  bool get isEmpty => values.isEmpty && islands.isEmpty;

  /// Canonical JSON; empty facets are omitted.
  Map<String, Object?> toJson() => {
        if (!isEmpty) 'domains': surfaceLayoutConditionJson(domains),
        if (values.isNotEmpty)
          'values': {
            for (final MapEntry(:key, :value) in values.entries)
              key: surfaceLayoutConditionJson(value),
          },
        if (islands.isNotEmpty)
          'islands': {
            for (final MapEntry(:key, :value) in islands.entries)
              key: surfaceLayoutConditionJson(value),
          },
        if (build != null) 'build': build,
        if (when.isNotEmpty)
          'when': {
            for (final MapEntry(key: discriminator, value: texts)
                in when.entries)
              discriminator: {
                for (final MapEntry(:key, :value) in texts.entries)
                  '$key': value.toJson(),
              },
          },
      };

  /// The conditions a build needs [needs] for, each from what [when] knows;
  /// null when one of them has no text.
  List<SurfaceLayoutWhenV1>? whenOf(SurfaceLayoutCondition needs) {
    final texts = <SurfaceLayoutWhenV1>[];
    for (final MapEntry(key: discriminator, value: allowed) in needs.entries) {
      final known = [
        for (final value in allowed.toList()..sort(_compareValues))
          when[discriminator]?[value],
      ];
      if (known.isEmpty || known.contains(null)) return null;
      final each = known.cast<SurfaceLayoutWhenV1>();
      texts.add(each.length == 1
          ? each.single
          : SurfaceLayoutWhenV1(
              source: each.map((text) => '(${text.source})').join(' || '),
              plain: [
                each.first.plain,
                for (final text in each.skip(1))
                  text.plain.replaceFirst(RegExp('^when '), ''),
              ].join(' or '),
              location: each.first.location,
            ));
    }
    return texts;
  }
}

Object _decodeValueKey(String wire, String path) => switch (wire) {
      'true' => true,
      'false' => false,
      _ => int.tryParse(wire) ??
          (throw FormatException('Expected an int or bool key at "$path".')),
    };

/// What a design's path to one read says of one discriminator.
@immutable
final class SurfaceLayoutArmV1 {
  /// The discriminator holds one of [values].
  SurfaceLayoutArmV1.oneOf(Set<Object> values)
      : this._(_frozenValues(values, 'oneOf'), excludes: false);

  /// The discriminator holds none of [values], or is absent.
  SurfaceLayoutArmV1.noneOf(Set<Object> values)
      : this._(_frozenValues(values, 'noneOf'), excludes: true);

  const SurfaceLayoutArmV1._(this.values, {required this.excludes});

  factory SurfaceLayoutArmV1._fromJson(Object? value, String path) {
    final json = SurfaceContractJson.requireObject(value, path);
    if (json.length != 1 ||
        !(json.containsKey('oneOf') || json.containsKey('noneOf'))) {
      throw FormatException('Expected oneOf or noneOf at "$path".');
    }
    final excludes = json.containsKey('noneOf');
    final values =
        _decodeValues(json.values.single, '$path.${json.keys.single}');
    return excludes
        ? SurfaceLayoutArmV1.noneOf(values)
        : SurfaceLayoutArmV1.oneOf(values);
  }

  /// The values named.
  final Set<Object> values;

  /// Whether [values] are excluded rather than required.
  final bool excludes;

  /// This arm and [other] both holding.
  SurfaceLayoutArmV1 and(SurfaceLayoutArmV1 other) => switch ((
        excludes,
        other.excludes,
      )) {
        (false, false) =>
          SurfaceLayoutArmV1.oneOf(values.intersection(other.values)),
        (false, true) =>
          SurfaceLayoutArmV1.oneOf(values.difference(other.values)),
        (true, false) =>
          SurfaceLayoutArmV1.oneOf(other.values.difference(values)),
        (true, true) => SurfaceLayoutArmV1.noneOf(values.union(other.values)),
      };

  /// The values of [domain] this arm admits.
  Set<Object> within(Set<Object> domain) =>
      excludes ? domain.difference(values) : values.intersection(domain);

  /// Canonical JSON.
  Map<String, Object?> toJson() =>
      {excludes ? 'noneOf' : 'oneOf': _valuesJson(values)};
}

/// The switch arms a design passes through to one read.
typedef SurfaceLayoutPath = Map<String, SurfaceLayoutArmV1>;

/// Every place a design reads each recorded value and places each island.
///
/// A read with no entry sits outside every switch.
@immutable
final class SurfaceLayoutReadsV1 {
  /// Creates reads; paths are deduplicated and ordered canonically.
  factory SurfaceLayoutReadsV1({
    Map<String, Iterable<SurfaceLayoutPath>> values = const {},
    Map<String, Iterable<SurfaceLayoutPath>> islands = const {},
  }) =>
      SurfaceLayoutReadsV1._(_frozenPaths(values), _frozenPaths(islands));

  const SurfaceLayoutReadsV1._(this.values, this.islands);

  /// No read inside a switch.
  static final SurfaceLayoutReadsV1 empty = SurfaceLayoutReadsV1();

  /// Decodes canonical reads strictly.
  factory SurfaceLayoutReadsV1.fromJson(Object? value, {String path = r'$'}) {
    final json = SurfaceContractJson.requireObject(value, path);
    SurfaceContractJson.allowedKeys(json, const {'values', 'islands'}, path);
    Map<String, List<SurfaceLayoutPath>> paths(String key) {
      if (!json.containsKey(key)) return const {};
      final raw = SurfaceContractJson.requireObject(json[key], '$path.$key');
      return {
        for (final MapEntry(key: name, :value) in raw.entries)
          name: [
            for (final (index, site) in SurfaceContractJson.requireList(
              value,
              '$path.$key.$name',
            ).indexed)
              {
                for (final MapEntry(key: discriminator, value: arm)
                    in SurfaceContractJson.requireObject(
                  site,
                  '$path.$key.$name[$index]',
                ).entries)
                  discriminator: SurfaceLayoutArmV1._fromJson(
                    arm,
                    '$path.$key.$name[$index].$discriminator',
                  ),
              },
          ],
      };
    }

    final reads = SurfaceLayoutReadsV1(
      values: paths('values'),
      islands: paths('islands'),
    );
    if (!SurfaceContractJson.bytesEqual(
      CanonicalJsonCodec.encode(reads.toJson()),
      CanonicalJsonCodec.encode(json),
    )) {
      throw FormatException('Non-canonical layout reads at "$path".');
    }
    return reads;
  }

  /// The paths to each read of a context key.
  final Map<String, List<SurfaceLayoutPath>> values;

  /// The paths to each placement of a qualified island.
  final Map<String, List<SurfaceLayoutPath>> islands;

  /// Whether no read sits inside a switch.
  bool get isEmpty => values.isEmpty && islands.isEmpty;

  /// Canonical JSON; empty facets are omitted.
  Map<String, Object?> toJson() => {
        if (values.isNotEmpty) 'values': _pathsJson(values),
        if (islands.isNotEmpty) 'islands': _pathsJson(islands),
      };
}

/// What [needs] asks that the first path in [paths] doesn't imply, given
/// what [layouts] says each discriminator needs; null when every path implies
/// it.
SurfaceLayoutCondition? surfaceLayoutMisses(
  Iterable<SurfaceLayoutPath> paths,
  SurfaceLayoutCondition needs,
  SurfaceLayoutsV1 layouts,
) {
  for (final path in paths) {
    final known = _withPresence(path, layouts);
    final misses = <String, Set<Object>>{
      for (final MapEntry(key: discriminator, value: allowed) in needs.entries)
        if (!allowed.containsAll(
            known[discriminator]?.within(layouts.domains[discriminator]!) ??
                layouts.domains[discriminator]!))
          discriminator: allowed,
    };
    if (misses.isNotEmpty) return misses;
  }
  return null;
}

// A discriminator a path requires a value of was recorded, so what its own
// recording needs holds too.
SurfaceLayoutPath _withPresence(
  SurfaceLayoutPath path,
  SurfaceLayoutsV1 layouts,
) {
  final known = Map.of(path);
  final pending = [
    for (final MapEntry(:key, :value) in path.entries)
      if (!value.excludes) key,
  ];
  final seen = pending.toSet();
  while (pending.isNotEmpty) {
    final needs = layouts.values[pending.removeLast()];
    if (needs == null) continue;
    for (final MapEntry(:key, :value) in needs.entries) {
      final arm = SurfaceLayoutArmV1.oneOf(value);
      known[key] = known[key]?.and(arm) ?? arm;
      if (seen.add(key)) pending.add(key);
    }
  }
  return known;
}

List<String> _sorted(Iterable<String> keys) =>
    keys.toList()..sort(SurfaceContractJson.compareUtf8);

int _compareValues(Object a, Object b) => switch ((a, b)) {
      (final bool x, final bool y) => x == y ? 0 : (x ? 1 : -1),
      (final int x, final int y) => x.compareTo(y),
      (bool(), int()) => -1,
      _ => 1,
    };

Set<Object> _frozenValues(Set<Object> values, String path) {
  for (final value in values) {
    if (value is! bool && value is! int) {
      throw FormatException('Expected an int or bool at "$path".');
    }
  }
  return Set.unmodifiable(values.toList()..sort(_compareValues));
}

SurfaceLayoutCondition _frozenCondition(
  Map<String, Set<Object>> condition,
  String path,
) =>
    Map.unmodifiable({
      for (final key in _sorted(condition.keys))
        key: _frozenValues(condition[key]!, '$path.$key'),
    });

List<Object> _valuesJson(Set<Object> values) =>
    values.toList()..sort(_compareValues);

/// Canonical JSON of [condition].
Map<String, Object?> surfaceLayoutConditionJson(
  SurfaceLayoutCondition condition,
) =>
    {
      for (final MapEntry(:key, :value) in condition.entries)
        key: _valuesJson(value),
    };

Set<Object> _decodeValues(Object? value, String path) {
  final values = <Object>{};
  for (final raw in SurfaceContractJson.requireList(value, path)) {
    if (raw is! Object || (raw is! bool && raw is! int) || !values.add(raw)) {
      throw FormatException('Expected distinct ints or bools at "$path".');
    }
  }
  return values;
}

SurfaceLayoutCondition _decodeCondition(Object? value, String path) => {
      for (final MapEntry(:key, :value)
          in SurfaceContractJson.requireObject(value, path).entries)
        key: _decodeValues(value, '$path.$key'),
    };

/// Canonical JSON of [path].
Map<String, Object?> surfaceLayoutPathJson(SurfaceLayoutPath path) => {
      for (final key in _sorted(path.keys)) key: path[key]!.toJson(),
    };

Map<String, List<SurfaceLayoutPath>> _frozenPaths(
  Map<String, Iterable<SurfaceLayoutPath>> raw,
) {
  final result = <String, List<SurfaceLayoutPath>>{};
  for (final key in _sorted(raw.keys)) {
    final byBytes = <String, SurfaceLayoutPath>{};
    for (final path in raw[key]!) {
      final frozen = Map<String, SurfaceLayoutArmV1>.unmodifiable({
        for (final name in _sorted(path.keys)) name: path[name]!,
      });
      byBytes[utf8.decode(
          CanonicalJsonCodec.encode(surfaceLayoutPathJson(frozen)))] = frozen;
    }
    final ordered = byBytes.keys.toList()..sort();
    if (ordered.isEmpty) continue;
    result[key] = List.unmodifiable([for (final k in ordered) byBytes[k]!]);
  }
  return Map.unmodifiable(result);
}

Map<String, Object?> _pathsJson(Map<String, List<SurfaceLayoutPath>> paths) => {
      for (final MapEntry(:key, :value) in paths.entries)
        key: [for (final path in value) surfaceLayoutPathJson(path)],
    };
