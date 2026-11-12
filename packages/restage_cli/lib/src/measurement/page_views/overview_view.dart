import 'package:restage_cli/src/output/held_count.dart';

import 'page_view_support.dart';

/// Writes the Analytics overview's figures.
void renderOverviewPage(
  StringSink out,
  Map<String, Object?> document,
  int floor,
) {
  out
    ..writeln(
      'Views: ${countFigure(document, ['sessions', 'counts', 'rootPresentations'], floor)}',
    )
    ..writeln(
      'App sessions: ${countFigure(document, ['sessions', 'counts', 'distinctSessions'], floor)}',
    )
    ..writeln(
      'Views in the previous period: '
      '${countFigure(document, ['previousSessions', 'counts', 'rootPresentations'], floor)}',
    )
    ..writeln('Surfaces: ${plainFigure(document, ['roster', 'totalMatches'])}')
    ..writeln(
      'Needs a look: ${plainFigure(document, ['attention', 'attentionCount'])}',
    );
  _writeAttention(out, figureAt(document, ['attention']));
  out.writeln(
    'Experiments: ${plainFigure(document, ['experiments', 'totalMatches'])}',
  );
  final names = <Object?, Object?>{
    for (final row in figureList(document, ['roster', 'rows']))
      if (figureAt(row, ['surfaceId']) != null)
        figureAt(row, ['surfaceId']):
            figureAt(row, ['surfaceSlug']) ?? figureAt(row, ['label']),
  };
  for (final row in figureList(document, ['rows'])) {
    final id = figureAt(row, ['surfaceId']);
    final name = names[id] ?? id;
    final value = figureAt(row, ['sessions', 'value']);
    final views = value == null
        ? kFigureUnavailable
        : viewsText(countFigure(value, ['counts', 'rootPresentations'], floor));
    out.writeln('$name  $views');
  }
}

/// One line per surface that needs a look: its name, type, reason and what
/// the reason means, as the dashboard's Needs a look card states them.
void _writeAttention(StringSink out, Object? attention) {
  final rows = figureList(attention, ['rows']);
  for (final row in rows) {
    final reasons = [
      for (final reason in figureList(row, ['attentionReasons']))
        if (reason is String) reason,
    ];
    final (reason, hint) = _attentionReason(reasons);
    final type = figureAt(row, ['surfaceType']);
    out.writeln(
      '  ${_surfaceLabel(row)}${type is String ? ' ($type)' : ''}: $reason.'
      '${hint == null ? '' : ' $hint'}',
    );
  }
  final total = int.tryParse('${figureAt(attention, ['totalMatches'])}');
  if (total != null && total > rows.length) {
    out.writeln('  and ${total - rows.length} more');
  }
}

/// The reason a row reads and its hint, in the dashboard's order.
(String, String?) _attentionReason(List<String> reasons) {
  if (reasons.contains('unpublished')) return ('Never published', null);
  if (reasons.contains('noBoundMetrics')) return ('No metric yet', null);
  if (reasons.contains('noData')) {
    return ('No data', 'Its metric has no result for this period.');
  }
  if (reasons.contains('multipleBoundMetrics')) {
    return (
      'No rate metric',
      'This surface’s metrics are all counts or steps. A rate metric gives '
          'it a headline figure.',
    );
  }
  if (reasons.contains('sourceUnavailable')) {
    return (
      'Couldn’t load its result',
      'The data source didn’t respond. Try again.',
    );
  }
  if (reasons.contains('staleEpoch')) {
    return (
      'Result out of date',
      'A newer result replaced this one. Run the command again to see it.',
    );
  }
  if (reasons.contains('incomparable')) {
    return (
      'Result can’t be compared',
      'The results in this period can’t be compared with each other.',
    );
  }
  return ('No result', null);
}

/// A roster row's name, with the dashboard's fallbacks.
String _surfaceLabel(Object? row) {
  final label = figureAt(row, ['label']);
  return switch (figureAt(row, ['nameState'])) {
    'deleted' => 'Deleted surface',
    'present' when label is String && label.trim().isNotEmpty => label,
    _ => 'Unnamed surface',
  };
}
