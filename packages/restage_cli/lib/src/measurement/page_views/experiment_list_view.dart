import 'page_view_support.dart';

/// Writes the experiments and their status.
void renderExperimentListPage(StringSink out, Map<String, Object?> document) {
  out
    ..writeln(
      'Experiments: ${plainFigure(document, ['roster', 'totalMatches'])}',
    )
    ..writeln(
      'Needs a look: ${plainFigure(document, ['roster', 'attentionCount'])}',
    );
  final headlines = <Object?, String?>{
    for (final entry in figureList(document, ['summaries']))
      figureAt(entry, ['experimentId']): sentenceText(
        figureAt(entry, ['summary', 'headline']),
      ),
  };
  for (final row in figureList(document, ['roster', 'rows'])) {
    final name = figureAt(row, ['label']) ?? figureAt(row, ['id']);
    out.writeln(
      '${name ?? kFigureUnavailable}  '
      '${lifecycleLabel(figureAt(row, ['lifecycle']))}',
    );
    if (headlines[figureAt(row, ['id'])] case final headline?) {
      out.writeln('  $headline');
    }
  }
}
