import 'dart:convert';

import 'package:restage_cli/src/output/held_count.dart';

import 'page_view_support.dart';

/// Writes the three at-a-glance figures as a total and one line per app.
void renderOverviewAppsPage(StringSink out, Map<String, Object?> document) {
  final totals = figureAt(document, ['totals']);
  final apps = figureList(document, ['apps']);
  for (final (label, key, revenue) in const [
    ('App sessions that saw a surface', 'sessions', false),
    ('Onboarding and surveys finished', 'flowsFinished', false),
    ('Revenue from surfaces', 'revenue', true),
  ]) {
    final total = figureAt(totals, [key]);
    out
      ..writeln(label)
      ..writeln(_figure(total, revenue: revenue));
    final totalValue = _amount(total, revenue: revenue);
    for (final app in apps) {
      final name = figureAt(app, ['appName']) ?? figureAt(app, ['appId']);
      final value = _appValue(app, key, revenue: revenue);
      final share = key == 'flowsFinished' || totalValue == null
          ? ''
          : _share(
              _amount(figureAt(app, ['figures', key]), revenue: revenue),
              totalValue,
            );
      out.writeln('  $name  $value$share');
    }
  }
}

/// The per-app lines of each figure, `{app} {value}`, keyed `sessions`,
/// `finished` and `revenue`.
Map<String, List<String>> overviewAppLinesOf(String reply) {
  final Object? envelope;
  try {
    envelope = jsonDecode(reply);
  } on FormatException {
    return const {};
  }
  final apps = figureList(envelope, ['projections', 0, 'document', 'apps']);
  return {
    for (final (name, key, revenue) in const [
      ('sessions', 'sessions', false),
      ('finished', 'flowsFinished', false),
      ('revenue', 'revenue', true),
    ])
      name: [
        for (final app in apps)
          '${figureAt(app, ['appName']) ?? figureAt(app, ['appId'])} '
              '${_appValue(app, key, revenue: revenue)}',
      ],
  };
}

String _appValue(Object? app, String key, {required bool revenue}) {
  final figure = figureAt(app, ['figures', key]);
  if (key == 'flowsFinished') {
    return _rate(figure, figureAt(app, ['figures', 'flowsEligible']));
  }
  return _figure(figure, revenue: revenue);
}

String _share(num? value, num total) =>
    value == null || total <= 0 ? '' : '  ${_percent(value / total)} of total';

/// Finished over eligible views, one decimal; held when either count is.
String _rate(Object? finished, Object? eligible) {
  if (finished is! Map<String, Object?> || eligible is! Map<String, Object?>) {
    return kFigureUnavailable;
  }
  if (finished['unavailable'] == true || eligible['unavailable'] == true) {
    return kFigureUnavailable;
  }
  final done = finished['value'];
  final seen = eligible['value'];
  if (done is! int || seen is! int || seen <= 0) return heldCountText;
  return '${(done * 100 / seen).toStringAsFixed(1)}%';
}

num? _amount(Object? figure, {required bool revenue}) {
  final value = figureAt(figure, [revenue ? 'grossUsdMicros' : 'value']);
  return value is int ? value : null;
}

String _percent(double share) {
  final fixed = (share * 100).toStringAsFixed(1);
  return '${fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed}%';
}

String _figure(Object? figure, {required bool revenue}) {
  if (figure is! Map<String, Object?>) return kFigureUnavailable;
  if (revenue) {
    if (figure['earning'] != true) return kFigureUnavailable;
    final gross = figure['grossUsdMicros'];
    if (gross is! int) return 'Hidden for privacy';
    final cents = (gross + 5000) ~/ 10000;
    final whole = '\$${groupedCount((cents + 50) ~/ 100)}';
    if (figure['approximate'] == true) return '≈$whole';
    return figure['unconverted'] == true ? '$whole so far' : whole;
  }
  if (figure['unavailable'] == true) return kFigureUnavailable;
  final value = figure['value'];
  if (value is! int) return heldCountText;
  final count = groupedCount(value);
  if (figure['atLeast'] == true) return 'At least $count';
  return figure['approximate'] == true ? '≈$count' : count;
}
