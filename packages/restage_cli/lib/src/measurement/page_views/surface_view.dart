import 'package:restage_cli/src/output/held_count.dart';

import 'page_view_support.dart';

/// Writes one surface's analytics figures.
void renderSurfaceAnalyticsPage(
  StringSink out,
  Map<String, Object?> document,
  int floor,
) {
  final summary = figureAt(document, ['summary', 'value']);
  out
    ..writeln(
      'Views: ${countFigure(summary, ['counts', 'rootPresentations'], floor)}',
    )
    ..writeln(
      'App sessions: ${countFigure(summary, ['counts', 'distinctSessions'], floor)}',
    );
  for (final metric in figureList(document, ['metrics'])) {
    final label = figureAt(metric, ['displayLabel']) ?? kFigureUnavailable;
    final funnel = figureAt(metric, ['summary', 'current', 'result']);
    if (funnel is Map<String, Object?> && funnel['steps'] is List<Object?>) {
      out.writeln(label);
      _writeSteps(out, funnel, figureList(metric, ['stepLabels']), floor);
      continue;
    }
    out.writeln(
      '$label: '
      '${_reading(figureAt(metric, ['history', 'current', 'summary']))}',
    );
  }
  if (figureAt(document, ['metadata', 'surfaceTypeWireName']) == 'paywall') {
    _writePurchaseRate(out, figureAt(document, ['purchaseRate']), floor);
  }
  out
    ..writeln(
      'Version comparisons: '
      '${figureList(document, ['versionComparisons']).length}',
    )
    ..writeln(
      'Experiments: ${plainFigure(document, ['experiments', 'totalMatches'])}',
    );
}

const _missingReasons = [
  'structurallyInapplicable',
  'sourceUnavailable',
  'transportTruncated',
  'domainRejected',
  'observedNoValue',
  'rightCensored',
];

const _allStates = [
  'observedZero',
  'observedValue',
  'observedNoValue',
  'semanticNull',
  'structurallyInapplicable',
  'sourceUnavailable',
  'transportTruncated',
  'domainRejected',
  'rightCensored',
  'latePending',
  'observedCapped',
];

/// A rate reading as a percent with one decimal, or `Not available`.
String _reading(Object? bucket) {
  final BigInt numerator;
  final BigInt admitted;
  final held = figureAt(bucket, ['held']);
  final counts = figureAt(bucket, ['counts']);
  if (held is Map<String, Object?>) {
    final n = BigInt.tryParse('${held['numerator']}');
    final a = BigInt.tryParse('${held['admitted']}');
    if (n == null || a == null) return kFigureUnavailable;
    numerator = n;
    admitted = a;
  } else if (counts is Map<String, Object?>) {
    BigInt at(String key) =>
        BigInt.tryParse('${counts[key] ?? 0}') ?? BigInt.zero;
    final total = _allStates.fold(BigInt.zero, (sum, key) => sum + at(key));
    final excluded = _missingReasons.fold(
      BigInt.zero,
      (sum, key) => sum + at(key),
    );
    numerator = at('observedValue');
    admitted = total - excluded - at('latePending');
  } else {
    return kFigureUnavailable;
  }
  if (admitted <= BigInt.zero) return kFigureUnavailable;
  final tenths =
      (numerator * BigInt.from(1000) + admitted ~/ BigInt.two) ~/ admitted;
  return '${tenths ~/ BigInt.from(10)}.${tenths % BigInt.from(10)}%';
}

/// One line per funnel step: its name, how many reached it and the share of
/// entrants; the last step reads `Finished`.
void _writeSteps(
  StringSink out,
  Map<String, Object?> funnel,
  List<Object?> names,
  int floor,
) {
  final steps = figureList(funnel, ['steps']);
  final entrants = int.tryParse('${funnel['entrantCount']}');
  for (final (index, step) in steps.indexed) {
    final name = index == steps.length - 1
        ? 'Finished'
        : switch (index < names.length ? names[index] : null) {
            'flowCompleted' => 'Finished',
            final String label when label.isNotEmpty => _stepName(label),
            _ => 'Step ${index + 1}',
          };
    final reach = int.tryParse('${figureAt(step, ['reachCount'])}');
    final reached = reach == null ? heldCountText(floor) : groupedCount(reach);
    final rate = reach == null || entrants == null || entrants <= 0
        ? kFigureUnavailable
        : _percent(reach, entrants);
    out.writeln('  $name  $reached reached  $rate');
  }
}

/// A step id in words: underscores and dashes become spaces.
String _stepName(String id) {
  final spaced = id.replaceAll('_', ' ').replaceAll('-', ' ');
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// The purchase rate per version, or why it has none.
void _writePurchaseRate(StringSink out, Object? rate, int floor) {
  if (rate is! Map<String, Object?>) {
    out.writeln('Purchase rate: $kFigureUnavailable');
    return;
  }
  if (rate['status'] == 'commerceNotConnected') {
    out.writeln('Purchase rate: Connect a store to see purchases.');
    return;
  }
  out.writeln('Purchase rate');
  for (final version in figureList(rate, ['versions'])) {
    final purchases = figureAt(version, ['purchases']);
    final views = figureAt(version, ['views']);
    final share = purchases is int && views is int && views > 0
        ? _percent(purchases, views)
        : kFigureUnavailable;
    out.writeln(
      '  v${figureAt(version, ['publishedVersion'])}  '
      '${purchases is int ? groupedCount(purchases) : heldCountText(floor)} '
      'first purchases  '
      '${views is int ? groupedCount(views) : heldCountText(floor)} views  $share',
    );
  }
}

String _percent(int part, int whole) {
  final tenths = (part * 1000 + whole ~/ 2) ~/ whole;
  return '${tenths ~/ 10}.${tenths % 10}%';
}
