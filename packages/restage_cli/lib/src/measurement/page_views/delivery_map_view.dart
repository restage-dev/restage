import 'package:restage_cli/src/measurement/page_read.dart';
import 'package:restage_cli/src/output/held_count.dart';

import 'page_view_support.dart';

const String _unknown = 'Unknown';
const String _none = '—';
const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Writes the delivery map: one row per placement, surface and version, then
/// the mismatches and the surfaces no build has placed.
void renderDeliveryMapPage(
  StringSink out,
  Map<String, Object?> document, {
  bool bySurface = false,
  SurfaceVersionArg? only,
}) {
  if (figureAt(document, ['tooLarge'])
      case final Map<String, Object?> refused) {
    final filters = figureList(refused, ['filters']);
    out.writeln(
      _line([
        'Too large',
        '${refused['bound']}',
        if (filters.isNotEmpty) 'Narrow by ${filters.join(' or ')}',
      ]),
    );
    return;
  }
  final builds = {
    for (final build in figureList(document, ['builds']))
      _buildKey(build): _buildLabel(build),
  };
  final environments = {
    for (final target in figureList(document, ['targets']))
      '${figureAt(target, ['target', 'environmentTargetId'])}': (
        name: '${figureAt(target, ['environment']) ?? _unknown}',
        plane: '${figureAt(target, ['target', 'runtimePlane']) ?? _unknown}',
      ),
  };
  out.writeln(
    _line([
      only == null ? 'Delivery map' : _surfaceTitle(only),
      _window(document),
      environments.length > 1
          ? 'All environments'
          : environments.values.map((e) => e.name).join(),
    ]),
  );
  final rows = <List<String>>[];
  final mismatches = <List<String>>[];
  for (final placement in figureList(document, ['placements', 'values'])) {
    final environment =
        environments['${figureAt(placement, ['target', 'environmentTargetId'])}'] ??
        (name: _unknown, plane: _unknown);
    final key =
        '${figureAt(placement, ['label']) ?? figureAt(placement, ['key'])}';
    final screen =
        '${figureAt(placement, ['screen', 'screenLabel']) ?? _unknown}';
    final edges = figureList(placement, ['edges']);
    final requests = _count(figureAt(placement, ['resolutions']));
    final paints = _total(edges.map((e) => figureAt(e, ['paints'])));
    final audiences = _ruleFigures(placement, 'audienceName');
    final names = _ruleFigures(placement, 'name');
    for (final edge in edges) {
      final slug = '${figureAt(edge, ['surfaceSlug']) ?? _none}';
      if (only != null && slug != only.slug) continue;
      final routes = figureList(edge, ['routeIds']);
      final audience = routes.isEmpty
          ? 'Everyone'
          : routes.map((id) => audiences['$id'] ?? '$id').join(', ');
      final named = [for (final id in routes) ?names['$id']];
      final rule = named.isEmpty ? _none : named.join(', ');
      final kpi = _kpi(figureAt(edge, ['kpi']));
      final versions = figureList(edge, ['versions']);
      for (final version in versions.isEmpty ? <Object?>[null] : versions) {
        if (only?.version != null &&
            figureAt(version, ['version']) != only!.version) {
          continue;
        }
        final node = version ?? edge;
        final cells = (
          version: version == null
              ? _none
              : 'v${figureAt(version, ['version'])}',
          builds: _buildRange(figureList(node, ['paintsByBuild']), builds),
          configured: _share(figureAt(node, ['routedResolutions']), requests),
          seen: _share(figureAt(node, ['paints']), paints),
          paints: _countText(figureAt(node, ['paints'])),
        );
        rows.add(
          bySurface
              ? [
                  slug,
                  cells.version,
                  environment.name,
                  environment.plane,
                  key,
                  screen,
                  rule,
                  audience,
                  cells.builds,
                  cells.configured,
                  cells.seen,
                  cells.paints,
                ]
              : [
                  key,
                  screen,
                  slug,
                  cells.version,
                  rule,
                  audience,
                  cells.builds,
                  cells.configured,
                  cells.seen,
                  cells.paints,
                  kpi,
                ],
        );
      }
      for (final node in [edge, ...versions]) {
        for (final flag in figureList(node, ['flags'])) {
          mismatches.add([
            if (bySurface) ...[environment.name, environment.plane],
            key,
            slug,
            _flagName(flag),
            _flagDetail(flag, builds),
          ]);
        }
      }
    }
  }
  if (bySurface) rows.sort((a, b) => a.join(' ').compareTo(b.join(' ')));
  _table(
    out,
    bySurface
        ? const [
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
          ]
        : const [
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
          ],
    rows,
  );
  if (mismatches.isNotEmpty) {
    out.writeln();
    _table(out, [
      if (bySurface) ...['ENVIRONMENT', 'PLANE'],
      'PLACEMENT',
      'SURFACE',
      'MISMATCH',
      'DETAIL',
    ], mismatches);
  }
  if (only != null) return;
  final unplaced = [
    for (final surface in figureList(document, ['surfaces', 'values']))
      if (figureAt(surface, ['placed']) == false) surface,
  ];
  if (unplaced.isEmpty) return;
  out
    ..writeln()
    ..writeln(_line(['Not placed yet', '${unplaced.length}']));
  for (final surface in unplaced) {
    final fits = figureList(surface, ['fitsPlacements']);
    out.writeln(
      _line([
        '${figureAt(surface, ['surfaceSlug'])}',
        fits.isEmpty ? 'Fits no reported spot' : 'Fits ${fits.join(', ')}',
      ]),
    );
  }
}

String _line(List<String> cells) => cells.where((c) => c.isNotEmpty).join('  ');

void _table(StringSink out, List<String> head, List<List<String>> rows) {
  final all = [head, ...rows];
  final widths = [
    for (var i = 0; i < head.length; i++)
      all.map((row) => row[i].length).reduce((a, b) => a > b ? a : b) + 2,
  ];
  for (final row in all) {
    out.writeln(
      [
        for (var i = 0; i < row.length; i++)
          i < row.length - 1 ? row[i].padRight(widths[i]) : row[i],
      ].join(),
    );
  }
}

String _surfaceTitle(SurfaceVersionArg only) =>
    only.version == null ? only.slug : '${only.slug} v${only.version}';

String _window(Map<String, Object?> document) {
  final from = figureAt(document, ['request', 'fromMicros']);
  final until = figureAt(document, ['request', 'untilMicros']);
  if (from is! int || until is! int) return '';
  final start = DateTime.fromMicrosecondsSinceEpoch(from, isUtc: true);
  final end = DateTime.fromMicrosecondsSinceEpoch(
    until,
    isUtc: true,
  ).subtract(const Duration(days: 1));
  String day(DateTime t) => '${_months[t.month - 1]} ${t.day}';
  return start.month == end.month
      ? '${day(start)}–${end.day}'
      : '${day(start)}–${day(end)}';
}

/// A count's value, or null when it is unknown or held.
int? _value(Object? count) => figureAt(count, ['value']) as int?;

String _countText(Object? count) => switch (figureAt(count, ['state'])) {
  'held' => heldCountText,
  _ when _value(count) != null => groupedCount(_value(count)!),
  _ => _unknown,
};

int? _count(Object? count) => _value(count);

int? _total(Iterable<Object?> counts) {
  var total = 0;
  for (final count in counts) {
    final value = _value(count);
    if (value == null) return null;
    total += value;
  }
  return total;
}

String _share(Object? part, int? whole) {
  final value = _value(part);
  if (value == null || whole == null || whole == 0) return _unknown;
  return '${(value * 1000 / whole).round() / 10}%';
}

String _kpi(Object? kpi) {
  final metric = figureAt(kpi, ['metric']);
  final text = switch (figureAt(kpi, ['state'])) {
    'available' => () {
      final numerator = figureAt(kpi, ['numerator'])! as int;
      final denominator = figureAt(kpi, ['denominator'])! as int;
      return '${(numerator * 1000 / denominator).round() / 10}%';
    }(),
    'noResult' => 'No result yet',
    'held' => heldCountText,
    _ => kFigureUnavailable,
  };
  return metric == null ? text : '$metric $text';
}

/// One string figure of each scheduled rule, by route.
Map<String, String> _ruleFigures(Object? placement, String figure) => {
  for (final snapshot in figureList(placement, ['schedule']))
    for (final rule in figureList(snapshot, ['rules']))
      if (figureAt(rule, [figure]) case final String value)
        '${figureAt(rule, ['routeId'])}': value,
};

String _buildKey(Object? build) =>
    '${figureAt(build, ['platform'])}|${figureAt(build, ['buildOrdinal'])}';

String _platform(Object? platform) => switch (platform) {
  'ios' => 'iOS',
  'android' => 'Android',
  'macos' => 'macOS',
  'web' => 'Web',
  'linux' => 'Linux',
  'windows' => 'Windows',
  _ => '$platform',
};

String _buildLabel(Object? build) {
  final platform = _platform(figureAt(build, ['platform']));
  final ordinal = figureAt(build, ['buildOrdinal']);
  final version = figureAt(build, ['appVersion']);
  return switch ((version, ordinal)) {
    (final String v, final int o) => '$platform $v ($o)',
    (null, final int o) => '$platform build $o',
    _ => platform,
  };
}

/// The builds that painted, per platform: one label, or the oldest to the
/// newest.
String _buildRange(List<Object?> byBuild, Map<String, String> labels) {
  final painted = [
    for (final entry in byBuild)
      if ((_value(figureAt(entry, ['count'])) ?? 1) > 0) entry,
  ];
  if (painted.isEmpty) return _none;
  final byPlatform = <String, List<Object?>>{};
  for (final entry in painted) {
    byPlatform
        .putIfAbsent('${figureAt(entry, ['platform'])}', () => [])
        .add(entry);
  }
  return [
    for (final entries in byPlatform.values)
      () {
        entries.sort(
          (a, b) => ((figureAt(a, ['buildOrdinal']) as int?) ?? 0).compareTo(
            (figureAt(b, ['buildOrdinal']) as int?) ?? 0,
          ),
        );
        final first =
            labels[_buildKey(entries.first)] ?? _buildLabel(entries.first);
        final last =
            labels[_buildKey(entries.last)] ?? _buildLabel(entries.last);
        return first == last ? first : '$first–$last';
      }(),
  ].join(' and ');
}

String _flagName(Object? flag) => switch (figureAt(flag, ['kind'])) {
  'cantRender' => 'cant-render',
  'stillPainting' => 'v${figureAt(flag, ['version'])}-still-painting',
  'neverPainted' => 'never-painted',
  final kind => '$kind',
};

String _flagDetail(Object? flag, Map<String, String> builds) {
  final count = groupedCount(figureAt(flag, ['count'])! as int);
  final build = figureAt(flag, ['platform']) == null
      ? null
      : builds[_buildKey(flag)] ?? _buildLabel(flag);
  return switch (figureAt(flag, ['kind'])) {
    'cantRender' => '$count fallbacks on $build',
    'stillPainting' => '$count paints on $build',
    _ => '$count requests',
  };
}
