import 'page_view_support.dart';

/// Writes what the app is sending.
void renderDataHealthPage(
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
    )
    ..writeln(
      'Surfaces set up to record: '
      '${figureList(document, ['manifests']).length}',
    )
    ..writeln(
      'Surface types: ${figureList(document, ['surfaceTypes']).length}',
    );
}
