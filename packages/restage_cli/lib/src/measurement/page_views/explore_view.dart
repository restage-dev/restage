import 'page_view_support.dart';

/// Writes Explore's figures.
void renderExplorePage(StringSink out, Map<String, Object?> document) {
  final summary = figureAt(document, ['summary', 'value']);
  out
    ..writeln('Views: ${countFigure(summary, ['counts', 'rootPresentations'])}')
    ..writeln(
      'App sessions: ${countFigure(summary, ['counts', 'distinctSessions'])}',
    );
  final groups = figureAt(document, ['split', 'values']);
  out.writeln(
    'Groups: ${groups is List<Object?> ? groups.length : kFigureUnavailable}',
  );
  final held = figureAt(document, ['hiddenSplitCount']);
  if (held is int && held > 0) out.writeln('Groups under 5 users: $held');
}
