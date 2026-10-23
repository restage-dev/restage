import 'dart:convert';

import 'package:restage_cli/src/measurement/page_views/page_view_support.dart';
import 'package:restage_cli/src/output/held_count.dart';

/// The three figures the console shows for the overview window.
class OverviewFigures {
  /// Construct figures from their display text.
  const OverviewFigures({
    required this.sessions,
    required this.finished,
    required this.revenue,
    this.appLines = const {},
  });

  /// Every figure unavailable.
  static const unavailable = OverviewFigures(
    sessions: kFigureUnavailable,
    finished: kFigureUnavailable,
    revenue: kFigureUnavailable,
  );

  /// App sessions that saw a surface.
  final String sessions;

  /// Onboarding and surveys finished.
  final String finished;

  /// Revenue from surfaces.
  final String revenue;

  /// One `{app} {value}` line per app under each figure, keyed `sessions`,
  /// `finished` and `revenue`; empty for a single app.
  final Map<String, List<String>> appLines;
}

/// The figures one overview reply states, derived as the dashboard derives
/// them.
OverviewFigures overviewFiguresOf(String reply) {
  final Object? envelope;
  try {
    envelope = jsonDecode(reply);
  } on FormatException {
    return OverviewFigures.unavailable;
  }
  final document = figureAt(envelope, ['projections', 0, 'document']);
  final floor = figureAt(envelope, ['disclosureFloor']);
  if (document is! Map<String, Object?> || floor is! int || floor < 1) {
    return OverviewFigures.unavailable;
  }
  return OverviewFigures(
    sessions: _sessions(document, floor),
    finished: _finished(document, floor),
    revenue: _revenue(document),
  );
}

String _sessions(Map<String, Object?> document, int floor) {
  final counts = figureAt(document, ['sessions', 'counts']);
  if (counts is! Map<String, Object?>) return kFigureUnavailable;
  if (counts['distinctKnownSessions'] is! int) return heldCountText(floor);
  return switch (counts['distinctSessions']) {
    final int exact => groupedCount(exact),
    _ => 'At least ${groupedCount(counts['distinctKnownSessions']! as int)}',
  };
}

String _finished(Map<String, Object?> document, int floor) {
  final series = figureAt(document, ['typedLifecycle']);
  final counts = figureAt(series, ['windowCounts']);
  if (counts is! Map<String, Object?>) return kFigureUnavailable;
  if ((figureAt(series, ['publicationCount']) ?? 0) == 0) {
    return kFigureUnavailable;
  }
  final completed = counts['completed'];
  if (completed is! int) return heldCountText(floor);
  if ((figureAt(series, ['unsupportedPublicationCount']) ?? 0) != 0) {
    return kFigureUnavailable;
  }
  final eligible = counts['eligibleRoots'];
  if (eligible is! int || eligible == 0) return kFigureUnavailable;
  return '${_trimFixed(completed / eligible * 100)}%';
}

String _trimFixed(double value) {
  final fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}

String _revenue(Map<String, Object?> document) {
  var gross = 0;
  var measured = false;
  var unconverted = false;
  for (final row in figureList(document, ['rows'])) {
    for (final version in figureList(row, ['activity', 'values'])) {
      final revenue = figureAt(version, ['series', 'revenue']);
      switch (revenue) {
        case {
          'kind': 'available',
          'grossUsdMicros': final List<Object?> micros,
        }:
          for (final value in micros) {
            if (value is! int) return kFigureUnavailable;
            measured = true;
            gross += value;
          }
        case {'kind': 'unavailable', 'reason': 'currencyRateUnavailable'}:
          unconverted = true;
      }
    }
  }
  if (!measured) return kFigureUnavailable;
  final whole = '\$${groupedCount(_wholeDollars(gross))}';
  return unconverted ? '$whole so far' : whole;
}

/// Micros rounded to whole dollars, half up, through cents as the dashboard
/// does.
int _wholeDollars(int micros) {
  final cents = (micros + 5000) ~/ 10000;
  return (cents + 50) ~/ 100;
}
