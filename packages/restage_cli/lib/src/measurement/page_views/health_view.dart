import 'page_view_support.dart';

/// Writes what the app is sending.
void renderDataHealthPage(StringSink out, Map<String, Object?> document) {
  final summary = figureAt(document, ['summary', 'value']);
  out
    ..writeln('Views: ${countFigure(summary, ['counts', 'rootPresentations'])}')
    ..writeln(
      'App sessions: ${countFigure(summary, ['counts', 'distinctSessions'])}',
    )
    ..writeln(
      'Surfaces set up to record: '
      '${figureList(document, ['manifests']).length}',
    )
    ..writeln(
      'Surface types: ${figureList(document, ['surfaceTypes']).length}',
    );
}
