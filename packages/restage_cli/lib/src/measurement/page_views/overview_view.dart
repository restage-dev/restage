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
    )
    ..writeln(
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
